<?php
declare(strict_types=1);

function api_base_url(): string
{
    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $host = (string) ($_SERVER['HTTP_HOST'] ?? 'localhost');
    $script = (string) ($_SERVER['SCRIPT_NAME'] ?? '/api.php');
    return $scheme . '://' . $host . $script;
}

function avatar_url(array $user): string
{
    $avatar = (string) ($user['avatar'] ?? '');
    if ($avatar === '') {
        return '';
    }
    return api_base_url() . '/v1/avatar/' . (int) $user['id']
        . '?v=' . rawurlencode($avatar);
}

function handle_ping(Request $request): void
{
    Response::ok(['service' => 'liangciyuan-account', 'time' => now()]);
}

function handle_health(Request $request): void
{
    $config = app_config();
    $dbOk = true;
    $error = '';
    try {
        db()->query('SELECT 1');
    } catch (Throwable $e) {
        $dbOk = false;
        $error = $e->getMessage();
    }
    Response::json([
        'ok' => $dbOk,
        'db' => $dbOk,
        'mailConfigured' => trim((string) $config['mail_user']) !== ''
            && trim((string) $config['mail_auth']) !== '',
        'error' => $error,
    ], $dbOk ? 200 : 500);
}

function handle_send_code(Request $request): void
{
    $config = app_config();
    $body = $request->json();
    $email = normalize_email((string) ($body['email'] ?? ''));
    // register：注册前验证；reset：给已有账号发重置密码验证码。
    $purpose = ($body['purpose'] ?? '') === 'reset' ? 'reset' : 'register';
    if (!is_allowed_email($email)) {
        throw new HttpException(400, '只支持 QQ 邮箱（@qq.com / @foxmail.com）');
    }

    rate_limit('send-code:ip:' . client_ip(), (int) $config['code_ip_hourly_limit'], 3600);
    rate_limit('send-code:email:' . $email, (int) $config['code_email_hourly_limit'], 3600);

    $pdo = db();
    // 清理过期与已使用的验证码，避免表无限增长。
    $pdo->prepare('DELETE FROM email_codes WHERE expires_at < ? OR (used = 1 AND created_at < ?)')
        ->execute([now(), now() - 86400]);
    $stmt = $pdo->prepare('SELECT id FROM users WHERE email = ?');
    $stmt->execute([$email]);
    $existingUser = $stmt->fetch();
    if ($purpose === 'register' && $existingUser) {
        throw new HttpException(409, '该邮箱已注册，请直接登录');
    }
    if ($purpose === 'reset' && !$existingUser) {
        throw new HttpException(400, '该邮箱尚未注册，请先注册');
    }

    $stmt = $pdo->prepare(
        'SELECT created_at FROM email_codes WHERE email = ? ORDER BY id DESC LIMIT 1'
    );
    $stmt->execute([$email]);
    $last = $stmt->fetch();
    if ($last && now() - (int) $last['created_at'] < (int) $config['code_resend_seconds']) {
        throw new HttpException(429, '发送过于频繁，请稍后再试');
    }

    $code = (string) random_int(100000, 999999);
    $pdo->prepare(
        'INSERT INTO email_codes(email, code_hash, expires_at, used, created_at, ip)
         VALUES(?, ?, ?, 0, ?, ?)'
    )->execute([
        $email,
        hash('sha256', $code),
        now() + (int) $config['code_ttl'],
        now(),
        client_ip(),
    ]);
    $codeId = (int) $pdo->lastInsertId();
    try {
        SmtpMailer::send(
            $email,
            $purpose === 'reset'
                ? '凉次元重置密码验证码（10 分钟内有效）'
                : '凉次元注册验证码（10 分钟内有效）',
            verification_mail_html($code)
        );
    } catch (Throwable $e) {
        // 发信失败时撤销验证码，避免用户拿到一个无法使用的记录。
        $pdo->prepare('DELETE FROM email_codes WHERE id = ?')->execute([$codeId]);
        throw $e;
    }

    Response::ok(['message' => '验证码已发送，请查收邮件']);
}

function handle_reset_password(Request $request): void
{
    $body = $request->json();
    $email = normalize_email((string) ($body['email'] ?? ''));
    $code = trim((string) ($body['code'] ?? ''));
    $password = (string) ($body['password'] ?? '');

    if (!is_allowed_email($email)) {
        throw new HttpException(400, '只支持 QQ 邮箱（@qq.com / @foxmail.com）');
    }
    if (!preg_match('/^\d{6}$/', $code)) {
        throw new HttpException(400, '验证码格式不正确');
    }
    if (strlen($password) < 8) {
        throw new HttpException(400, '密码至少 8 位');
    }

    rate_limit('reset:ip:' . client_ip(), 10, 3600);

    $pdo = db();
    $pdo->beginTransaction();
    try {
        $stmt = $pdo->prepare('SELECT id FROM users WHERE email = ?');
        $stmt->execute([$email]);
        $user = $stmt->fetch();
        if (!$user) {
            throw new HttpException(400, '该邮箱尚未注册，请先注册');
        }

        $stmt = $pdo->prepare(
            'SELECT id, code_hash, expires_at FROM email_codes
             WHERE email = ? AND used = 0 ORDER BY id DESC LIMIT 1'
        );
        $stmt->execute([$email]);
        $row = $stmt->fetch();
        if (!$row) {
            throw new HttpException(400, '请先获取验证码');
        }
        if ((int) $row['expires_at'] < now()) {
            throw new HttpException(400, '验证码已过期，请重新获取');
        }
        if (!hash_equals((string) $row['code_hash'], hash('sha256', $code))) {
            throw new HttpException(400, '验证码不正确');
        }

        $pdo->prepare('UPDATE email_codes SET used = 1 WHERE id = ?')->execute([(int) $row['id']]);
        $pdo->prepare('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?')
            ->execute([
                password_hash($password, PASSWORD_DEFAULT),
                now(),
                (int) $user['id'],
            ]);
        // 改密后让所有旧令牌失效，避免被盗令牌继续可用。
        $pdo->prepare('DELETE FROM tokens WHERE user_id = ?')->execute([(int) $user['id']]);
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }

    Response::ok(['message' => '密码已重置，请用新密码登录']);
}

function handle_register(Request $request): void
{
    $body = $request->json();
    $email = normalize_email((string) ($body['email'] ?? ''));
    $code = trim((string) ($body['code'] ?? ''));
    $password = (string) ($body['password'] ?? '');
    $nickname = trim((string) ($body['nickname'] ?? ''));

    if (!is_allowed_email($email)) {
        throw new HttpException(400, '只支持 QQ 邮箱（@qq.com / @foxmail.com）');
    }
    if (!preg_match('/^\d{6}$/', $code)) {
        throw new HttpException(400, '验证码格式不正确');
    }
    if (strlen($password) < 8) {
        throw new HttpException(400, '密码至少 8 位');
    }
    if ($nickname === '') {
        $nickname = '凉次元用户';
    }
    if (mb_strlen($nickname) > 24) {
        throw new HttpException(400, '昵称最多 24 个字符');
    }

    rate_limit('register:ip:' . client_ip(), 10, 3600);

    $pdo = db();
    $pdo->beginTransaction();
    try {
        $stmt = $pdo->prepare('SELECT id FROM users WHERE email = ?');
        $stmt->execute([$email]);
        if ($stmt->fetch()) {
            throw new HttpException(409, '该邮箱已注册，请直接登录');
        }

        $stmt = $pdo->prepare(
            'SELECT id, code_hash, expires_at FROM email_codes
             WHERE email = ? AND used = 0 ORDER BY id DESC LIMIT 1'
        );
        $stmt->execute([$email]);
        $row = $stmt->fetch();
        if (!$row) {
            throw new HttpException(400, '请先获取验证码');
        }
        if ((int) $row['expires_at'] < now()) {
            throw new HttpException(400, '验证码已过期，请重新获取');
        }
        if (!hash_equals((string) $row['code_hash'], hash('sha256', $code))) {
            throw new HttpException(400, '验证码不正确');
        }

        $pdo->prepare('UPDATE email_codes SET used = 1 WHERE id = ?')->execute([(int) $row['id']]);
        $now = now();
        $pdo->prepare(
            'INSERT INTO users(email, password_hash, nickname, avatar, email_verified, created_at, updated_at)
             VALUES(?, ?, ?, ?, 1, ?, ?)'
        )->execute([
            $email,
            password_hash($password, PASSWORD_DEFAULT),
            $nickname,
            '',
            $now,
            $now,
        ]);
        $userId = (int) $pdo->lastInsertId();
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        if ($e instanceof PDOException
            && (string) ($e->errorInfo[0] ?? '') === '23000') {
            throw new HttpException(409, '该邮箱已注册，请直接登录');
        }
        throw $e;
    }

    $token = create_token($userId);
    $stmt = $pdo->prepare('SELECT * FROM users WHERE id = ?');
    $stmt->execute([$userId]);
    $user = $stmt->fetch();
    Response::ok([
        'token' => $token,
        'user' => public_profile($user),
        'avatarUrl' => avatar_url($user),
    ]);
}

function handle_login(Request $request): void
{
    $body = $request->json();
    $email = normalize_email((string) ($body['email'] ?? ''));
    $password = (string) ($body['password'] ?? '');
    if (!is_allowed_email($email) || $password === '') {
        throw new HttpException(400, '请输入邮箱和密码');
    }

    rate_limit('login:ip:' . client_ip(), 30, 600);
    rate_limit('login:email:' . $email, 10, 600);

    $stmt = db()->prepare('SELECT * FROM users WHERE email = ?');
    $stmt->execute([$email]);
    $user = $stmt->fetch();
    if (!$user || !password_verify($password, (string) $user['password_hash'])) {
        throw new HttpException(401, '邮箱或密码不正确');
    }

    $token = create_token((int) $user['id']);
    Response::ok([
        'token' => $token,
        'user' => public_profile($user),
        'avatarUrl' => avatar_url($user),
    ]);
}

function handle_logout(Request $request): void
{
    revoke_current_token($request);
    Response::ok();
}

function handle_me(Request $request): void
{
    $user = current_user($request);
    Response::ok(['user' => public_profile($user), 'avatarUrl' => avatar_url($user)]);
}

function handle_update_me(Request $request): void
{
    $user = current_user($request);
    $body = $request->json();
    $nickname = trim((string) ($body['nickname'] ?? ''));
    if ($nickname === '') {
        throw new HttpException(400, '昵称不能为空');
    }
    if (mb_strlen($nickname) > 24) {
        throw new HttpException(400, '昵称最多 24 个字符');
    }

    db()->prepare('UPDATE users SET nickname = ?, updated_at = ? WHERE id = ?')
        ->execute([$nickname, now(), (int) $user['id']]);
    $user['nickname'] = $nickname;
    Response::ok(['user' => public_profile($user), 'avatarUrl' => avatar_url($user)]);
}

function handle_upload_avatar(Request $request): void
{
    $user = current_user($request);
    $config = app_config();
    if (!isset($_FILES['avatar']) || !is_array($_FILES['avatar'])) {
        throw new HttpException(400, '缺少 avatar 文件');
    }
    $file = $_FILES['avatar'];
    if ((int) ($file['error'] ?? 1) !== UPLOAD_ERR_OK) {
        throw new HttpException(400, '上传失败，请重试');
    }
    if ((int) $file['size'] > (int) $config['max_avatar_bytes']) {
        throw new HttpException(413, '头像不能超过 2 MB');
    }

    $info = @getimagesize((string) $file['tmp_name']);
    $allowed = [
        IMAGETYPE_JPEG => 'jpg',
        IMAGETYPE_PNG => 'png',
        IMAGETYPE_WEBP => 'webp',
    ];
    $type = is_array($info) ? (int) $info[2] : 0;
    if (!isset($allowed[$type])) {
        throw new HttpException(415, '头像仅支持 JPG / PNG / WebP');
    }

    $dir = (string) $config['avatar_dir'];
    if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
        throw new HttpException(500, '无法创建头像目录');
    }

    $userId = (int) $user['id'];
    $name = $userId . '.' . $allowed[$type];
    $staged = $dir . '/.' . $userId . '.upload';
    if (!move_uploaded_file((string) $file['tmp_name'], $staged)) {
        throw new HttpException(500, '保存头像失败');
    }
    // 先落地新文件，再删除旧文件，避免移动失败时旧头像也丢失。
    foreach (['jpg', 'png', 'webp'] as $ext) {
        $old = $dir . '/' . $userId . '.' . $ext;
        if ($old !== $dir . '/' . $name && is_file($old)) {
            @unlink($old);
        }
    }
    if (!rename($staged, $dir . '/' . $name)) {
        @unlink($staged);
        throw new HttpException(500, '保存头像失败');
    }

    db()->prepare('UPDATE users SET avatar = ?, updated_at = ? WHERE id = ?')
        ->execute([$name, now(), $userId]);
    $user['avatar'] = $name;
    Response::ok(['user' => public_profile($user), 'avatarUrl' => avatar_url($user)]);
}

function handle_get_avatar(Request $request): void
{
    $id = (int) ($request->params['id'] ?? 0);
    if ($id <= 0) {
        throw new HttpException(404, '头像不存在');
    }
    $dir = (string) app_config()['avatar_dir'];
    foreach (['jpg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp'] as $ext => $mime) {
        $path = $dir . '/' . $id . '.' . $ext;
        if (is_file($path)) {
            header('Content-Type: ' . $mime);
            header('X-Content-Type-Options: nosniff');
            header('Content-Length: ' . (string) filesize($path));
            header('Cache-Control: public, max-age=86400');
            readfile($path);
            exit;
        }
    }
    throw new HttpException(404, '头像不存在');
}

function sync_kind(Request $request): string
{
    $kind = (string) ($request->params['kind'] ?? '');
    if (!preg_match('/^[a-zA-Z0-9_\-]{1,200}$/', $kind)) {
        throw new HttpException(400, '同步类型不合法');
    }
    return $kind;
}

function handle_sync_list(Request $request): void
{
    $user = current_user($request);
    $stmt = db()->prepare('SELECT kind, updated_at, length(payload) AS size FROM sync_blobs WHERE user_id = ?');
    $stmt->execute([(int) $user['id']]);
    Response::ok(['items' => $stmt->fetchAll()]);
}

function handle_sync_get(Request $request): void
{
    $user = current_user($request);
    $kind = sync_kind($request);
    $stmt = db()->prepare('SELECT payload, updated_at, checksum FROM sync_blobs WHERE user_id = ? AND kind = ?');
    $stmt->execute([(int) $user['id'], $kind]);
    $row = $stmt->fetch();
    if (!$row) {
        throw new HttpException(404, '尚未同步过该内容');
    }
    Response::ok([
        'payload' => (string) $row['payload'],
        'updatedAt' => (int) $row['updated_at'],
        'checksum' => (string) $row['checksum'],
    ]);
}

function handle_sync_put(Request $request): void
{
    $user = current_user($request);
    $kind = sync_kind($request);
    $config = app_config();
    $body = $request->json();
    $payload = (string) ($body['payload'] ?? '');
    $updatedAt = (int) ($body['updatedAt'] ?? 0);
    // 允许显式写入空内容（例如空的收藏盒子），只拒绝缺少字段的请求。
    if (!array_key_exists('payload', $body) || $updatedAt <= 0) {
        throw new HttpException(400, '缺少 payload 或 updatedAt');
    }
    $decoded = base64_decode($payload, true);
    if ($decoded === false) {
        throw new HttpException(400, 'payload 不是合法 base64');
    }
    if (strlen($decoded) > (int) $config['max_payload_bytes']) {
        throw new HttpException(413, '同步数据过大');
    }

    $pdo = db();
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) AS c, COALESCE(SUM(length(payload)), 0) AS s
         FROM sync_blobs WHERE user_id = ? AND kind <> ?'
    );
    $stmt->execute([(int) $user['id'], $kind]);
    $existing = $stmt->fetch() ?: ['c' => 0, 's' => 0];
    if ((int) $existing['c'] >= (int) $config['max_sync_kinds']) {
        throw new HttpException(413, '同步内容类型过多');
    }
    if ((int) $existing['s'] + strlen($payload) > (int) $config['max_sync_total_bytes']) {
        throw new HttpException(413, '同步数据总量超出限制');
    }
    // 客户端在上传前已经拉取并合并过云端数据，这里以服务端接收时间落库，
    // 避免设备时钟偏差导致 PUT 永远 409。
    $storedAt = (int) round(microtime(true) * 1000);
    $checksum = hash('sha256', $payload);
    $pdo->prepare(
        'INSERT INTO sync_blobs(user_id, kind, payload, checksum, updated_at)
         VALUES(?, ?, ?, ?, ?)
         ON CONFLICT(user_id, kind) DO UPDATE SET
           payload = excluded.payload,
           checksum = excluded.checksum,
           updated_at = excluded.updated_at'
    )->execute([(int) $user['id'], $kind, $payload, $checksum, $storedAt]);

    Response::ok(['updatedAt' => $storedAt, 'checksum' => $checksum]);
}

function handle_sync_delete(Request $request): void
{
    $user = current_user($request);
    $kind = sync_kind($request);
    db()->prepare('DELETE FROM sync_blobs WHERE user_id = ? AND kind = ?')
        ->execute([(int) $user['id'], $kind]);
    Response::ok();
}