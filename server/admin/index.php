<?php
declare(strict_types=1);

/**
 * 凉次元管理后台（/user/）。
 *
 * 只管理账号与发言，不对外提供任何 API；与 /liangciyuan/api.php 共用同一个
 * SQLite 数据库，因此数据始终一致（不要各自维护两份）。
 *
 * 访问控制：
 * - 单一入口密码，配置在 config.local.php 的 admin_password；
 * - 会话用 HttpOnly + SameSite=Strict 的 cookie，30 分钟无操作自动登出；
 * - 所有写操作校验 CSRF token；
 * - 连续输错密码会被临时锁定（存 SQLite，重启不丢）。
 */

session_name('lcy_admin');
session_set_cookie_params([
    'lifetime' => 0,
    'path' => '/user/',
    'httponly' => true,
    'samesite' => 'Strict',
    'secure' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
]);
session_start();

require __DIR__ . '/lib/config.php';
require __DIR__ . '/lib/db.php';
require __DIR__ . '/lib/auth.php';
require __DIR__ . '/lib/view.php';
require __DIR__ . '/lib/actions.php';

$action = (string) ($_GET['a'] ?? '');
$isPost = ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST';

// 登录页不受登录态保护。
if ($action === 'login') {
    if ($isPost) {
        admin_login();
    } else {
        render_login(admin_login_error());
    }
    exit;
}

if ($action === 'logout') {
    $_SESSION = [];
    session_destroy();
    header('Location: /user/');
    exit;
}

if (!admin_logged_in()) {
    header('Location: /user/?a=login');
    exit;
}

touch_admin_session();

switch ($action) {
    case '':
    case 'dashboard':
        render_dashboard();
        break;
    case 'users':
        render_users();
        break;
    case 'user':
        render_user_detail((int) ($_GET['id'] ?? 0));
        break;
    case 'history':
        render_user_detail((int) ($_GET['id'] ?? 0));
        break;
    case 'comments':
        render_comments();
        break;
    case 'danmaku':
        render_danmaku();
        break;
    case 'audit':
        render_audit();
        break;
    case 'ban':
        require_post();
        do_ban();
        break;
    case 'unban':
        require_post();
        do_unban();
        break;
    case 'set-title':
        require_post();
        do_set_title();
        break;
    case 'delete-comment':
        require_post();
        do_delete_comment();
        break;
    case 'restore-comment':
        require_post();
        do_restore_comment();
        break;
    case 'delete-danmaku':
        require_post();
        do_delete_danmaku();
        break;
    default:
        http_response_code(404);
        render_page('未找到', '<p class="muted">页面不存在。</p>');
}