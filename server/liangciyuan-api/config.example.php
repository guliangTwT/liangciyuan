<?php
// 复制为 config.local.php 并填入真实值（不要提交到仓库）。
return [
    // QQ 邮箱发件账号，例如 123456789@qq.com
    'mail_user' => '',
    // QQ 邮箱设置 -> 账户 -> POP3/SMTP 服务 -> 授权码
    'mail_auth' => '',
    'mail_from_name' => '凉次元',
    // 服务端授予的称号：键为小写邮箱，值为称号（1~16 字）。
    // 注册与登录时自动同步，客户端没有任何设置入口。
    // 'granted_titles' => [
    //     '123456789@qq.com' => '凉次元作者',
    // ],
    // 可选：调整数据库与头像目录
    // 'db_path' => dirname(__DIR__, 2) . '/data/liangciyuan.sqlite',
    // 'avatar_dir' => dirname(__DIR__, 2) . '/data/liangciyuan-avatars',
];
