<?php
declare(strict_types=1);

// 本地联调用：直接写入一条验证码，不经过 SMTP。请勿部署到线上。
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
require __DIR__ . '/../lib/config.php';
require __DIR__ . '/../lib/http.php';
require __DIR__ . '/../lib/db.php';

$email = strtolower($argv[1] ?? 'reviewer@qq.com');
$code = (string) ($argv[2] ?? '123456');

db()->prepare(
    'INSERT INTO email_codes(email, code_hash, expires_at, used, created_at, ip)
     VALUES(?, ?, ?, 0, ?, ?)'
)->execute([$email, hash('sha256', $code), time() + 600, time(), '127.0.0.1']);

echo "seeded {$email} code {$code}\n";