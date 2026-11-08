<?php
declare(strict_types=1);

function normalize_email(string $email): string
{
    return strtolower(trim($email));
}

function is_allowed_email(string $email): bool
{
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        return false;
    }
    return (bool) preg_match('/@(qq\.com|vip\.qq\.com|foxmail\.com)$/i', $email);
}

function create_token(int $userId): string
{
    $config = app_config();
    $token = bin2hex(random_bytes(32));
    $now = now();
    $pdo = db();
    $pdo->prepare('DELETE FROM tokens WHERE expires_at < ?')->execute([$now]);
    // 单账号最多保留 10 个有效令牌，避免无限累积。
    $pdo->prepare(
        'DELETE FROM tokens WHERE user_id = ? AND id NOT IN (
           SELECT id FROM tokens WHERE user_id = ? ORDER BY id DESC LIMIT 10
         )'
    )->execute([$userId, $userId]);
    $stmt = $pdo->prepare(
        'INSERT INTO tokens(user_id, token_hash, created_at, expires_at, last_used_at)
         VALUES(?, ?, ?, ?, ?)'
    );
    $stmt->execute([
        $userId,
        hash('sha256', $token),
        $now,
        $now + (int) $config['token_ttl'],
        $now,
    ]);
    return $token;
}

function current_user(Request $request): array
{
    $token = $request->bearerToken();
    if ($token === '') {
        throw new HttpException(401, '请先登录');
    }
    $pdo = db();
    $stmt = $pdo->prepare(
        'SELECT t.id AS token_id, t.expires_at, u.*
         FROM tokens t JOIN users u ON u.id = t.user_id
         WHERE t.token_hash = ?'
    );
    $stmt->execute([hash('sha256', $token)]);
    $row = $stmt->fetch();
    if (!$row) {
        throw new HttpException(401, '登录状态已失效，请重新登录');
    }
    if ((int) $row['expires_at'] < now()) {
        $pdo->prepare('DELETE FROM tokens WHERE id = ?')->execute([(int) $row['token_id']]);
        throw new HttpException(401, '登录状态已过期，请重新登录');
    }
    $pdo->prepare('UPDATE tokens SET last_used_at = ? WHERE id = ?')
        ->execute([now(), (int) $row['token_id']]);
    return $row;
}

function public_profile(array $user): array
{
    $avatar = (string) ($user['avatar'] ?? '');
    return [
        'id' => (int) $user['id'],
        'email' => (string) $user['email'],
        'nickname' => (string) ($user['nickname'] ?? ''),
        'avatar' => $avatar,
        'title' => (string) ($user['title'] ?? ''),
        'emailVerified' => (bool) ($user['email_verified'] ?? false),
        'createdAt' => (int) ($user['created_at'] ?? 0),
    ];
}

function revoke_current_token(Request $request): void
{
    $token = $request->bearerToken();
    if ($token !== '') {
        db()->prepare('DELETE FROM tokens WHERE token_hash = ?')
            ->execute([hash('sha256', $token)]);
    }
}

/// 按 config.local.php 的 granted_titles 表授予称号。
///
/// 称号只能由服务端给：客户端没有任何写入入口。白名单放在服务器配置里，
/// 升级代码不会覆盖，也不需要手工改数据库。
function grant_title_for_email(int $userId, string $email): void
{
    $config = app_config();
    $titles = $config['granted_titles'] ?? [];
    if (!is_array($titles)) {
        return;
    }
    $wanted = (string) ($titles[normalize_email($email)] ?? '');
    if ($wanted === '') {
        return;
    }
    $pdo = db();
    $stmt = $pdo->prepare('SELECT title FROM users WHERE id = ?');
    $stmt->execute([$userId]);
    $current = (string) ($stmt->fetch()['title'] ?? '');
    if ($current === $wanted) {
        return;
    }
    $pdo->prepare('UPDATE users SET title = ?, updated_at = ? WHERE id = ?')
        ->execute([$wanted, now(), $userId]);
}