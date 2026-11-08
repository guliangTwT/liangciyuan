<?php
declare(strict_types=1);

/**
 * 管理后台配置。
 *
 * 与凉次元账号后端共用同一份 SQLite。后台的 config.local.php 放在
 * /user/ 下（不入库），只存管理密码；数据库路径与账号后端保持一致。
 */
function admin_config(): array
{
    static $config = null;
    if ($config !== null) {
        return $config;
    }

    // __DIR__ 是 /user/lib，站点根要往上两层。
    // 数据库与账号后端（/liangciyuan/api.php）共用同一份 SQLite。
    $siteRoot = dirname(dirname(__DIR__));
    $config = [
        'db_path' => $siteRoot . '/data/liangciyuan.sqlite',
        // 管理密码：必须在 config.local.php 里覆盖，不设默认值。
        'admin_password' => '',
        // 输错密码锁定策略
        'login_max_attempts' => 5,
        'login_lock_seconds' => 900,
        'session_idle_seconds' => 1800,
    ];

    // config.local.php 放在 /user/ 根（与 index.php 同级），不在 lib/ 里。
    $local = dirname(__DIR__) . '/config.local.php';
    if (is_file($local)) {
        $overrides = require $local;
        if (is_array($overrides)) {
            $config = array_merge($config, $overrides);
        }
    }

    return $config;
}
