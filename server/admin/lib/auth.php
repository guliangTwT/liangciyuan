<?php
declare(strict_types=1);

/**
 * 登录与会话。
 *
 * 密码只存在 /user/config.local.php 里，用 password_hash 校验；
 * 连续输错按 IP 计数，超过阈值锁定一段时间（存 SQLite，重启不清零）。
 *
 * 另外支持「30 天内免密登录」：勾选后种一枚独立 cookie，令牌哈希存库。
 * 会话本身仍是 30 分钟无操作过期；免密 cookie 只负责把已过期的会话
 * 重新建立起来，两者互不替代。
 */

const ADMIN_REMEMBER_COOKIE = 'lcy_admin_remember';
const ADMIN_REMEMBER_DAYS = 30;

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

/// 校验会话；过期时先尝试用免密 cookie 续期，续不上才跳登录页。
///
/// 这是唯一的登录闸门：调用方不需要（也不应该）再单独判断
/// `admin_logged_in()`，否则免密续期永远走不到。
function touch_admin_session(): void
{
    if (admin_session_expired()) {
        if (!admin_try_remember_login()) {
            $_SESSION = [];
            if (session_status() === PHP_SESSION_ACTIVE) {
                session_destroy();
            }
            admin_redirect('/user/?a=login&expired=1');
        }
    }
    // 续期成功也要刷新时间戳：否则本次请求结束后会话仍停留在
    // 「已过期」状态，下一个请求又得重新续期一次。
    $_SESSION['admin_last'] = admin_now();
}

function admin_client_ip(): string
{
    return (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
}

function admin_user_agent(): string
{
    return mb_substr((string) ($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 200, 'UTF-8');
}

// ---------------------------------------------------------------------------
// 免密登录
// ---------------------------------------------------------------------------

/// cookie 的 path 必须和 session cookie 一致，否则两者不会一起失效。
///
/// SameSite 用 Lax 而不是 Strict：Strict 只在「同站导航」时发送，
/// 用户从书签、直接输入网址或点外部链接打开后台时浏览器不会带上它，
/// 「30 天免密」就直接失效了。Lax 会在顶层 GET 导航时发送，但跨站
/// POST 依然不带，配合 CSRF token 已经足够。
function admin_remember_cookie_options(int $expires): array
{
    return [
        'expires' => $expires,
        'path' => '/user/',
        'httponly' => true,
        'samesite' => 'Lax',
        'secure' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
    ];
}

/// 登录成功后签发一枚免密令牌。
///
/// 每次登录都换新令牌，并清掉过期的、以及同一台设备（IP + UA 相同）的旧令牌：
/// 否则反复登录会在库里堆出十几枚指向同一台机器的凭证，撤销时也分不清哪枚是当前的。
function admin_issue_remember_token(): void
{
    $token = bin2hex(random_bytes(32));
    $now = admin_now();
    $expires = $now + 86400 * ADMIN_REMEMBER_DAYS;
    $ip = admin_client_ip();
    $agent = admin_user_agent();
    $pdo = admin_db();
    $pdo->prepare('DELETE FROM admin_remember_tokens WHERE expires_at <= ?')
        ->execute([$now]);
    $pdo->prepare('DELETE FROM admin_remember_tokens WHERE ip = ? AND user_agent = ?')
        ->execute([$ip, $agent]);
    $pdo->prepare(
        'INSERT INTO admin_remember_tokens(token_hash, ip, user_agent, created_at, expires_at, last_used_at)
         VALUES(?, ?, ?, ?, ?, ?)'
    )->execute([
        hash('sha256', $token),
        $ip,
        $agent,
        $now,
        $expires,
        $now,
    ]);
    setcookie(ADMIN_REMEMBER_COOKIE, $token, admin_remember_cookie_options($expires));
}

/// 清掉当前浏览器持有的免密令牌（退出登录时调用）。
function admin_revoke_remember_token(): void
{
    $token = (string) ($_COOKIE[ADMIN_REMEMBER_COOKIE] ?? '');
    if ($token !== '') {
        admin_db()
            ->prepare('DELETE FROM admin_remember_tokens WHERE token_hash = ?')
            ->execute([hash('sha256', $token)]);
    }
    // 立即失效：过期时间设成过去，浏览器会删掉它。
    setcookie(ADMIN_REMEMBER_COOKIE, '', admin_remember_cookie_options(admin_now() - 3600));
}

/// 关闭免密登录（用户主动取消勾选，或安全事件后统一作废）。
function admin_revoke_all_remember_tokens(): void
{
    admin_db()->exec('DELETE FROM admin_remember_tokens');
}

/// 用 cookie 里的令牌恢复会话。
///
/// 三条硬性校验：
/// 1. 令牌存在且未过期；
/// 2. 来源 IP 与签发时一致——后台是单人使用，IP 变化通常意味着 cookie 被复制；
/// 3. User-Agent 一致，同理。
/// 任一不符就当作未登录，并作废这枚令牌，避免它被反复试探。
function admin_try_remember_login(): bool
{
    $token = (string) ($_COOKIE[ADMIN_REMEMBER_COOKIE] ?? '');
    if ($token === '' || strlen($token) !== 64) {
        return false;
    }
    $hash = hash('sha256', $token);
    $pdo = admin_db();
    $stmt = $pdo->prepare('SELECT * FROM admin_remember_tokens WHERE token_hash = ?');
    $stmt->execute([$hash]);
    $row = $stmt->fetch();
    if (!$row) {
        return false;
    }
    if ((int) $row['expires_at'] <= admin_now()) {
        $pdo->prepare('DELETE FROM admin_remember_tokens WHERE token_hash = ?')
            ->execute([$hash]);
        admin_revoke_remember_token();
        return false;
    }
    $sameIp = hash_equals((string) $row['ip'], admin_client_ip());
    $sameAgent = hash_equals((string) $row['user_agent'], admin_user_agent());
    if (!$sameIp || !$sameAgent) {
        // 令牌被搬到别处使用：直接作废，宁可让用户重新输密码。
        $pdo->prepare('DELETE FROM admin_remember_tokens WHERE token_hash = ?')
            ->execute([$hash]);
        admin_revoke_remember_token();
        return false;
    }

    // 恢复会话时必须换 session id，防止 session fixation。
    // 只有会话真正启动时才能换；否则 PHP 会抛「no active session」警告
    // （例如被别处的脚本 include 时）。
    if (session_status() === PHP_SESSION_ACTIVE) {
        session_regenerate_id(true);
    }
    $_SESSION = [
        'admin_ok' => true,
        'admin_last' => admin_now(),
    ];
    $pdo->prepare('UPDATE admin_remember_tokens SET last_used_at = ? WHERE token_hash = ?')
        ->execute([admin_now(), $hash]);
    return true;
}

/// 是否存在可用的免密令牌（用于登录页提示「已记住本设备」）。
function admin_has_remember_token(): bool
{
    $token = (string) ($_COOKIE[ADMIN_REMEMBER_COOKIE] ?? '');
    if ($token === '' || strlen($token) !== 64) {
        return false;
    }
    $stmt = admin_db()->prepare(
        'SELECT expires_at FROM admin_remember_tokens WHERE token_hash = ?'
    );
    $stmt->execute([hash('sha256', $token)]);
    $row = $stmt->fetch();
    return $row !== false && (int) $row['expires_at'] > admin_now();
}

// ---------------------------------------------------------------------------
// 失败计数
// ---------------------------------------------------------------------------

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

    // 勾选了「30 天内免密」才种 cookie；没勾则顺手作废旧的那枚，
    // 否则「取消勾选后重新登录」仍然会自动登录，与用户预期相反。
    if (!empty($_POST['remember'])) {
        admin_issue_remember_token();
        admin_audit('login', '登录成功（已记住本设备 30 天）');
    } else {
        admin_revoke_remember_token();
        admin_audit('login', '登录成功');
    }
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
