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

/// 当前账号是否处于封禁中。
function is_banned(array $user): bool
{
    $until = (int) ($user['banned_until'] ?? 0);
    return $until > 0 && $until > now();
}

/// 封禁原因 + 解封时间的提示文案。
function ban_message(array $user): string
{
    $until = (int) ($user['banned_until'] ?? 0);
    $reason = trim((string) ($user['ban_reason'] ?? ''));
    $when = $until > 0 ? date('Y-m-d H:i', $until) : '';
    $base = $when !== '' ? "你的账号已被停用至 {$when}" : '你的账号已被停用';
    if ($reason !== '') {
        $base .= "（原因：{$reason}）";
    }
    return $base . '，期间无法发表内容。';
}

/// 写操作前调用：封禁中的账号一律拒绝。
///
/// 封禁用 403 而不是 401：401 会让客户端清掉本地登录态，
/// 用户重新登录又失败，反而看不到"为什么被封"。
function require_writable_user(Request $request): array
{
    $user = current_user($request);
    if (is_banned($user)) {
        throw new HttpException(403, ban_message($user));
    }
    return $user;
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
        // 封禁状态：客户端据此在设置页给出提示，而不是让用户反复点"发表"。
        'bannedUntil' => (int) ($user['banned_until'] ?? 0),
        'banReason' => (string) ($user['ban_reason'] ?? ''),
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