<?php
declare(strict_types=1);

/**
 * 管理动作：封禁、解封、删除/恢复发言。
 *
 * 全部要求 POST + CSRF。操作后回跳列表页并显示结果。
 */

function admin_find_user(int $id): ?array
{
    $stmt = admin_db()->prepare('SELECT * FROM users WHERE id = ?');
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    return $row ?: null;
}

function do_ban(): void
{
    $id = (int) ($_POST['user_id'] ?? 0);
    $days = (int) ($_POST['days'] ?? 7);
    $reason = trim((string) ($_POST['reason'] ?? ''));
    $user = admin_find_user($id);
    if (!$user) {
        admin_flash('用户不存在。', 'error');
        admin_redirect('/user/');
    }
    // days = 0 表示永久封禁（给一个很远的未来时间）
    $until = $days <= 0
        ? admin_now() + 86400 * 3650
        : admin_now() + 86400 * min($days, 3650);
    if (mb_strlen($reason, 'UTF-8') > 200) {
        $reason = mb_substr($reason, 0, 200, 'UTF-8');
    }

    $pdo = admin_db();
    $pdo->prepare('UPDATE users SET banned_until = ?, ban_reason = ?, updated_at = ? WHERE id = ?')
        ->execute([$until, $reason, admin_now(), $id]);
    // 立刻踢掉该用户所有会话：封禁应当马上生效，而不是等 token 过期。
    $pdo->prepare('DELETE FROM tokens WHERE user_id = ?')->execute([$id]);

    $label = $days <= 0 ? '永久' : $days . ' 天';
    admin_flash('已封禁 ' . admin_email_of($user) . '（' . $label . '）。');
    admin_redirect('/user/?a=user&id=' . $id);
}

function do_unban(): void
{
    $id = (int) ($_POST['user_id'] ?? 0);
    $user = admin_find_user($id);
    if (!$user) {
        admin_flash('用户不存在。', 'error');
        admin_redirect('/user/');
    }
    admin_db()
        ->prepare('UPDATE users SET banned_until = 0, ban_reason = "", updated_at = ? WHERE id = ?')
        ->execute([admin_now(), $id]);
    admin_flash('已解封 ' . admin_email_of($user) . '。');
    admin_redirect('/user/?a=user&id=' . $id);
}

function admin_email_of(array $user): string
{
    $email = (string) ($user['email'] ?? '');
    $nick = trim((string) ($user['nickname'] ?? ''));
    return $nick !== '' ? "{$nick}（{$email}）" : $email;
}

function do_delete_comment(): void
{
    $id = (int) ($_POST['comment_id'] ?? 0);
    $back = (string) ($_POST['back'] ?? '/user/?a=comments');
    $pdo = admin_db();
    $stmt = $pdo->prepare('SELECT id FROM comments WHERE id = ?');
    $stmt->execute([$id]);
    if (!$stmt->fetch()) {
        admin_flash('评论不存在。', 'error');
        admin_redirect($back);
    }
    $pdo->prepare('UPDATE comments SET deleted = 1, updated_at = ? WHERE id = ?')
        ->execute([admin_now(), $id]);
    admin_flash('已删除该评论。');
    admin_redirect($back);
}

function do_restore_comment(): void
{
    $id = (int) ($_POST['comment_id'] ?? 0);
    $back = (string) ($_POST['back'] ?? '/user/?a=comments');
    admin_db()
        ->prepare('UPDATE comments SET deleted = 0, updated_at = ? WHERE id = ?')
        ->execute([admin_now(), $id]);
    admin_flash('已恢复该评论。');
    admin_redirect($back);
}

function do_delete_danmaku(): void
{
    $id = (int) ($_POST['danmaku_id'] ?? 0);
    $back = (string) ($_POST['back'] ?? '/user/?a=danmaku');
    $pdo = admin_db();
    $stmt = $pdo->prepare('SELECT id FROM danmaku WHERE id = ?');
    $stmt->execute([$id]);
    if (!$stmt->fetch()) {
        admin_flash('弹幕不存在。', 'error');
        admin_redirect($back);
    }
    $pdo->prepare('UPDATE danmaku SET deleted = 1 WHERE id = ?')->execute([$id]);
    admin_flash('已删除该弹幕。');
    admin_redirect($back);
}
