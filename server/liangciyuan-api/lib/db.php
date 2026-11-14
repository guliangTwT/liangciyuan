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
    // busy_timeout 必须最先设置：切 WAL 本身可能遇到 SQLITE_BUSY，
    // 此时若超时还是 0 会直接抛异常。
    $pdo->exec('PRAGMA busy_timeout=5000');
    try {
        // 已经是 WAL 时不要重复设置：这条 PRAGMA 会尝试拿写锁，
        // 每次请求都执行等于给并发同步多加一层争用。
        $mode = (string) $pdo->query('PRAGMA journal_mode')->fetchColumn();
        if (strtolower($mode) !== 'wal') {
            $pdo->exec('PRAGMA journal_mode=WAL');
        }
    } catch (Throwable $ignored) {
        // 已有连接持锁时切换失败并不致命，沿用现有 journal 模式即可。
    }
    $pdo->exec('PRAGMA foreign_keys=ON');

    init_schema($pdo);

    return $pdo;
}

/// 建表与列迁移。
///
/// 以前每次请求都跑一遍这些 DDL：共享主机上每个请求可能是新进程，
/// 于是并发同步时多个请求同时抢写锁、互相等，PUT 会被拖到十几秒，
/// 客户端 12 秒超时后报「同步未完成」。
///
/// 现在用 SQLite 自带的 PRAGMA user_version 做版本闸门：
/// 版本达标时只多一条 SELECT，不再执行任何 DDL。
/// 新增表或列时把 $target 加一即可。
function init_schema(PDO $pdo): void
{
    $target = 3;
    $current = (int) $pdo->query('PRAGMA user_version')->fetchColumn();
    if ($current >= $target) {
        return;
    }

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

    // 自建评分：每人每个条目一票（1~10 分，可改分）。
    // 客户端只显示这里的统计，不再参考 Bangumi 的评分。
    $pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS ratings (
  bangumi_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  score INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (bangumi_id, user_id)
)
SQL);
    $pdo->exec(
        'CREATE INDEX IF NOT EXISTS idx_ratings_bangumi ON ratings(bangumi_id)'
    );
    $pdo->exec(
        'CREATE INDEX IF NOT EXISTS idx_ratings_user ON ratings(user_id, updated_at)'
    );

    // 称号：仅由服务端授予（例如作者），客户端不可自行设置。
    // SQLite 的 ADD COLUMN 不支持 IF NOT EXISTS，先查表结构再补。
    ensure_column($pdo, 'users', 'title', "TEXT NOT NULL DEFAULT ''");

    // 封禁：0 表示正常。停用到的时间点（秒级 Unix 时间戳）拒绝登录与发言。
    // 用时间戳而不是布尔值，管理后台可以直接"封 7 天"。
    ensure_column($pdo, 'users', 'banned_until', 'INTEGER NOT NULL DEFAULT 0');
    // 封禁原因，展示给用户，也便于后台复查。
    ensure_column($pdo, 'users', 'ban_reason', "TEXT NOT NULL DEFAULT ''");

    // 后台操作日志：管理站点 /user/ 会用到。放在这里是为了让「谁先访问」
    // 都能把表补齐，两个入口共用同一个版本号。
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS admin_login_attempts (
           ip TEXT PRIMARY KEY,
           count INTEGER NOT NULL,
           window_start INTEGER NOT NULL
         )'
    );
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS admin_audit_log (
           id INTEGER PRIMARY KEY AUTOINCREMENT,
           action TEXT NOT NULL,
           target_user INTEGER NOT NULL DEFAULT 0,
           detail TEXT NOT NULL DEFAULT "",
           ip TEXT NOT NULL DEFAULT "",
           created_at INTEGER NOT NULL
         )'
    );
    $pdo->exec(
        'CREATE INDEX IF NOT EXISTS idx_admin_audit_time
         ON admin_audit_log(created_at)'
    );

    // 迁移完成后再抬高版本号：万一中途有语句失败，下次请求会重跑一遍
    // （所有语句都是幂等的），不会留下半成品被当作已完成。
    $pdo->exec('PRAGMA user_version = ' . $target);
}

function ensure_column(PDO $pdo, string $table, string $column, string $definition): void
{
    $stmt = $pdo->query('PRAGMA table_info(' . $table . ')');
    foreach ($stmt->fetchAll() as $row) {
        if (strcasecmp((string) $row['name'], $column) === 0) {
            return;
        }
    }
    try {
        $pdo->exec('ALTER TABLE ' . $table . ' ADD COLUMN ' . $column . ' ' . $definition);
    } catch (PDOException $e) {
        // 部署后第一批并发请求会同时判定「列缺失」，第二个 ALTER 会报
        // duplicate column name。这说明列已经被另一个请求加上了，视为成功。
        if (stripos($e->getMessage(), 'duplicate column') === false) {
            throw $e;
        }
    }
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

    // 事务策略必须和调用方一致，否则会嵌套 BEGIN 报
    // "cannot start a transaction within a transaction"，随后的 ROLLBACK
    // 还会把调用方的事务一起回滚（注册/重置就是这种情况）。
    //
    // 注意：PDO 的 inTransaction() 只在 beginTransaction() 之后才为 true，
    // 用 exec('BEGIN ...') 开的事务它看不清；所以全项目统一用
    // beginTransaction()/commit()/rollBack()，不要混用 exec 版。
    $nested = $pdo->inTransaction();
    if (!$nested) {
        $pdo->beginTransaction();
    }
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
        if (!$nested) {
            $pdo->commit();
        }
        $committed = true;
    } catch (Throwable $e) {
        if (!$committed && !$nested) {
            try {
                $pdo->rollBack();
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