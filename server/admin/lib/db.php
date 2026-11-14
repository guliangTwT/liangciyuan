<?php
declare(strict_types=1);

function admin_db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    $config = admin_config();
    $path = $config['db_path'];
    $dir = dirname($path);
    if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
        throw new RuntimeException('无法创建数据目录：' . $dir);
    }
    $pdo = new PDO('sqlite:' . $path);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    // busy_timeout 必须最先设置：切 WAL 本身可能遇到 SQLITE_BUSY。
    $pdo->exec('PRAGMA busy_timeout=5000');
    try {
        // 已经是 WAL 时不重复设置，避免每次请求都尝试拿写锁。
        $mode = (string) $pdo->query('PRAGMA journal_mode')->fetchColumn();
        if (strtolower($mode) !== 'wal') {
            $pdo->exec('PRAGMA journal_mode=WAL');
        }
    } catch (Throwable $ignored) {
        // 并发切换失败不致命，沿用现有 journal 模式。
    }
    admin_ensure_schema($pdo);
    return $pdo;
}

/// 建表与列迁移。
///
/// 后台可能比账号接口先被访问，所以这里也要能把基础表建出来；
/// 与 liangciyuan-api/lib/db.php 共用同一个 SQLite 与同一个版本号，
/// 谁先访问谁迁移，另一个看到版本达标就只多一条 SELECT。
///
/// 版本 3 = 在 2 的基础上增加后台操作日志表。
function admin_ensure_schema(PDO $pdo): void
{
    $target = 3;
    if ((int) $pdo->query('PRAGMA user_version')->fetchColumn() >= $target) {
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

    // 后台自己的锁定记录表（与业务表分开，避免污染账号库结构）。
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS admin_login_attempts (
           ip TEXT PRIMARY KEY,
           count INTEGER NOT NULL,
           window_start INTEGER NOT NULL
         )'
    );

    // 后台操作流水：谁在什么时候封了谁、删了哪条评论。
    // 出问题时能回溯，也不至于把日志散落到各表里。
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

    // users 的扩展列：老库补列，新库直接建在上面那张表里。
    admin_ensure_column($pdo, 'users', 'title', "TEXT NOT NULL DEFAULT ''");
    admin_ensure_column($pdo, 'users', 'banned_until', 'INTEGER NOT NULL DEFAULT 0');
    admin_ensure_column($pdo, 'users', 'ban_reason', "TEXT NOT NULL DEFAULT ''");

    // 所有语句幂等，中途失败下次会重跑；成功后才抬版本号。
    $pdo->exec('PRAGMA user_version = ' . $target);
}

function admin_ensure_column(PDO $pdo, string $table, string $column, string $definition): void
{
    if (admin_column_exists($pdo, $table, $column)) {
        return;
    }
    try {
        $pdo->exec('ALTER TABLE ' . $table . ' ADD COLUMN ' . $column . ' ' . $definition);
    } catch (PDOException $e) {
        // 并发部署时第二个 ALTER 会报 duplicate column，视为成功。
        if (stripos($e->getMessage(), 'duplicate column') === false) {
            throw $e;
        }
    }
}

function admin_column_exists(PDO $pdo, string $table, string $column): bool
{
    foreach ($pdo->query('PRAGMA table_info(' . $table . ')')->fetchAll() as $row) {
        if (strcasecmp((string) $row['name'], $column) === 0) {
            return true;
        }
    }
    return false;
}

/// 后台锁定记录表。低概率清理过期记录，避免失败 IP 只增不减。
function admin_rate_table(PDO $pdo): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS admin_login_attempts (
           ip TEXT PRIMARY KEY,
           count INTEGER NOT NULL,
           window_start INTEGER NOT NULL
         )'
    );
    if (random_int(1, 100) === 1) {
        $pdo->prepare('DELETE FROM admin_login_attempts WHERE window_start < ?')
            ->execute([time() - 86400]);
    }
}

function admin_now(): int
{
    return time();
}

function admin_esc(?string $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/// 读取 GET 里的字符串参数并截断，避免超长输入进 SQL / 页面。
function admin_q(string $key, string $default = '', int $maxLength = 100): string
{
    $value = $_GET[$key] ?? $default;
    if (!is_string($value)) {
        return $default;
    }
    $value = trim($value);
    return mb_substr($value, 0, $maxLength, 'UTF-8');
}

function admin_int(string $key, int $default = 0): int
{
    $value = $_GET[$key] ?? null;
    return is_string($value) ? (int) $value : $default;
}

/// 分页计算。total=0 时也返回可用的页码信息，方便页面统一渲染。
function admin_paginate(int $total, int $perPage, int $page): array
{
    $perPage = max(1, $perPage);
    $pages = max(1, (int) ceil($total / $perPage));
    $page = min(max(1, $page), $pages);
    $offset = ($page - 1) * $perPage;
    return [
        'total' => $total,
        'perPage' => $perPage,
        'page' => $page,
        'pages' => $pages,
        'offset' => $offset,
        'from' => $total === 0 ? 0 : $offset + 1,
        'to' => min($total, $offset + $perPage),
    ];
}

/// 记录一条后台操作。写日志失败不应该让主操作回滚，吞掉异常即可。
function admin_audit(string $action, string $detail = '', int $targetUser = 0): void
{
    try {
        admin_db()
            ->prepare(
                'INSERT INTO admin_audit_log(action, target_user, detail, ip, created_at)
                 VALUES(?, ?, ?, ?, ?)'
            )
            ->execute([$action, $targetUser, $detail, admin_client_ip(), admin_now()]);
    } catch (Throwable $ignored) {
    }
}

/// 跳转到站内页面。
///
/// 只接受以 /user 开头的相对路径：`back` 来自表单字段，是用户可提交的内容，
/// 直接拼进 Location 会变成开放重定向（`//evil.com` 之类）。
/// 虽然需要有效 CSRF 才能提交，仍不该留这个口子。
function admin_redirect(string $path): void
{
    $isInternal = str_starts_with($path, '/user')
        && !str_starts_with($path, '//')
        && !str_contains($path, "\r")
        && !str_contains($path, "\n");
    header('Location: ' . ($isInternal ? $path : '/user/'));
    exit;
}

function admin_flash(string $message, string $kind = 'ok'): void
{
    $_SESSION['flash'] = ['message' => $message, 'kind' => $kind];
}

function admin_take_flash(): ?array
{
    $flash = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);
    return is_array($flash) ? $flash : null;
}

function csrf_token(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return (string) $_SESSION['csrf'];
}

function csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="' . admin_esc(csrf_token()) . '">';
}

function check_csrf(): void
{
    $sent = (string) ($_POST['csrf'] ?? '');
    if ($sent === '' || !hash_equals(csrf_token(), $sent)) {
        http_response_code(400);
        exit('会话已过期，请刷新页面重试。');
    }
}
