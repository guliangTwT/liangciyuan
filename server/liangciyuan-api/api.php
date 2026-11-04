<?php
declare(strict_types=1);

/**
 * 凉次元账号 / 云同步服务。
 * 部署在虚拟主机子目录（例如 /liangciyuan/），不依赖 Composer。
 */

require __DIR__ . '/lib/config.php';
require __DIR__ . '/lib/http.php';
require __DIR__ . '/lib/db.php';
require __DIR__ . '/lib/mailer.php';
require __DIR__ . '/lib/auth.php';
require __DIR__ . '/lib/router.php';
require __DIR__ . '/lib/handlers.php';

$router = new Router();
$router->add('GET', '/v1/ping', 'handle_ping');
$router->add('GET', '/v1/health', 'handle_health');
$router->add('POST', '/v1/auth/send-code', 'handle_send_code');
$router->add('POST', '/v1/auth/register', 'handle_register');
$router->add('POST', '/v1/auth/reset', 'handle_reset_password');
$router->add('POST', '/v1/auth/login', 'handle_login');
$router->add('POST', '/v1/auth/logout', 'handle_logout');
$router->add('GET', '/v1/me', 'handle_me');
$router->add('PATCH', '/v1/me', 'handle_update_me');
$router->add('POST', '/v1/me/avatar', 'handle_upload_avatar');
$router->add('GET', '/v1/avatar/{id}', 'handle_get_avatar');
$router->add('GET', '/v1/sync', 'handle_sync_list');
$router->add('GET', '/v1/sync/{kind}', 'handle_sync_get');
$router->add('PUT', '/v1/sync/{kind}', 'handle_sync_put');
$router->add('DELETE', '/v1/sync/{kind}', 'handle_sync_delete');
$router->add('GET', '/v1/comments', 'handle_comments_list');
$router->add('POST', '/v1/comments', 'handle_comments_create');
$router->add('DELETE', '/v1/comments/{id}', 'handle_comments_delete');
$router->add('GET', '/v1/users/{id}', 'handle_user_profile');

$router->dispatch(Request::fromGlobals());