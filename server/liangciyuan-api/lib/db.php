<?php
declare(strict_types=1);

function db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $config = app_config();
    $path = $config['db_path'];
    $dir = dirname($path);
    if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
        throw new RuntimeException('无法创建数据目录');
    }

    $pdo = new PDO('sqlite:' . $path);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    $pdo->exec('PRAGMA journal_mode=WAL');
    $pdo->exec('PRAGMA foreign_keys=ON');
    $pdo->exec('PRAGMA busy_timeout=5000');

    $pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  nickname TEXT NOT NULL DEFAULT '',
  avatar TEXT NOT NULL DEFAULT '',
  email_verified INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
SQL);

    $pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS email_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  used INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  ip TEXT NOT NULL DEFAULT ''
)
SQL);
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_email_codes_email ON email_codes(email, created_at)');

    $pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL DEFAULT 0
)
SQL);
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_tokens_user ON tokens(user_id)');

    $pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS sync_blobs (
  user_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  payload TEXT NOT NULL,
  checksum TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, kind)
)
SQL);

    $pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_type TEXT NOT NULL DEFAULT 'bangumi',
  target_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  content TEXT NOT NULL,
  spoiler INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)
SQL);
    $pdo->exec(
        'CREATE INDEX IF NOT EXISTS idx_comments_target
         ON comments(target_type, target_id, created_at, id)'
    );
    $pdo->exec(
        'CREATE INDEX IF NOT EXISTS idx_comments_user ON comments(user_id, created_at)'
    );

    // 自建弹幕：按 (番剧, 集数) 隔离，position_ms 为播放位置。
    // mode 沿用 DanDanPlay 语义：1 滚动 / 4 底部 / 5 顶部。
    $pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS danmaku (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bangumi_id INTEGER NOT NULL,
  episode INTEGER NOT NULL,
  position_ms INTEGER NOT NULL,
  mode INTEGER NOT NULL DEFAULT 1,
  color INTEGER NOT NULL DEFAULT 16777215,
  content TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
)
SQL);
    $pdo->exec(
        'CREATE INDEX IF NOT EXISTS idx_danmaku_target
         ON danmaku(bangumi_id, episode, position_ms, id)'
    );
    $pdo->exec(
        'CREATE INDEX IF NOT EXISTS idx_danmaku_user ON danmaku(user_id, created_at)'
    );

    $pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS rate_limits (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  window_start INTEGER NOT NULL
)
SQL);

    // 称号：仅由服务端授予（例如作者），客户端不可自行设置。
    // SQLite 的 ADD COLUMN 不支持 IF NOT EXISTS，先查表结构再补。
    ensure_column($pdo, 'users', 'title', "TEXT NOT NULL DEFAULT ''");

    return $pdo;
}

function ensure_column(PDO $pdo, string $table, string $column, string $definition): void
{
    $stmt = $pdo->query('PRAGMA table_info(' . $table . ')');
    foreach ($stmt->fetchAll() as $row) {
        if (strcasecmp((string) $row['name'], $column) === 0) {
            return;
        }
    }
    $pdo->exec('ALTER TABLE ' . $table . ' ADD COLUMN ' . $column . ' ' . $definition);
}

function rate_limit(string $key, int $limit, int $windowSeconds): void
{
    if ($limit <= 0) {
        return;
    }
    $pdo = db();
    $now = now();
    // 低概率清理过期计数，避免表无限增长。
    if (random_int(1, 100) === 1) {
        $pdo->prepare('DELETE FROM rate_limits WHERE window_start < ?')
            ->execute([$now - 86400]);
    }
    // WAL 下延迟事务先读后写会撞 SQLITE_BUSY_SNAPSHOT（busy_timeout 不生效），
    // 限流这类「读-改-写」必须用 IMMEDIATE 事务直接拿写锁。
    $pdo->exec('BEGIN IMMEDIATE');
    $committed = false;
    try {
        $stmt = $pdo->prepare('SELECT count, window_start FROM rate_limits WHERE key = ?');
        $stmt->execute([$key]);
        $row = $stmt->fetch();
        if (!$row || ($now - (int) $row['window_start']) >= $windowSeconds) {
            $pdo->prepare(
                'INSERT INTO rate_limits(key, count, window_start) VALUES(?, 1, ?)
                 ON CONFLICT(key) DO UPDATE SET count = 1, window_start = excluded.window_start'
            )->execute([$key, $now]);
        } elseif ((int) $row['count'] >= $limit) {
            throw new HttpException(429, '请求过于频繁，请稍后再试');
        } else {
            $pdo->prepare('UPDATE rate_limits SET count = count + 1 WHERE key = ?')->execute([$key]);
        }
        $pdo->exec('COMMIT');
        $committed = true;
    } catch (Throwable $e) {
        if (!$committed) {
            try {
                $pdo->exec('ROLLBACK');
            } catch (Throwable $ignored) {
                // 事务可能已被 SQLite 自动回滚。
            }
        }
        throw $e;
    }
}

function client_ip(): string
{
    return (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
}