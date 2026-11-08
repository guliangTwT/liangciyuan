<?php
declare(strict_types=1);

function app_config(): array
{
    static $config = null;
    if ($config !== null) {
        return $config;
    }

    $base = dirname(__DIR__);
    $shared = dirname($base) . '/data';
    $config = [
        // 数据放在站点根目录的 data/ 下（根站伪静态已禁止直接访问该目录）。
        'db_path' => $shared . '/liangciyuan.sqlite',
        'data_dir' => $shared,
        'avatar_dir' => $shared . '/liangciyuan-avatars',
        'mail_host' => 'ssl://smtp.qq.com',
        'mail_port' => 465,
        'mail_user' => '',
        'mail_auth' => '',
        'mail_from_name' => '凉次元',
        'code_ttl' => 600,
        'code_resend_seconds' => 60,
        'code_ip_hourly_limit' => 20,
        'code_email_hourly_limit' => 5,
        'token_ttl' => 15552000,
        'max_payload_bytes' => 8388608,
        'max_sync_kinds' => 64,
        'max_sync_total_bytes' => 67108864,
        'max_avatar_bytes' => 2097152,
        // 服务端授予的称号：键为邮箱（小写），值为称号。
        // 注册与登录时按此表自动同步，避免手工改库；表里没有的账号称号为空。
        'granted_titles' => [],
    ];

    $local = $base . '/config.local.php';
    if (is_file($local)) {
        $overrides = require $local;
        if (is_array($overrides)) {
            $config = array_merge($config, $overrides);
        }
    }

    return $config;
}