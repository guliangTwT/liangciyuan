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
CREATE TABLE IF NOT EXISTS rate_limits (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  window_start INTEGER NOT NULL
)
SQL);

    return $pdo;
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
    $pdo->beginTransaction();
    try {
        $stmt = $pdo->prepare('SELECT count, window_start FROM rate_limits WHERE key = ?');
        $stmt->execute([$key]);
        $row = $stmt->fetch();
        if (!$row || ($now - (int) $row['window_start']) >= $windowSeconds) {
            $pdo->prepare(
                'INSERT INTO rate_limits(key, count, window_start) VALUES(?, 1, ?)
                 ON CONFLICT(key) DO UPDATE SET count = 1, window_start = excluded.window_start'
            )->execute([$key, $now]);
        } else {
            if ((int) $row['count'] >= $limit) {
                $pdo->commit();
                throw new HttpException(429, '请求过于频繁，请稍后再试');
            }
            $pdo->prepare('UPDATE rate_limits SET count = count + 1 WHERE key = ?')->execute([$key]);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}

function client_ip(): string
{
    return (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
}