<?php
declare(strict_types=1);

/**
 * 登录与会话。
 *
 * 密码只存在 /user/config.local.php 里，用 password_hash 校验；
 * 连续输错按 IP 计数，超过阈值锁定一段时间（存 SQLite，重启不清零）。
 */

function admin_logged_in(): bool
{
    return !empty($_SESSION['admin_ok']);
}

function admin_session_expired(): bool
{
    if (!admin_logged_in()) {
        return true;
    }
    $idle = admin_config()['session_idle_seconds'];
    $last = (int) ($_SESSION['admin_last'] ?? 0);
    return $last > 0 && (admin_now() - $last) > $idle;
}

function touch_admin_session(): void
{
    if (admin_session_expired()) {
        $_SESSION = [];
        session_destroy();
        admin_redirect('/user/?a=login&expired=1');
    }
    $_SESSION['admin_last'] = admin_now();
}

function admin_client_ip(): string
{
    return (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
}

function admin_lock_remaining(): int
{
    $config = admin_config();
    $pdo = admin_db();
    admin_rate_table($pdo);
    $stmt = $pdo->prepare('SELECT count, window_start FROM admin_login_attempts WHERE ip = ?');
    $stmt->execute([admin_client_ip()]);
    $row = $stmt->fetch();
    if (!$row) {
        return 0;
    }
    $window = (int) $config['login_lock_seconds'];
    $elapsed = admin_now() - (int) $row['window_start'];
    if ($elapsed >= $window) {
        return 0;
    }
    if ((int) $row['count'] < (int) $config['login_max_attempts']) {
        return 0;
    }
    return $window - $elapsed;
}

function admin_note_failure(): void
{
    $config = admin_config();
    $pdo = admin_db();
    admin_rate_table($pdo);
    $ip = admin_client_ip();
    $now = admin_now();
    $window = (int) $config['login_lock_seconds'];
    $stmt = $pdo->prepare('SELECT count, window_start FROM admin_login_attempts WHERE ip = ?');
    $stmt->execute([$ip]);
    $row = $stmt->fetch();
    if (!$row || ($now - (int) $row['window_start']) >= $window) {
        $pdo->prepare(
            'INSERT INTO admin_login_attempts(ip, count, window_start) VALUES(?, 1, ?)
             ON CONFLICT(ip) DO UPDATE SET count = 1, window_start = excluded.window_start'
        )->execute([$ip, $now]);
        return;
    }
    $pdo->prepare('UPDATE admin_login_attempts SET count = count + 1 WHERE ip = ?')
        ->execute([$ip]);
}

function admin_clear_failures(): void
{
    $pdo = admin_db();
    admin_rate_table($pdo);
    $pdo->prepare('DELETE FROM admin_login_attempts WHERE ip = ?')
        ->execute([admin_client_ip()]);
}

function admin_login_error(): ?string
{
    if (isset($_GET['expired'])) {
        return '登录已超时，请重新登录。';
    }
    return null;
}

function admin_login(): void
{
    check_csrf();

    $remaining = admin_lock_remaining();
    if ($remaining > 0) {
        render_login('尝试次数过多，请在 ' . ceil($remaining / 60) . ' 分钟后再试。');
        return;
    }

    $config = admin_config();
    $expected = (string) $config['admin_password'];
    $given = (string) ($_POST['password'] ?? '');

    if ($expected === '') {
        render_login('后台密码尚未配置，请检查 /user/config.local.php。');
        return;
    }

    // 配置里必须存 bcrypt 哈希。早期为方便首次部署允许写明文，
    // 但「明文比较」有一个致命副作用：哈希本身会被当作有效密码
    // （提交 $2y$... 那串就能登录）。因此只在确认配置不是哈希时才允许明文。
    $info = password_get_info($expected);
    $isHash = ($info['algo'] ?? null) !== null && ($info['algo'] ?? 0) !== 0;
    $ok = $isHash
        ? password_verify($given, $expected)
        : hash_equals($expected, $given);
    if (!$ok) {
        admin_note_failure();
        render_login('密码不正确。');
        return;
    }

    admin_clear_failures();
    session_regenerate_id(true);
    $_SESSION['admin_ok'] = true;
    $_SESSION['admin_last'] = admin_now();
    unset($_SESSION['csrf']);
    // 登录也留痕：异常时间点的登录比单看业务操作更能说明问题。
    admin_audit('login', '登录成功');
    admin_redirect('/user/');
}

function require_post(): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        http_response_code(405);
        exit('请求方法不允许');
    }
    check_csrf();
}
