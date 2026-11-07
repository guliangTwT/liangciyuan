<?php
declare(strict_types=1);

// 仅本地 CLI 使用：授予/撤销用户称号。请勿部署到线上目录
// （部署脚本会排除 tool/ 目录）。
//
// 用法：
//   php tool/title.php list
//   php tool/title.php set <用户ID或邮箱> <称号>
//   php tool/title.php clear <用户ID或邮箱>

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require __DIR__ . '/../lib/config.php';
require __DIR__ . '/../lib/http.php';
require __DIR__ . '/../lib/db.php';

$command = (string) ($argv[1] ?? 'list');
$target = (string) ($argv[2] ?? '');
$title = (string) ($argv[3] ?? '');
$pdo = db();

function find_user(PDO $pdo, string $target): ?array
{
    if ($target === '') {
        return null;
    }
    $stmt = ctype_digit($target)
        ? $pdo->prepare('SELECT id, email, nickname, title FROM users WHERE id = ?')
        : $pdo->prepare('SELECT id, email, nickname, title FROM users WHERE email = ?');
    $stmt->execute([ctype_digit($target) ? (int) $target : strtolower($target)]);
    $row = $stmt->fetch();
    return $row ?: null;
}

switch ($command) {
    case 'list':
        $rows = $pdo->query(
            'SELECT id, email, nickname, title FROM users
             WHERE title <> "" ORDER BY id ASC'
        )->fetchAll();
        if (!$rows) {
            echo "（还没有任何用户拥有称号）\n";
            break;
        }
        foreach ($rows as $row) {
            printf(
                "%d\t%s\t%s\t%s\n",
                (int) $row['id'],
                (string) $row['email'],
                (string) $row['nickname'],
                (string) $row['title']
            );
        }
        break;

    case 'set':
        if ($title === '') {
            fwrite(STDERR, "用法：php tool/title.php set <用户ID或邮箱> <称号>\n");
            exit(1);
        }
        $length = mb_strlen($title, 'UTF-8');
        if ($length < 1 || $length > 16) {
            fwrite(STDERR, "称号长度需为 1~16 个字符\n");
            exit(1);
        }
        $user = find_user($pdo, $target);
        if ($user === null) {
            fwrite(STDERR, "找不到用户：{$target}\n");
            exit(1);
        }
        $pdo->prepare('UPDATE users SET title = ?, updated_at = ? WHERE id = ?')
            ->execute([$title, time(), (int) $user['id']]);
        printf("已设置：%s → %s\n", (string) $user['email'], $title);
        break;

    case 'clear':
        $user = find_user($pdo, $target);
        if ($user === null) {
            fwrite(STDERR, "找不到用户：{$target}\n");
            exit(1);
        }
        $pdo->prepare('UPDATE users SET title = "", updated_at = ? WHERE id = ?')
            ->execute([time(), (int) $user['id']]);
        printf("已清除：%s\n", (string) $user['email']);
        break;

    default:
        fwrite(STDERR, "未知命令：{$command}\n");
        exit(1);
}
