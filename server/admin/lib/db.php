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
    if (!is_file($path)) {
        throw new RuntimeException('数据库不存在：' . $path);
    }
    $pdo = new PDO('sqlite:' . $path);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
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

/// 后台可能比 API 先被访问，所以自己也要补齐新增列。
/// 与 liangciyuan-api/lib/db.php 的 init_schema 共用同一个版本号：
/// 谁先访问谁迁移，另一个看到版本达标就跳过，避免每次请求都跑 DDL。
function admin_ensure_schema(PDO $pdo): void
{
    $target = 2;
    if ((int) $pdo->query('PRAGMA user_version')->fetchColumn() >= $target) {
        return;
    }
    $columns = [
        'title' => "TEXT NOT NULL DEFAULT ''",
        'banned_until' => 'INTEGER NOT NULL DEFAULT 0',
        'ban_reason' => "TEXT NOT NULL DEFAULT ''",
    ];
    $existing = [];
    foreach ($pdo->query('PRAGMA table_info(users)')->fetchAll() as $row) {
        $existing[strtolower((string) $row['name'])] = true;
    }
    foreach ($columns as $name => $definition) {
        if (isset($existing[$name])) {
            continue;
        }
        try {
            $pdo->exec('ALTER TABLE users ADD COLUMN ' . $name . ' ' . $definition);
        } catch (PDOException $e) {
            if (stripos($e->getMessage(), 'duplicate column') === false) {
                throw $e;
            }
        }
    }
    $pdo->exec('PRAGMA user_version = ' . $target);
}

function admin_column_exists(PDO $pdo, string $table, string $column): bool
{
    $stmt = $pdo->query('PRAGMA table_info(' . $table . ')');
    foreach ($stmt->fetchAll() as $row) {
        if (strcasecmp((string) $row['name'], $column) === 0) {
            return true;
        }
    }
    return false;
}

/// 后台自己的锁定记录表（与业务表分开，避免污染账号库结构）。
function admin_rate_table(PDO $pdo): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS admin_login_attempts (
           ip TEXT PRIMARY KEY,
           count INTEGER NOT NULL,
           window_start INTEGER NOT NULL
         )'
    );
}

function admin_now(): int
{
    return time();
}

function admin_esc(?string $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function admin_redirect(string $path): void
{
    header('Location: ' . $path);
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
