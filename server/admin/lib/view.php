<?php
declare(strict_types=1);

require_once __DIR__ . '/sync_data.php';
require_once __DIR__ . '/ui.php';

/// 后台导航。key 与 index.php 里的 action 对应。
const ADMIN_NAV = [
    '' => ['label' => '概览', 'icon' => 'dashboard'],
    'users' => ['label' => '用户', 'icon' => 'users'],
    'comments' => ['label' => '评论', 'icon' => 'comments'],
    'danmaku' => ['label' => '弹幕', 'icon' => 'danmaku'],
    'audit' => ['label' => '操作日志', 'icon' => 'log'],
];

function render_login(?string $error = null): void
{
    $flash = admin_take_flash();
    ?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>登录 · 凉次元管理后台</title>
<style><?= admin_css() ?></style>
</head>
<body class="login-body">
  <form class="login-card" method="post" action="/user/?a=login">
    <div class="login-brand">
      <span class="logo-dot"></span>
      <div>
        <h1>凉次元</h1>
        <p>管理后台</p>
      </div>
    </div>
    <?php if ($error !== null): ?>
      <div class="alert error"><?= admin_esc($error) ?></div>
    <?php endif; ?>
    <?php if ($flash !== null): ?>
      <div class="alert <?= admin_esc($flash['kind']) ?>"><?= admin_esc($flash['message']) ?></div>
    <?php endif; ?>
    <input type="hidden" name="csrf" value="<?= admin_esc(csrf_token()) ?>">
    <label class="field">
      <span>访问密码</span>
      <input type="password" name="password" autocomplete="current-password" required autofocus>
    </label>
    <button class="btn primary block" type="submit">进入后台</button>
    <p class="login-foot">仅限管理员访问 · 连续输错会临时锁定</p>
  </form>
</body>
</html>
    <?php
}

/// 统一外壳：侧边导航 + 内容区。
function render_page(string $title, string $body, string $active = '', bool $wide = false): void
{
    $flash = admin_take_flash();
    $pending = admin_pending_badge_counts();
    ?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title><?= admin_esc($title) ?> · 凉次元管理后台</title>
<style><?= admin_css() ?></style>
</head>
<body>
<input type="checkbox" id="nav-toggle" class="nav-toggle" hidden>
<div class="shell">
  <aside class="sidebar">
    <div class="brand">
      <span class="logo-dot"></span>
      <div class="brand-text">
        <strong>凉次元</strong>
        <small>管理后台</small>
      </div>
    </div>
    <nav class="nav">
      <?php foreach (ADMIN_NAV as $key => $item): ?>
        <?php
          $href = $key === '' ? '/user/' : '/user/?a=' . $key;
          $count = $pending[$key] ?? 0;
        ?>
        <a class="nav-item<?= $active === $key ? ' active' : '' ?>" href="<?= admin_esc($href) ?>">
          <?= ui_icon($item['icon']) ?>
          <span><?= admin_esc($item['label']) ?></span>
          <?php if ($count > 0): ?><em class="nav-count"><?= $count ?></em><?php endif; ?>
        </a>
      <?php endforeach; ?>
    </nav>
    <div class="sidebar-foot">
      <a class="nav-item quiet" href="/" target="_blank" rel="noopener">
        <?= ui_icon('external') ?><span>查看站点</span>
      </a>
      <a class="nav-item quiet" href="/user/?a=logout">
        <?= ui_icon('logout') ?><span>退出登录</span>
      </a>
    </div>
  </aside>
  <div class="scrim" onclick="document.getElementById('nav-toggle').checked=false"></div>
  <div class="main">
    <header class="mobile-bar">
      <label for="nav-toggle" class="icon-btn" aria-label="打开导航"><?= ui_icon('menu', 22) ?></label>
      <span><?= admin_esc($title) ?></span>
    </header>
    <main class="content<?= $wide ? ' wide' : '' ?>">
      <?php if ($flash !== null): ?>
        <div class="alert <?= admin_esc($flash['kind']) ?>"><?= admin_esc($flash['message']) ?></div>
      <?php endif; ?>
      <?= $body ?>
    </main>
  </div>
</div>
</body>
</html>
    <?php
}

/// 侧栏的小红点数字：封禁中用户数、待处理评论（这里只显示总数，不做未读概念）。
function admin_pending_badge_counts(): array
{
    try {
        $pdo = admin_db();
        $banned = (int) $pdo->query(
            'SELECT COUNT(*) FROM users WHERE banned_until > ' . admin_now()
        )->fetchColumn();
        return ['users' => $banned];
    } catch (Throwable $ignored) {
        return [];
    }
}

// ---------------------------------------------------------------------------
// 概览
// ---------------------------------------------------------------------------

function render_dashboard(): void
{
    $pdo = admin_db();
    $now = admin_now();
    $scalar = static function (string $sql) use ($pdo): int {
        return (int) $pdo->query($sql)->fetchColumn();
    };

    $users = $scalar('SELECT COUNT(*) FROM users');
    $verified = $scalar('SELECT COUNT(*) FROM users WHERE email_verified = 1');
    $banned = $scalar('SELECT COUNT(*) FROM users WHERE banned_until > ' . $now);
    $newUsers7 = $scalar('SELECT COUNT(*) FROM users WHERE created_at > ' . ($now - 86400 * 7));

    $comments = $scalar('SELECT COUNT(*) FROM comments WHERE deleted = 0');
    $comments7 = $scalar('SELECT COUNT(*) FROM comments WHERE deleted = 0 AND created_at > ' . ($now - 86400 * 7));
    $danmaku = $scalar('SELECT COUNT(*) FROM danmaku WHERE deleted = 0');
    $danmaku7 = $scalar('SELECT COUNT(*) FROM danmaku WHERE deleted = 0 AND created_at > ' . ($now - 86400 * 7));

    $syncUsers = $scalar('SELECT COUNT(DISTINCT user_id) FROM sync_blobs');
    $syncBytes = $scalar('SELECT COALESCE(SUM(length(payload)), 0) FROM sync_blobs');
    $activeTokens = $scalar('SELECT COUNT(*) FROM tokens WHERE expires_at > ' . $now);

    // 近 7 天注册曲线。
    $series = [];
    for ($i = 6; $i >= 0; $i--) {
        $start = strtotime('today') - $i * 86400;
        $end = $start + 86400;
        $count = $scalar(
            'SELECT COUNT(*) FROM users WHERE created_at >= ' . $start . ' AND created_at < ' . $end
        );
        $series[date('m-d', $start)] = $count;
    }

    $recentUsers = $pdo->query(
        'SELECT id, nickname, email, title, created_at, banned_until
         FROM users ORDER BY id DESC LIMIT 6'
    )->fetchAll();
    $recentComments = $pdo->query(
        'SELECT c.id, c.content, c.target_type, c.target_id, c.created_at, u.nickname
         FROM comments c JOIN users u ON u.id = c.user_id
         WHERE c.deleted = 0 ORDER BY c.id DESC LIMIT 6'
    )->fetchAll();

    ob_start();
    ?>
    <?= ui_page_head(
        '概览',
        '凉次元账号与社区数据一览',
        '<a class="btn" href="/user/?a=comments">处理评论' . ui_icon('arrow-right', 16) . '</a>'
    ) ?>

    <div class="stats">
      <?= ui_stat('注册用户', (string) $users, '近 7 天新增 ' . $newUsers7, 'users', '', '/user/?a=users') ?>
      <?= ui_stat('已认证', (string) $verified, '邮箱已验证', 'check') ?>
      <?= ui_stat('封禁中', (string) $banned, $banned > 0 ? '需要关注' : '状态良好', 'shield', $banned > 0 ? 'warn' : '') ?>
      <?= ui_stat('活跃会话', (string) $activeTokens, '未过期的登录凭证', 'clock') ?>
    </div>

    <div class="grid-2">
      <section class="card">
        <div class="card-head">
          <h2>近 7 天注册</h2>
          <span class="muted small">合计 <?= array_sum($series) ?> 人</span>
        </div>
        <?= ui_bars($series) ?>
      </section>
      <section class="card">
        <div class="card-head"><h2>互动</h2></div>
        <div class="kv-rows">
          <div class="kv-row">
            <span class="kv-label">评论总数</span>
            <span class="kv-value"><?= $comments ?></span>
            <span class="muted small">近 7 天 <?= $comments7 ?></span>
          </div>
          <div class="kv-row">
            <span class="kv-label">弹幕总数</span>
            <span class="kv-value"><?= $danmaku ?></span>
            <span class="muted small">近 7 天 <?= $danmaku7 ?></span>
          </div>
          <div class="kv-row">
            <span class="kv-label">同步用户</span>
            <span class="kv-value"><?= $syncUsers ?></span>
            <span class="muted small">共 <?= number_format($syncBytes / 1024 / 1024, 1) ?> MB</span>
          </div>
        </div>
      </section>
    </div>

    <div class="grid-2">
      <section class="card">
        <div class="card-head">
          <h2>最新注册</h2>
          <a class="link small" href="/user/?a=users">全部用户</a>
        </div>
        <?php if (!$recentUsers): ?>
          <?= ui_empty('还没有用户', '有人注册后会出现在这里') ?>
        <?php else: ?>
          <ul class="mini-list">
          <?php foreach ($recentUsers as $u): ?>
            <?php $isBanned = (int) $u['banned_until'] > $now; ?>
            <li>
              <a class="mini-main" href="/user/?a=user&id=<?= (int) $u['id'] ?>">
                <span class="avatar-sm"><?= admin_esc(mb_substr(trim((string) $u['nickname']) !== '' ? (string) $u['nickname'] : (string) $u['email'], 0, 1, 'UTF-8')) ?></span>
                <span class="mini-text">
                  <strong><?= admin_esc(trim((string) $u['nickname']) !== '' ? (string) $u['nickname'] : '未设置昵称') ?></strong>
                  <small><?= admin_esc((string) $u['email']) ?></small>
                </span>
              </a>
              <span class="mini-side">
                <?php if ($isBanned): ?><?= ui_badge('封禁', 'danger') ?><?php endif; ?>
                <small class="muted"><?= admin_esc(ui_ago((int) $u['created_at'])) ?></small>
              </span>
            </li>
          <?php endforeach; ?>
          </ul>
        <?php endif; ?>
      </section>

      <section class="card">
        <div class="card-head">
          <h2>最新评论</h2>
          <a class="link small" href="/user/?a=comments">全部评论</a>
        </div>
        <?php if (!$recentComments): ?>
          <?= ui_empty('还没有评论', '用户发表评论后会出现在这里', 'comments') ?>
        <?php else: ?>
          <ul class="mini-list">
          <?php foreach ($recentComments as $c): ?>
            <li>
              <a class="mini-main" href="/user/?a=comments&q=<?= urlencode((string) $c['target_type'] . '#' . (int) $c['target_id']) ?>">
                <span class="mini-text">
                  <strong><?= admin_esc((string) $c['nickname']) ?></strong>
                  <small class="clamp-1"><?= admin_esc((string) $c['content']) ?></small>
                </span>
              </a>
              <span class="mini-side">
                <small class="muted"><?= admin_esc(ui_ago((int) $c['created_at'])) ?></small>
              </span>
            </li>
          <?php endforeach; ?>
          </ul>
        <?php endif; ?>
      </section>
    </div>
    <?php
    render_page('概览', (string) ob_get_clean(), '');
}

// ---------------------------------------------------------------------------
// 用户
// ---------------------------------------------------------------------------

function render_users(): void
{
    $q = admin_q('q');
    $filter = admin_q('f', 'all', 16);
    $sort = admin_q('sort', 'new', 16);
    $pageNo = max(1, admin_int('p', 1));
    $perPage = 25;

    $where = [];
    $args = [];
    if ($q !== '') {
        $where[] = '(email LIKE ? OR nickname LIKE ?)';
        $like = '%' . $q . '%';
        $args[] = $like;
        $args[] = $like;
    }
    switch ($filter) {
        case 'banned':
            $where[] = 'banned_until > ?';
            $args[] = admin_now();
            break;
        case 'title':
            $where[] = "title <> ''";
            break;
        case 'unverified':
            $where[] = 'email_verified = 0';
            break;
        case 'sync':
            $where[] = 'id IN (SELECT user_id FROM sync_blobs)';
            break;
    }
    $whereSql = $where ? 'WHERE ' . implode(' AND ', $where) : '';
    $orderSql = match ($sort) {
        'old' => 'ORDER BY id ASC',
        'active' => 'ORDER BY updated_at DESC, id DESC',
        'name' => 'ORDER BY nickname ASC, id DESC',
        default => 'ORDER BY id DESC',
    };

    $pdo = admin_db();
    $countStmt = $pdo->prepare('SELECT COUNT(*) FROM users ' . $whereSql);
    $countStmt->execute($args);
    $page = admin_paginate((int) $countStmt->fetchColumn(), $perPage, $pageNo);

    $stmt = $pdo->prepare(
        'SELECT * FROM users ' . $whereSql . ' ' . $orderSql
        . ' LIMIT ' . $page['perPage'] . ' OFFSET ' . $page['offset']
    );
    $stmt->execute($args);
    $users = $stmt->fetchAll();

    // 每个列表项的统计（限定到当前页的 id，避免全表聚合）。
    $ids = array_map(static fn(array $u): int => (int) $u['id'], $users);
    $stats = admin_user_stats($ids);

    ob_start();
    ?>
    <?= ui_page_head('用户', '共 ' . $page['total'] . ' 个账号，可按状态筛选、进入详情管理') ?>

    <form class="filters" method="get" action="/user/">
      <input type="hidden" name="a" value="users">
      <div class="filter-search">
        <span class="filter-icon"><?= ui_icon('search', 18) ?></span>
        <input type="search" name="q" value="<?= admin_esc($q) ?>" placeholder="搜索邮箱或昵称" autocomplete="off">
      </div>
      <select name="f" onchange="this.form.submit()">
        <?php foreach ([
            'all' => '全部状态',
            'banned' => '封禁中',
            'title' => '有称号',
            'sync' => '同步过数据',
            'unverified' => '未验证邮箱',
        ] as $value => $label): ?>
          <option value="<?= $value ?>"<?= $filter === $value ? ' selected' : '' ?>><?= $label ?></option>
        <?php endforeach; ?>
      </select>
      <select name="sort" onchange="this.form.submit()">
        <?php foreach ([
            'new' => '最新注册',
            'old' => '最早注册',
            'active' => '最近活跃',
            'name' => '昵称排序',
        ] as $value => $label): ?>
          <option value="<?= $value ?>"<?= $sort === $value ? ' selected' : '' ?>><?= $label ?></option>
        <?php endforeach; ?>
      </select>
      <button class="btn primary" type="submit">筛选</button>
      <?php if ($q !== '' || $filter !== 'all' || $sort !== 'new'): ?>
        <a class="btn ghost" href="/user/?a=users">重置</a>
      <?php endif; ?>
    </form>

    <section class="card flush">
      <?php if (!$users): ?>
        <?= ui_empty(
            $q !== '' || $filter !== 'all' ? '没有匹配的用户' : '还没有用户',
            $q !== '' || $filter !== 'all' ? '换个关键词或清空筛选试试' : '客户端注册后会出现在这里',
            'users'
        ) ?>
      <?php else: ?>
        <div class="table-scroll">
          <table class="table users-table">
            <thead>
              <tr>
                <th>用户</th>
                <th class="col-num">评论</th>
                <th class="col-num">弹幕</th>
                <th class="col-num">同步</th>
                <th>状态</th>
                <th class="col-time">注册</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
            <?php foreach ($users as $u): ?>
              <?php
                $id = (int) $u['id'];
                $s = $stats[$id] ?? [];
                $isBanned = (int) ($u['banned_until'] ?? 0) > admin_now();
                $name = trim((string) $u['nickname']);
              ?>
              <tr>
                <td>
                  <a class="user-cell" href="/user/?a=user&id=<?= $id ?>">
                    <span class="avatar-sm"><?= admin_esc($name !== '' ? mb_substr($name, 0, 1, 'UTF-8') : mb_substr((string) $u['email'], 0, 1, 'UTF-8')) ?></span>
                    <span class="user-cell-text">
                      <span class="user-name">
                        <span class="user-name-text"><?= admin_esc($name !== '' ? $name : '未设置昵称') ?></span>
                        <?php if (trim((string) ($u['title'] ?? '')) !== ''): ?>
                          <span class="title-chip"><?= admin_esc((string) $u['title']) ?></span>
                        <?php endif; ?>
                      </span>
                      <small class="muted"><?= admin_esc((string) $u['email']) ?></small>
                    </span>
                  </a>
                </td>
                <td class="col-num"><?= (int) ($s['comments'] ?? 0) ?></td>
                <td class="col-num"><?= (int) ($s['danmaku'] ?? 0) ?></td>
                <td class="col-num col-sync">
                  <?= ($s['syncCount'] ?? 0) > 0
                      ? (int) $s['syncCount'] . ' 项'
                      : '<span class="muted">—</span>' ?>
                </td>
                <td class="col-status">
                  <?php if ($isBanned): ?>
                    <span class="badge danger" title="封禁至 <?= admin_esc(ui_time((int) $u['banned_until'])) ?>">封禁</span>
                  <?php elseif ((int) $u['email_verified'] === 1): ?>
                    <?= ui_badge('正常', 'ok') ?>
                  <?php else: ?>
                    <?= ui_badge('未验证', 'muted') ?>
                  <?php endif; ?>
                </td>
                <td class="col-time"><?= admin_esc(ui_ago((int) $u['created_at'])) ?></td>
                <td class="col-action">
                  <a class="btn small" href="/user/?a=user&id=<?= $id ?>">详情</a>
                </td>
              </tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </section>

    <?php if ($users): ?>
      <div class="table-foot">
        <span class="muted small"><?= admin_esc(ui_pager_summary($page, '个用户')) ?></span>
        <?= ui_pager($page, ui_link(['a' => 'users', 'q' => $q, 'f' => $filter === 'all' ? '' : $filter, 'sort' => $sort === 'new' ? '' : $sort])) ?>
      </div>
    <?php endif; ?>
    <?php
    render_page('用户', (string) ob_get_clean(), 'users');
}

/// 批量统计：评论数、弹幕数、同步块数与最近同步时间。
function admin_user_stats(array $ids): array
{
    if (!$ids) {
        return [];
    }
    $pdo = admin_db();
    $in = implode(',', array_map('intval', $ids));
    $stats = [];
    foreach ($pdo->query(
        "SELECT user_id, COUNT(*) AS c FROM comments WHERE deleted = 0 AND user_id IN ($in) GROUP BY user_id"
    ) as $row) {
        $stats[(int) $row['user_id']]['comments'] = (int) $row['c'];
    }
    foreach ($pdo->query(
        "SELECT user_id, COUNT(*) AS c FROM danmaku WHERE deleted = 0 AND user_id IN ($in) GROUP BY user_id"
    ) as $row) {
        $stats[(int) $row['user_id']]['danmaku'] = (int) $row['c'];
    }
    foreach ($pdo->query(
        "SELECT user_id, COUNT(*) AS c, MAX(updated_at) AS last
         FROM sync_blobs WHERE user_id IN ($in) GROUP BY user_id"
    ) as $row) {
        $stats[(int) $row['user_id']]['syncCount'] = (int) $row['c'];
        $stats[(int) $row['user_id']]['syncLast'] = (int) floor(((int) $row['last']) / 1000);
    }
    return $stats;
}

function render_user_detail(int $id): void
{
    $user = admin_find_user($id);
    if (!$user) {
        render_page('用户', ui_page_head('用户不存在', '该账号可能已被删除')
            . ui_empty('找不到这个用户', '返回列表重新选择', 'users')
            . '<p><a class="btn" href="/user/?a=users">' . ui_icon('arrow-left', 16) . ' 返回用户列表</a></p>', 'users');
        return;
    }
    $pdo = admin_db();
    $now = admin_now();
    $banned = (int) ($user['banned_until'] ?? 0) > $now;
    $name = trim((string) $user['nickname']);

    $commentStmt = $pdo->prepare(
        'SELECT id, target_type, target_id, content, created_at, deleted
         FROM comments WHERE user_id = ? ORDER BY id DESC LIMIT 50'
    );
    $commentStmt->execute([$id]);
    $comments = $commentStmt->fetchAll();

    $danmakuStmt = $pdo->prepare(
        'SELECT id, bangumi_id, episode, content, created_at, deleted
         FROM danmaku WHERE user_id = ? ORDER BY id DESC LIMIT 50'
    );
    $danmakuStmt->execute([$id]);
    $danmaku = $danmakuStmt->fetchAll();

    $collect = collectible_summary($id);
    $snapshotKind = find_history_snapshot_kind($id);
    $history = $snapshotKind !== null
        ? parse_history_rows(sync_payload_json($id, $snapshotKind) ?? [])
        : [];
    $blocks = sync_blocks($id);
    $ratingCount = (int) $pdo->query(
        'SELECT COUNT(*) FROM ratings WHERE user_id = ' . $id
    )->fetchColumn();
    $tokenCount = (int) $pdo->query(
        'SELECT COUNT(*) FROM tokens WHERE user_id = ' . $id . ' AND expires_at > ' . $now
    )->fetchColumn();

    ob_start();
    ?>
    <p class="back-link"><a href="/user/?a=users"><?= ui_icon('arrow-left', 16) ?> 用户列表</a></p>

    <section class="profile">
      <div class="profile-avatar"><?= admin_esc($name !== '' ? mb_substr($name, 0, 1, 'UTF-8') : mb_substr((string) $user['email'], 0, 1, 'UTF-8')) ?></div>
      <div class="profile-main">
        <h1>
          <?= admin_esc($name !== '' ? $name : '未设置昵称') ?>
          <?php if (trim((string) ($user['title'] ?? '')) !== ''): ?>
            <span class="title-chip"><?= admin_esc((string) $user['title']) ?></span>
          <?php endif; ?>
          <?php if ($banned): ?>
            <?= ui_badge('封禁中', 'danger') ?>
          <?php elseif ((int) $user['email_verified'] === 1): ?>
            <?= ui_badge('已认证', 'ok') ?>
          <?php else: ?>
            <?= ui_badge('未验证', 'muted') ?>
          <?php endif; ?>
        </h1>
        <p class="profile-meta">
          <span><?= admin_esc((string) $user['email']) ?></span>
          <span class="dot">·</span>
          <span class="mono">#<?= (int) $user['id'] ?></span>
          <span class="dot">·</span>
          <span>注册于 <?= admin_esc(ui_time((int) $user['created_at'])) ?></span>
        </p>
        <p class="profile-meta">
          <span>评论 <?= count($comments) >= 50 ? '50+' : count($comments) ?></span>
          <span class="dot">·</span>
          <span>弹幕 <?= count($danmaku) >= 50 ? '50+' : count($danmaku) ?></span>
          <span class="dot">·</span>
          <span>评分 <?= $ratingCount ?></span>
          <span class="dot">·</span>
          <span>活跃设备 <?= $tokenCount ?></span>
          <?php if ($banned): ?>
            <span class="dot">·</span>
            <span class="danger-text">封禁至 <?= admin_esc(ui_time((int) $user['banned_until'])) ?></span>
          <?php endif; ?>
        </p>
        <?php if ($banned && trim((string) $user['ban_reason']) !== ''): ?>
          <div class="ban-reason">封禁原因：<?= admin_esc((string) $user['ban_reason']) ?></div>
        <?php endif; ?>
      </div>
    </section>

    <div class="grid-2">
      <section class="card">
        <div class="card-head"><h2>称号</h2></div>
        <p class="muted small">称号只由管理端授予，客户端只能展示。留空即取消。</p>
        <form class="inline-form" method="post" action="/user/?a=set-title">
          <?= csrf_field() ?>
          <input type="hidden" name="user_id" value="<?= (int) $user['id'] ?>">
          <input type="text" name="title" value="<?= admin_esc((string) ($user['title'] ?? '')) ?>"
                 placeholder="例如：凉次元作者" maxlength="24">
          <button class="btn primary" type="submit">保存称号</button>
        </form>
      </section>

      <section class="card">
        <div class="card-head"><h2>账号状态</h2></div>
        <?php if ($banned): ?>
          <p class="muted small">封禁期间该用户无法登录与发言，已登录的设备会被强制下线。</p>
          <form method="post" action="/user/?a=unban"
                onsubmit="return confirm('确定解除该用户的封禁？');">
            <?= csrf_field() ?>
            <input type="hidden" name="user_id" value="<?= (int) $user['id'] ?>">
            <button class="btn primary" type="submit"><?= ui_icon('check', 16) ?> 解除封禁</button>
          </form>
        <?php else: ?>
          <form class="ban-form" method="post" action="/user/?a=ban"
                onsubmit="return confirm('确定封禁该用户？封禁会立即踢下线。');">
            <?= csrf_field() ?>
            <input type="hidden" name="user_id" value="<?= (int) $user['id'] ?>">
            <select name="days">
              <option value="1">封 1 天</option>
              <option value="7" selected>封 7 天</option>
              <option value="30">封 30 天</option>
              <option value="365">封 1 年</option>
              <option value="0">永久封禁</option>
            </select>
            <input type="text" name="reason" placeholder="原因（可选，会展示给用户）" maxlength="200">
            <button class="btn danger" type="submit"><?= ui_icon('shield', 16) ?> 封禁</button>
          </form>
        <?php endif; ?>
      </section>
    </div>

    <section class="card">
      <div class="card-head">
        <h2>观看记录 <span class="count"><?= count($history) ?> 部</span></h2>
      </div>
      <?php if ($snapshotKind === null): ?>
        <?= ui_empty('还没有同步观看记录', '客户端开启云同步后，记录会出现在这里', 'clock') ?>
      <?php elseif (!$history): ?>
        <?= ui_empty('已同步，但没有可展示的条目', '', 'clock') ?>
      <?php else: ?>
        <div class="table-scroll">
          <table class="table">
            <thead><tr><th>番剧</th><th>看到</th><th class="col-num">已看集数</th><th class="col-time">最后观看</th></tr></thead>
            <tbody>
            <?php foreach ($history as $row): ?>
              <tr>
                <td>
                  <div class="title-cell">
                    <?php if ($row['cover'] !== ''): ?>
                      <img class="cover" src="<?= admin_esc($row['cover']) ?>" alt=""
                           loading="lazy" referrerpolicy="no-referrer"
                           onerror="this.style.visibility='hidden'">
                    <?php else: ?>
                      <span class="cover placeholder"></span>
                    <?php endif; ?>
                    <div class="title-text">
                      <div><?= admin_esc($row['title']) ?></div>
                      <?php if ($row['titleOriginal'] !== ''): ?>
                        <small class="muted"><?= admin_esc($row['titleOriginal']) ?></small>
                      <?php endif; ?>
                    </div>
                  </div>
                </td>
                <td class="mono"><?= $row['lastEpisode'] > 0 ? '第 ' . (int) $row['lastEpisode'] . ' 集' : '—' ?></td>
                <td class="col-num mono"><?= (int) $row['episodeCount'] ?></td>
                <td class="col-time mono"><?= $row['lastWatchTime'] > 0 ? admin_esc(ui_time((int) floor($row['lastWatchTime'] / 1000))) : '—' ?></td>
              </tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </section>

    <section class="card">
      <div class="card-head"><h2>收藏与同步</h2></div>
      <?php if ($collect['collectibles'] === null && $collect['collectchanges'] === null && !$blocks): ?>
        <?= ui_empty('还没有同步数据', '', 'shield') ?>
      <?php else: ?>
        <p class="muted small">
          收藏以 Hive 二进制格式同步，服务端无法解析出具体番剧，只能确认同步状态与体积。
        </p>
        <div class="chip-grid">
          <?php if ($collect['collectibles'] !== null): ?>
            <div class="chip-card">
              <span class="chip-label">收藏数据</span>
              <strong><?= number_format($collect['collectibles']['size'] / 1024, 1) ?> KB</strong>
              <small class="muted">更新于 <?= admin_esc(ui_ago($collect['collectibles']['updatedAt'])) ?></small>
            </div>
          <?php endif; ?>
          <?php if ($collect['collectchanges'] !== null): ?>
            <div class="chip-card">
              <span class="chip-label">增量变更</span>
              <strong><?= number_format($collect['collectchanges']['size'] / 1024, 1) ?> KB</strong>
              <small class="muted">更新于 <?= admin_esc(ui_ago($collect['collectchanges']['updatedAt'])) ?></small>
            </div>
          <?php endif; ?>
          <?php if (($collect['danmakuShield'] ?? null) !== null): ?>
            <div class="chip-card">
              <span class="chip-label">弹幕屏蔽词</span>
              <strong><?= number_format($collect['danmakuShield']['size'] / 1024, 1) ?> KB</strong>
              <small class="muted">更新于 <?= admin_esc(ui_ago($collect['danmakuShield']['updatedAt'])) ?></small>
            </div>
          <?php endif; ?>
          <div class="chip-card">
            <span class="chip-label">同步块</span>
            <strong><?= count($blocks) ?> 项</strong>
            <small class="muted">
              <?= $blocks ? '最近 ' . admin_esc(ui_ago((int) $blocks[0]['updated_at'])) : '暂无' ?>
            </small>
          </div>
        </div>
        <?php if ($blocks): ?>
          <details class="fold">
            <summary>查看全部同步块</summary>
            <div class="table-scroll">
              <table class="table">
                <thead><tr><th>类型</th><th>路径</th><th class="col-num">体积</th><th class="col-time">更新时间</th></tr></thead>
                <tbody>
                <?php foreach ($blocks as $b): ?>
                  <?php $path = sync_kind_to_path((string) $b['kind']); ?>
                  <tr>
                    <td class="mono small"><?= admin_esc((string) $b['kind']) ?></td>
                    <td class="mono small"><?= admin_esc($path ?? '—') ?></td>
                    <td class="col-num mono small"><?= number_format(((int) $b['size']) / 1024, 1) ?> KB</td>
                    <td class="col-time mono small"><?= admin_esc(ui_time((int) $b['updated_at'])) ?></td>
                  </tr>
                <?php endforeach; ?>
                </tbody>
              </table>
            </div>
          </details>
        <?php endif; ?>
      <?php endif; ?>
    </section>

    <section class="card">
      <div class="card-head">
        <h2>评论 <span class="count">最近 50 条</span></h2>
        <a class="link small" href="/user/?a=comments&uid=<?= (int) $user['id'] ?>">查看全部</a>
      </div>
      <?php if (!$comments): ?>
        <?= ui_empty('没有评论', '', 'comments') ?>
      <?php else: ?>
        <ul class="comment-list">
        <?php foreach ($comments as $c): ?>
          <?php $deleted = (int) $c['deleted'] === 1; ?>
          <li class="comment-item<?= $deleted ? ' is-deleted' : '' ?>">
            <div class="comment-body"><?= ui_excerpt((string) $c['content'], 200) ?></div>
            <div class="comment-meta">
              <span class="mono small"><?= admin_esc((string) $c['target_type']) ?>#<?= (int) $c['target_id'] ?></span>
              <span class="muted small"><?= admin_esc(ui_time((int) $c['created_at'])) ?></span>
              <?php if ($deleted): ?><?= ui_badge('已删除', 'muted') ?><?php endif; ?>
              <form method="post" action="/user/?a=<?= $deleted ? 'restore-comment' : 'delete-comment' ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="comment_id" value="<?= (int) $c['id'] ?>">
                <input type="hidden" name="back" value="/user/?a=user&id=<?= (int) $user['id'] ?>">
                <button class="btn small <?= $deleted ? '' : 'danger' ?>" type="submit">
                  <?= $deleted ? '恢复' : '删除' ?>
                </button>
              </form>
            </div>
          </li>
        <?php endforeach; ?>
        </ul>
      <?php endif; ?>
    </section>

    <section class="card">
      <div class="card-head"><h2>弹幕 <span class="count">最近 50 条</span></h2></div>
      <?php if (!$danmaku): ?>
        <?= ui_empty('没有弹幕', '', 'danmaku') ?>
      <?php else: ?>
        <ul class="comment-list">
        <?php foreach ($danmaku as $d): ?>
          <?php $deleted = (int) $d['deleted'] === 1; ?>
          <li class="comment-item<?= $deleted ? ' is-deleted' : '' ?>">
            <div class="comment-body"><?= ui_excerpt((string) $d['content'], 200) ?></div>
            <div class="comment-meta">
              <span class="mono small">番剧 <?= (int) $d['bangumi_id'] ?> · 第 <?= (int) $d['episode'] ?> 集</span>
              <span class="muted small"><?= admin_esc(ui_time((int) $d['created_at'])) ?></span>
              <?php if ($deleted): ?><?= ui_badge('已删除', 'muted') ?><?php endif; ?>
              <?php if (!$deleted): ?>
                <form method="post" action="/user/?a=delete-danmaku">
                  <?= csrf_field() ?>
                  <input type="hidden" name="danmaku_id" value="<?= (int) $d['id'] ?>">
                  <input type="hidden" name="back" value="/user/?a=user&id=<?= (int) $user['id'] ?>">
                  <button class="btn small danger" type="submit">删除</button>
                </form>
              <?php endif; ?>
            </div>
          </li>
        <?php endforeach; ?>
        </ul>
      <?php endif; ?>
    </section>
    <?php
    render_page($name !== '' ? $name : '用户详情', (string) ob_get_clean(), 'users');
}

// ---------------------------------------------------------------------------
// 评论 / 弹幕
// ---------------------------------------------------------------------------

function render_comments(): void
{
    $q = admin_q('q');
    $showDeleted = admin_q('state', 'live', 16) === 'all';
    $uid = admin_int('uid');
    $targetType = admin_q('type');
    $pageNo = max(1, admin_int('p', 1));
    $perPage = 30;

    $where = [];
    $args = [];
    if (!$showDeleted) {
        $where[] = 'c.deleted = 0';
    }
    if ($q !== '') {
        $where[] = '(c.content LIKE ? OR u.nickname LIKE ? OR u.email LIKE ?'
            . ' OR (c.target_type || "#" || c.target_id) LIKE ?)';
        $like = '%' . $q . '%';
        array_push($args, $like, $like, $like, $like);
    }
    if ($uid > 0) {
        $where[] = 'c.user_id = ?';
        $args[] = $uid;
    }
    if ($targetType !== '') {
        $where[] = 'c.target_type = ?';
        $args[] = $targetType;
    }
    $whereSql = $where ? 'WHERE ' . implode(' AND ', $where) : '';

    $pdo = admin_db();
    $countStmt = $pdo->prepare(
        'SELECT COUNT(*) FROM comments c JOIN users u ON u.id = c.user_id ' . $whereSql
    );
    $countStmt->execute($args);
    $page = admin_paginate((int) $countStmt->fetchColumn(), $perPage, $pageNo);

    $stmt = $pdo->prepare(
        'SELECT c.*, u.nickname, u.email, u.title
         FROM comments c JOIN users u ON u.id = c.user_id
         ' . $whereSql . '
         ORDER BY c.id DESC
         LIMIT ' . $page['perPage'] . ' OFFSET ' . $page['offset']
    );
    $stmt->execute($args);
    $rows = $stmt->fetchAll();

    ob_start();
    ?>
    <?= ui_page_head('评论', '共 ' . $page['total'] . ' 条，删除后可恢复') ?>

    <form class="filters" method="get" action="/user/">
      <input type="hidden" name="a" value="comments">
      <?php if ($uid > 0): ?><input type="hidden" name="uid" value="<?= $uid ?>"><?php endif; ?>
      <div class="filter-search">
        <span class="filter-icon"><?= ui_icon('search', 18) ?></span>
        <input type="search" name="q" value="<?= admin_esc($q) ?>" placeholder="搜索内容、用户或目标（如 bangumi#123）" autocomplete="off">
      </div>
      <select name="type" onchange="this.form.submit()">
        <option value="">全部目标</option>
        <?php foreach (['bangumi' => '条目', 'episode' => '集数', 'character' => '角色'] as $value => $label): ?>
          <option value="<?= $value ?>"<?= $targetType === $value ? ' selected' : '' ?>><?= $label ?></option>
        <?php endforeach; ?>
      </select>
      <select name="state" onchange="this.form.submit()">
        <option value="live"<?= !$showDeleted ? ' selected' : '' ?>>仅正常</option>
        <option value="all"<?= $showDeleted ? ' selected' : '' ?>>含已删除</option>
      </select>
      <button class="btn primary" type="submit">筛选</button>
      <?php if ($q !== '' || $uid > 0 || $targetType !== '' || $showDeleted): ?>
        <a class="btn ghost" href="/user/?a=comments">重置</a>
      <?php endif; ?>
    </form>

    <?php if ($uid > 0): ?>
      <?php $filterUser = admin_find_user($uid); ?>
      <div class="notice">
        正在查看 <?= admin_esc($filterUser ? admin_email_of($filterUser) : ('用户 #' . $uid)) ?> 的评论
        <a class="link" href="/user/?a=comments">查看全部</a>
      </div>
    <?php endif; ?>

    <section class="card flush">
      <?php if (!$rows): ?>
        <?= ui_empty('没有评论', $q !== '' || $uid > 0 ? '换个关键词试试' : '用户在条目、集数页发表评论后会出现在这里', 'comments') ?>
      <?php else: ?>
        <ul class="comment-list padded">
        <?php foreach ($rows as $c): ?>
          <?php
            $deleted = (int) $c['deleted'] === 1;
            $back = '/user/?a=comments' . ($q !== '' ? '&q=' . urlencode($q) : '')
                . ($showDeleted ? '&state=all' : '')
                . ($uid > 0 ? '&uid=' . $uid : '')
                . ($targetType !== '' ? '&type=' . urlencode($targetType) : '')
                . ($page['page'] > 1 ? '&p=' . $page['page'] : '');
          ?>
          <li class="comment-item<?= $deleted ? ' is-deleted' : '' ?>">
            <div class="comment-top">
              <a class="comment-user" href="/user/?a=user&id=<?= (int) $c['user_id'] ?>">
                <span class="avatar-sm"><?= admin_esc(mb_substr(trim((string) $c['nickname']) !== '' ? (string) $c['nickname'] : (string) $c['email'], 0, 1, 'UTF-8')) ?></span>
                <span>
                  <strong><?= admin_esc(trim((string) $c['nickname']) !== '' ? (string) $c['nickname'] : (string) $c['email']) ?></strong>
                  <?php if (trim((string) ($c['title'] ?? '')) !== ''): ?>
                    <span class="title-chip"><?= admin_esc((string) $c['title']) ?></span>
                  <?php endif; ?>
                </span>
              </a>
              <span class="comment-target mono small"><?= admin_esc((string) $c['target_type']) ?>#<?= (int) $c['target_id'] ?></span>
            </div>
            <div class="comment-body"><?= ui_excerpt((string) $c['content'], 400) ?></div>
            <div class="comment-meta">
              <span class="muted small"><?= admin_esc(ui_time((int) $c['created_at'])) ?></span>
              <span class="muted small">#<?= (int) $c['id'] ?></span>
              <?php if ($deleted): ?><?= ui_badge('已删除', 'muted') ?><?php endif; ?>
              <span class="spacer"></span>
              <form method="post" action="/user/?a=<?= $deleted ? 'restore-comment' : 'delete-comment' ?>"
                    onsubmit="return confirm('<?= $deleted ? '恢复这条评论？' : '删除这条评论？用户端将立即看不到。' ?>');">
                <?= csrf_field() ?>
                <input type="hidden" name="comment_id" value="<?= (int) $c['id'] ?>">
                <input type="hidden" name="back" value="<?= admin_esc($back) ?>">
                <button class="btn small <?= $deleted ? '' : 'danger' ?>" type="submit">
                  <?= $deleted ? ui_icon('restore', 15) . ' 恢复' : ui_icon('trash', 15) . ' 删除' ?>
                </button>
              </form>
            </div>
          </li>
        <?php endforeach; ?>
        </ul>
      <?php endif; ?>
    </section>

    <?php if ($rows): ?>
      <div class="table-foot">
        <span class="muted small"><?= admin_esc(ui_pager_summary($page, '条评论')) ?></span>
        <?= ui_pager($page, ui_link([
            'a' => 'comments',
            'q' => $q,
            'uid' => $uid,
            'type' => $targetType,
            'state' => $showDeleted ? 'all' : '',
        ])) ?>
      </div>
    <?php endif; ?>
    <?php
    render_page('评论', (string) ob_get_clean(), 'comments');
}

function render_danmaku(): void
{
    $q = admin_q('q');
    $showDeleted = admin_q('state', 'live', 16) === 'all';
    $uid = admin_int('uid');
    $bangumiId = admin_int('bid');
    $pageNo = max(1, admin_int('p', 1));
    $perPage = 30;

    $where = [];
    $args = [];
    if (!$showDeleted) {
        $where[] = 'd.deleted = 0';
    }
    if ($q !== '') {
        $where[] = '(d.content LIKE ? OR u.nickname LIKE ? OR u.email LIKE ?)';
        $like = '%' . $q . '%';
        array_push($args, $like, $like, $like);
    }
    if ($uid > 0) {
        $where[] = 'd.user_id = ?';
        $args[] = $uid;
    }
    if ($bangumiId > 0) {
        $where[] = 'd.bangumi_id = ?';
        $args[] = $bangumiId;
    }
    $whereSql = $where ? 'WHERE ' . implode(' AND ', $where) : '';

    $pdo = admin_db();
    $countStmt = $pdo->prepare(
        'SELECT COUNT(*) FROM danmaku d JOIN users u ON u.id = d.user_id ' . $whereSql
    );
    $countStmt->execute($args);
    $page = admin_paginate((int) $countStmt->fetchColumn(), $perPage, $pageNo);

    $stmt = $pdo->prepare(
        'SELECT d.*, u.nickname, u.email
         FROM danmaku d JOIN users u ON u.id = d.user_id
         ' . $whereSql . '
         ORDER BY d.id DESC
         LIMIT ' . $page['perPage'] . ' OFFSET ' . $page['offset']
    );
    $stmt->execute($args);
    $rows = $stmt->fetchAll();

    ob_start();
    ?>
    <?= ui_page_head('弹幕', '共 ' . $page['total'] . ' 条，按时间倒序') ?>

    <form class="filters" method="get" action="/user/">
      <input type="hidden" name="a" value="danmaku">
      <div class="filter-search">
        <span class="filter-icon"><?= ui_icon('search', 18) ?></span>
        <input type="search" name="q" value="<?= admin_esc($q) ?>" placeholder="搜索弹幕内容或用户" autocomplete="off">
      </div>
      <input class="narrow" type="number" name="bid" value="<?= $bangumiId > 0 ? $bangumiId : '' ?>" placeholder="番剧 ID">
      <select name="state" onchange="this.form.submit()">
        <option value="live"<?= !$showDeleted ? ' selected' : '' ?>>仅正常</option>
        <option value="all"<?= $showDeleted ? ' selected' : '' ?>>含已删除</option>
      </select>
      <button class="btn primary" type="submit">筛选</button>
      <?php if ($q !== '' || $uid > 0 || $bangumiId > 0 || $showDeleted): ?>
        <a class="btn ghost" href="/user/?a=danmaku">重置</a>
      <?php endif; ?>
    </form>

    <?php if ($uid > 0): ?>
      <?php $filterUser = admin_find_user($uid); ?>
      <div class="notice">
        正在查看 <?= admin_esc($filterUser ? admin_email_of($filterUser) : ('用户 #' . $uid)) ?> 的弹幕
        <a class="link" href="/user/?a=danmaku">查看全部</a>
      </div>
    <?php endif; ?>

    <section class="card flush">
      <?php if (!$rows): ?>
        <?= ui_empty('没有弹幕', '用户发送弹幕后会出现在这里', 'danmaku') ?>
      <?php else: ?>
        <ul class="comment-list padded">
        <?php foreach ($rows as $d): ?>
          <?php
            $deleted = (int) $d['deleted'] === 1;
            $back = '/user/?a=danmaku' . ($q !== '' ? '&q=' . urlencode($q) : '')
                . ($showDeleted ? '&state=all' : '')
                . ($uid > 0 ? '&uid=' . $uid : '')
                . ($bangumiId > 0 ? '&bid=' . $bangumiId : '')
                . ($page['page'] > 1 ? '&p=' . $page['page'] : '');
            $seconds = intdiv((int) $d['position_ms'], 1000);
          ?>
          <li class="comment-item<?= $deleted ? ' is-deleted' : '' ?>">
            <div class="comment-top">
              <a class="comment-user" href="/user/?a=user&id=<?= (int) $d['user_id'] ?>">
                <span class="avatar-sm"><?= admin_esc(mb_substr(trim((string) $d['nickname']) !== '' ? (string) $d['nickname'] : (string) $d['email'], 0, 1, 'UTF-8')) ?></span>
                <strong><?= admin_esc(trim((string) $d['nickname']) !== '' ? (string) $d['nickname'] : (string) $d['email']) ?></strong>
              </a>
              <a class="comment-target mono small" href="/user/?a=danmaku&bid=<?= (int) $d['bangumi_id'] ?>">
                番剧 <?= (int) $d['bangumi_id'] ?> · 第 <?= (int) $d['episode'] ?> 集 · <?= sprintf('%02d:%02d', intdiv($seconds, 60), $seconds % 60) ?>
              </a>
            </div>
            <div class="comment-body"><?= ui_excerpt((string) $d['content'], 400) ?></div>
            <div class="comment-meta">
              <span class="muted small"><?= admin_esc(ui_time((int) $d['created_at'])) ?></span>
              <span class="muted small">#<?= (int) $d['id'] ?></span>
              <?php if ($deleted): ?><?= ui_badge('已删除', 'muted') ?><?php endif; ?>
              <span class="spacer"></span>
              <?php if (!$deleted): ?>
                <form method="post" action="/user/?a=delete-danmaku"
                      onsubmit="return confirm('删除这条弹幕？');">
                  <?= csrf_field() ?>
                  <input type="hidden" name="danmaku_id" value="<?= (int) $d['id'] ?>">
                  <input type="hidden" name="back" value="<?= admin_esc($back) ?>">
                  <button class="btn small danger" type="submit"><?= ui_icon('trash', 15) ?> 删除</button>
                </form>
              <?php endif; ?>
            </div>
          </li>
        <?php endforeach; ?>
        </ul>
      <?php endif; ?>
    </section>

    <?php if ($rows): ?>
      <div class="table-foot">
        <span class="muted small"><?= admin_esc(ui_pager_summary($page, '条弹幕')) ?></span>
        <?= ui_pager($page, ui_link([
            'a' => 'danmaku',
            'q' => $q,
            'uid' => $uid,
            'bid' => $bangumiId,
            'state' => $showDeleted ? 'all' : '',
        ])) ?>
      </div>
    <?php endif; ?>
    <?php
    render_page('弹幕', (string) ob_get_clean(), 'danmaku');
}

// ---------------------------------------------------------------------------
// 操作日志
// ---------------------------------------------------------------------------

function render_audit(): void
{
    $pageNo = max(1, admin_int('p', 1));
    $perPage = 40;
    $pdo = admin_db();
    $total = (int) $pdo->query('SELECT COUNT(*) FROM admin_audit_log')->fetchColumn();
    $page = admin_paginate($total, $perPage, $pageNo);
    $rows = $pdo->query(
        'SELECT * FROM admin_audit_log ORDER BY id DESC
         LIMIT ' . $page['perPage'] . ' OFFSET ' . $page['offset']
    )->fetchAll();

    $labels = [
        'ban' => ['封禁用户', 'danger'],
        'unban' => ['解除封禁', 'ok'],
        'delete-comment' => ['删除评论', 'warn'],
        'restore-comment' => ['恢复评论', 'ok'],
        'delete-danmaku' => ['删除弹幕', 'warn'],
        'set-title' => ['设置称号', 'muted'],
        'login' => ['登录后台', 'muted'],
    ];

    ob_start();
    ?>
    <?= ui_page_head('操作日志', '后台的写操作都会留痕，便于回溯') ?>

    <section class="card flush">
      <?php if (!$rows): ?>
        <?= ui_empty('还没有操作记录', '封禁、删除、设置称号等操作会记录在这里', 'log') ?>
      <?php else: ?>
        <div class="table-scroll">
          <table class="table">
            <thead><tr><th>操作</th><th>对象</th><th>说明</th><th>IP</th><th class="col-time">时间</th></tr></thead>
            <tbody>
            <?php foreach ($rows as $row): ?>
              <?php [$label, $tone] = $labels[(string) $row['action']] ?? [(string) $row['action'], 'muted']; ?>
              <tr>
                <td><?= ui_badge($label, $tone) ?></td>
                <td class="mono small">
                  <?php if ((int) $row['target_user'] > 0): ?>
                    <a class="link" href="/user/?a=user&id=<?= (int) $row['target_user'] ?>">#<?= (int) $row['target_user'] ?></a>
                  <?php else: ?>—<?php endif; ?>
                </td>
                <td class="small"><?= admin_esc((string) $row['detail']) ?: '<span class="muted">—</span>' ?></td>
                <td class="mono small"><?= admin_esc((string) $row['ip']) ?></td>
                <td class="col-time mono small"><?= admin_esc(ui_time((int) $row['created_at'])) ?></td>
              </tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </section>

    <?php if ($rows): ?>
      <div class="table-foot">
        <span class="muted small"><?= admin_esc(ui_pager_summary($page, '条记录')) ?></span>
        <?= ui_pager($page, ui_link(['a' => 'audit'])) ?>
      </div>
    <?php endif; ?>
    <?php
    render_page('操作日志', (string) ob_get_clean(), 'audit');
}

// ---------------------------------------------------------------------------
// 样式
// ---------------------------------------------------------------------------

function admin_css(): string
{
    return <<<'CSS'
:root{
  --bg:#0f0d13; --bg-soft:#15121b; --panel:#1a1621; --panel-2:#211c29;
  --line:#2b2534; --line-soft:#241f2c;
  --text:#eae6f1; --text-2:#b6aec4; --muted:#867d95;
  --accent:#c08cff; --accent-soft:#2b2039; --accent-ink:#241634;
  --ok:#5fd18c; --ok-soft:#16311f;
  --warn:#ffbf5f; --warn-soft:#33260f;
  --danger:#ff7188; --danger-soft:#361a21;
  --radius:16px; --radius-sm:10px;
  --shadow:0 10px 30px rgba(0,0,0,.28);
}
@media (prefers-color-scheme: light){
  :root{
    --bg:#f6f4f8; --bg-soft:#efeaf5; --panel:#ffffff; --panel-2:#faf7fd;
    --line:#e3dced; --line-soft:#ece6f3;
    --text:#241d2e; --text-2:#514563; --muted:#7d7290;
    --accent:#7b3fd1; --accent-soft:#f0e6ff; --accent-ink:#3d1c6b;
    --ok:#157f47; --ok-soft:#e2f7ec;
    --warn:#96620a; --warn-soft:#fdf1d9;
    --danger:#c22a45; --danger-soft:#fde7eb;
    --shadow:0 10px 30px rgba(50,30,90,.08);
  }
}
*{box-sizing:border-box}
html,body{height:100%}
body{
  margin:0;background:var(--bg);color:var(--text);
  font:15px/1.6 -apple-system,BlinkMacSystemFont,"PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
  -webkit-font-smoothing:antialiased;
}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:none;color:var(--text)}
.ic{flex:none;display:block}
.muted{color:var(--muted)}
.small{font-size:12.5px}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px}
.center{text-align:center}
.danger-text{color:var(--danger)}
.spacer{flex:1}
.clamp-1{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}

/* ---------- 外壳 ---------- */
.shell{display:flex;min-height:100vh}
.sidebar{
  width:236px;flex:none;display:flex;flex-direction:column;gap:8px;
  padding:18px 14px;background:var(--bg-soft);border-right:1px solid var(--line);
  position:sticky;top:0;height:100vh;
}
.brand{display:flex;align-items:center;gap:11px;padding:6px 10px 18px}
.logo-dot{
  width:34px;height:34px;border-radius:11px;flex:none;
  background:linear-gradient(135deg,var(--accent),#ff9ecd 70%);
  box-shadow:0 4px 14px rgba(192,140,255,.35);
}
.brand-text{display:flex;flex-direction:column;line-height:1.25}
.brand-text strong{font-size:16px;letter-spacing:.4px}
.brand-text small{color:var(--muted);font-size:12px}
.nav{display:flex;flex-direction:column;gap:2px}
.nav-item{
  display:flex;align-items:center;gap:11px;padding:10px 12px;border-radius:12px;
  color:var(--text-2);font-size:14.5px;transition:background .16s,color .16s;
}
.nav-item:hover{background:var(--panel);color:var(--text)}
.nav-item.active{background:var(--accent-soft);color:var(--accent);font-weight:600}
.nav-item.quiet{color:var(--muted);font-size:13.5px}
.nav-count{
  margin-left:auto;font-style:normal;font-size:11.5px;font-weight:600;
  background:var(--danger);color:#fff;border-radius:999px;padding:1px 7px;
}
.sidebar-foot{margin-top:auto;display:flex;flex-direction:column;gap:2px;
  padding-top:12px;border-top:1px solid var(--line)}
.main{flex:1;min-width:0;display:flex;flex-direction:column}
.mobile-bar{display:none;align-items:center;gap:10px;padding:10px 14px;
  border-bottom:1px solid var(--line);background:var(--bg-soft)}
.icon-btn{display:inline-flex;align-items:center;justify-content:center;
  width:38px;height:38px;border-radius:10px;color:var(--text);cursor:pointer}
.icon-btn:hover{background:var(--panel)}
.scrim{display:none}
.content{width:100%;max-width:1160px;margin:0 auto;padding:26px 24px 72px}

/* ---------- 页头 ---------- */
.page-head{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;
  margin-bottom:20px;flex-wrap:wrap}
.page-head h1{margin:0;font-size:25px;letter-spacing:.3px;font-weight:700}
.page-head p{margin:5px 0 0;color:var(--muted);font-size:13.5px}
.page-head-actions{display:flex;gap:8px;flex-wrap:wrap}
.back-link{margin:0 0 12px}
.back-link a{display:inline-flex;align-items:center;gap:6px;color:var(--muted);font-size:13.5px}
.back-link a:hover{color:var(--accent)}

/* ---------- 卡片 ---------- */
.card{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);
  padding:18px 20px;margin-bottom:16px}
.card.flush{padding:0;overflow:hidden}
.card-head{display:flex;align-items:center;justify-content:space-between;gap:12px;
  margin-bottom:14px;flex-wrap:wrap}
.card.flush .card-head{padding:16px 20px 0;margin-bottom:14px}
.card-head h2{margin:0;font-size:15.5px;font-weight:650}
.card-head .count{color:var(--muted);font-weight:400;font-size:12.5px;margin-left:6px}
.grid-2{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.grid-2>.card{margin-bottom:16px}

/* ---------- 概览 ---------- */
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:16px}
.stat{display:block;background:var(--panel);border:1px solid var(--line);
  border-radius:var(--radius);padding:16px 18px;color:inherit;transition:border-color .16s,transform .16s}
a.stat:hover{border-color:var(--accent);transform:translateY(-1px)}
.stat.warn{border-color:color-mix(in srgb,var(--danger) 40%,var(--line))}
.stat-top{display:flex;align-items:center;gap:8px;color:var(--muted);font-size:13px}
.stat-value{font-size:28px;font-weight:700;letter-spacing:.5px;margin:6px 0 2px;
  font-variant-numeric:tabular-nums}
.stat-hint{color:var(--muted);font-size:12px}
.kv-rows{display:flex;flex-direction:column;gap:2px}
.kv-row{display:flex;align-items:baseline;gap:10px;padding:9px 0;
  border-bottom:1px dashed var(--line-soft)}
.kv-row:last-child{border-bottom:none}
.kv-label{color:var(--muted);font-size:13.5px;min-width:76px}
.kv-value{font-size:17px;font-weight:650;font-variant-numeric:tabular-nums}
.bars{display:flex;align-items:flex-end;gap:8px;height:96px;padding-top:6px}
.bar-col{flex:1;display:flex;flex-direction:column;align-items:center;gap:6px;justify-content:flex-end}
.bar{width:100%;max-width:38px;border-radius:6px 6px 3px 3px;
  background:linear-gradient(180deg,var(--accent),color-mix(in srgb,var(--accent) 45%,transparent))}
.bar-label{font-size:11px;color:var(--muted);white-space:nowrap}
.mini-list{list-style:none;margin:0;padding:0;display:flex;flex-direction:column}
.mini-list li{display:flex;align-items:center;gap:10px;padding:9px 0;
  border-bottom:1px dashed var(--line-soft)}
.mini-list li:last-child{border-bottom:none}
.mini-main{display:flex;align-items:center;gap:10px;min-width:0;flex:1;color:inherit}
.mini-main:hover strong{color:var(--accent)}
.mini-text{display:flex;flex-direction:column;min-width:0;line-height:1.35}
.mini-text strong{font-size:14px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.mini-text small{color:var(--muted);font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.mini-side{display:flex;align-items:center;gap:8px;flex:none}
.avatar-sm{width:32px;height:32px;border-radius:10px;flex:none;display:inline-flex;
  align-items:center;justify-content:center;font-size:13.5px;font-weight:600;
  background:var(--accent-soft);color:var(--accent);text-transform:uppercase}

/* ---------- 筛选器 ---------- */
.filters{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:14px}
.filter-search{position:relative;flex:1;min-width:220px;display:flex;align-items:center}
.filter-icon{position:absolute;left:12px;color:var(--muted);display:flex}
.filter-search input{padding-left:38px;width:100%}
input[type=search],input[type=text],input[type=number],input[type=password],select{
  background:var(--panel);border:1px solid var(--line);color:var(--text);
  border-radius:11px;padding:9px 12px;font:inherit;font-size:14px;min-width:0;
  transition:border-color .16s,box-shadow .16s;appearance:none;
}
select{background-image:linear-gradient(45deg,transparent 50%,var(--muted) 50%),
  linear-gradient(135deg,var(--muted) 50%,transparent 50%);
  background-position:calc(100% - 17px) 50%,calc(100% - 12px) 50%;
  background-size:5px 5px,5px 5px;background-repeat:no-repeat;padding-right:34px}
input:focus,select:focus{outline:none;border-color:var(--accent);
  box-shadow:0 0 0 3px color-mix(in srgb,var(--accent) 22%,transparent)}
input.narrow{width:120px}
.notice{background:var(--accent-soft);border:1px solid color-mix(in srgb,var(--accent) 30%,transparent);
  color:var(--text);border-radius:var(--radius-sm);padding:10px 14px;margin-bottom:14px;
  font-size:13.5px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}

/* ---------- 按钮 ---------- */
.btn{
  display:inline-flex;align-items:center;gap:6px;justify-content:center;
  background:var(--panel-2);color:var(--text);border:1px solid var(--line);
  border-radius:11px;padding:8px 15px;font:inherit;font-size:14px;cursor:pointer;
  transition:background .16s,border-color .16s,color .16s;white-space:nowrap;
}
.btn:hover{background:color-mix(in srgb,var(--panel-2) 70%,var(--text) 8%);color:var(--text)}
.btn.primary{background:var(--accent);color:var(--accent-ink);border-color:transparent;font-weight:600}
.btn.primary:hover{background:color-mix(in srgb,var(--accent) 85%,#fff)}
.btn.danger{color:var(--danger);border-color:color-mix(in srgb,var(--danger) 45%,var(--line))}
.btn.danger:hover{background:var(--danger-soft);color:var(--danger)}
.btn.ghost{background:transparent;color:var(--muted)}
.btn.small{padding:5px 11px;font-size:13px;border-radius:9px}
.btn.block{width:100%;padding:11px;font-size:15px}

/* ---------- 表格 ---------- */
.table-scroll{overflow-x:auto}
.table{width:100%;border-collapse:collapse;font-size:14px}
.table th,.table td{padding:11px 14px;text-align:left;border-bottom:1px solid var(--line-soft);
  vertical-align:middle}
.table th{
  background:var(--panel-2);color:var(--muted);font-weight:600;font-size:12.5px;
  letter-spacing:.4px;white-space:nowrap;position:sticky;top:0;z-index:1;
}
.table tbody tr:last-child td{border-bottom:none}
.table tbody tr:hover td{background:color-mix(in srgb,var(--panel-2) 60%,transparent)}
.col-num{text-align:right;font-variant-numeric:tabular-nums;width:76px}
.col-time{white-space:nowrap;color:var(--text-2);font-size:12.5px}
.col-action{text-align:right;width:88px}
.user-cell{display:flex;align-items:center;gap:10px;color:inherit}
.user-cell:hover .user-name{color:var(--accent)}
.user-cell-text{display:flex;flex-direction:column;line-height:1.35;min-width:0}
.user-name{font-weight:600;font-size:14px;display:flex;align-items:center;gap:6px;
  flex-wrap:wrap;min-width:0}
/* 昵称过长时先省略昵称，不要把称号挤出单元格。 */
.user-name-text{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0}
.title-chip{
  display:inline-block;font-size:11.5px;font-weight:600;letter-spacing:.3px;
  padding:1px 7px;border-radius:999px;color:#8a5a00;white-space:nowrap;
  background:rgba(217,160,32,.13);border:1px solid rgba(217,160,32,.55);
}
@media (prefers-color-scheme: dark){
  .title-chip{color:#f0c463;background:rgba(217,160,32,.16);border-color:rgba(217,160,32,.5)}
}
.table-foot{display:flex;align-items:center;justify-content:space-between;
  gap:12px;flex-wrap:wrap;margin-top:12px}
.badge{display:inline-block;padding:2px 9px;border-radius:999px;font-size:12px;
  font-weight:600;white-space:nowrap;border:1px solid transparent}
.badge.ok{color:var(--ok);background:var(--ok-soft)}
.badge.danger{color:var(--danger);background:var(--danger-soft)}
.badge.warn{color:var(--warn);background:var(--warn-soft)}
.badge.muted{color:var(--muted);background:var(--panel-2)}
.pager{display:flex;gap:4px;align-items:center}
.pg{display:inline-flex;align-items:center;justify-content:center;
  min-width:34px;height:34px;padding:0 8px;border-radius:9px;font-size:13.5px;
  color:var(--text-2);background:var(--panel);border:1px solid var(--line)}
.pg:hover{border-color:var(--accent);color:var(--accent)}
.pg.current{background:var(--accent);color:var(--accent-ink);border-color:transparent;font-weight:700}
.pg.disabled{opacity:.35}
.pg.gap{border:none;background:none}

/* ---------- 详情页 ---------- */
.profile{display:flex;gap:16px;align-items:flex-start;background:var(--panel);
  border:1px solid var(--line);border-radius:var(--radius);padding:20px;margin-bottom:16px}
.profile-avatar{width:62px;height:62px;border-radius:18px;flex:none;
  display:flex;align-items:center;justify-content:center;font-size:25px;font-weight:700;
  background:linear-gradient(135deg,var(--accent-soft),color-mix(in srgb,var(--accent) 28%,transparent));
  color:var(--accent)}
.profile-main{min-width:0;flex:1}
.profile-main h1{margin:0 0 6px;font-size:21px;display:flex;align-items:center;
  gap:8px;flex-wrap:wrap;font-weight:700}
.profile-meta{margin:0 0 4px;color:var(--muted);font-size:13px;
  display:flex;gap:7px;flex-wrap:wrap;align-items:center}
.dot{opacity:.5}
.ban-reason{margin-top:8px;padding:8px 12px;border-radius:10px;
  background:var(--danger-soft);color:var(--danger);font-size:13px}
.inline-form{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
.inline-form input{flex:1;min-width:160px}
.ban-form{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px}
.ban-form input{flex:1;min-width:150px}
.ban-form select{min-width:104px}
.chip-grid{display:flex;gap:10px;flex-wrap:wrap;margin:12px 0}
.chip-card{display:flex;flex-direction:column;gap:2px;background:var(--panel-2);
  border:1px solid var(--line);border-radius:12px;padding:11px 15px;min-width:130px}
.chip-label{color:var(--muted);font-size:12px}
.chip-card strong{font-size:17px;font-variant-numeric:tabular-nums}
.fold{margin-top:12px;border-top:1px dashed var(--line-soft);padding-top:10px}
.fold summary{cursor:pointer;color:var(--muted);font-size:13px;padding:4px 0}
.fold summary:hover{color:var(--accent)}
.title-cell{display:flex;gap:10px;align-items:center;min-width:0}
.cover{width:36px;height:50px;border-radius:7px;object-fit:cover;flex:none;
  background:var(--panel-2)}
.cover.placeholder{display:block;border:1px dashed var(--line)}
.title-text{min-width:0;line-height:1.35}
.title-text small{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:340px}

/* ---------- 评论卡片 ---------- */
.comment-list{list-style:none;margin:0;padding:0;display:flex;flex-direction:column}
.comment-list.padded{padding:6px 0}
.comment-item{padding:14px 20px;border-bottom:1px solid var(--line-soft)}
.comment-list.padded .comment-item{padding-left:20px;padding-right:20px}
.comment-item:last-child{border-bottom:none}
.comment-item:hover{background:color-mix(in srgb,var(--panel-2) 55%,transparent)}
.comment-item.is-deleted{opacity:.62}
.comment-top{display:flex;align-items:center;gap:10px;justify-content:space-between;
  margin-bottom:7px;flex-wrap:wrap}
.comment-user{display:inline-flex;align-items:center;gap:8px;color:inherit;font-size:13.5px}
.comment-user strong{font-weight:600}
.comment-user:hover strong{color:var(--accent)}
.comment-target{color:var(--muted);background:var(--panel-2);padding:2px 8px;border-radius:8px}
.comment-body{white-space:pre-wrap;word-break:break-word;font-size:14px;line-height:1.65;
  color:var(--text)}
.comment-meta{display:flex;align-items:center;gap:10px;margin-top:8px;flex-wrap:wrap}
.comment-meta form{display:inline-flex;margin:0}

/* ---------- 空状态 ---------- */
.empty{display:flex;flex-direction:column;align-items:center;justify-content:center;
  gap:8px;padding:48px 24px;color:var(--muted);text-align:center}
.empty .ic{opacity:.5}
.empty-title{font-size:14.5px;font-weight:600;color:var(--text-2)}
.empty-hint{font-size:12.5px}

/* ---------- 提示条 ---------- */
.alert{padding:11px 15px;border-radius:12px;margin-bottom:16px;font-size:13.5px}
.alert.ok{background:var(--ok-soft);color:var(--ok)}
.alert.error{background:var(--danger-soft);color:var(--danger)}

/* ---------- 登录 ---------- */
.login-body{display:flex;align-items:center;justify-content:center;min-height:100vh;
  padding:24px;background:radial-gradient(1200px 600px at 20% 0%,var(--accent-soft),transparent 60%),var(--bg)}
.login-card{background:var(--panel);border:1px solid var(--line);border-radius:22px;
  padding:30px 28px;width:100%;max-width:370px;display:flex;flex-direction:column;gap:14px;
  box-shadow:var(--shadow)}
.login-brand{display:flex;align-items:center;gap:12px;margin-bottom:4px}
.login-brand h1{margin:0;font-size:21px;letter-spacing:1px}
.login-brand p{margin:0;color:var(--muted);font-size:12.5px}
.field{display:flex;flex-direction:column;gap:7px;font-size:13.5px;color:var(--text-2)}
.field input{width:100%}
.login-foot{margin:2px 0 0;text-align:center;color:var(--muted);font-size:12px}

/* ---------- 响应式 ---------- */
@media (max-width:1000px){
  .stats{grid-template-columns:repeat(2,1fr)}
  .grid-2{grid-template-columns:1fr}
  .content{padding:20px 16px 64px}
}
@media (max-width:760px){
  .mobile-bar{display:flex}
  .sidebar{position:fixed;left:0;top:0;z-index:30;transform:translateX(-100%);
    transition:transform .22s ease;box-shadow:var(--shadow)}
  .nav-toggle:checked ~ .shell .sidebar{transform:translateX(0)}
  .nav-toggle:checked ~ .shell .scrim{display:block;position:fixed;inset:0;
    background:rgba(0,0,0,.5);z-index:20}
  .stats{grid-template-columns:1fr 1fr;gap:10px}
  .stat{padding:13px 14px}
  .stat-value{font-size:23px}
  .page-head h1{font-size:21px}
  .content{padding:16px 12px 56px}
  .card{padding:15px 14px}
  .comment-item{padding:12px 14px}
  .profile{padding:15px;gap:12px}
  .profile-avatar{width:50px;height:50px;border-radius:14px;font-size:20px}
  .table th,.table td{padding:9px 10px}
  .users-table .col-time{display:none}
  /* 手机宽度下评论/弹幕/同步三列太挤，只保留用户、状态与操作。
     状态列必须留着——看不到「封禁中」就失去了列表的意义。 */
  .users-table .col-num{display:none}
  .users-table .col-sync{display:none}
  .users-table th:first-child,.users-table td:first-child{min-width:150px}
}
@media (max-width:520px){
  .stats{grid-template-columns:1fr}
  .filters .btn{flex:1}
  .title-text small{max-width:200px}
  /* 状态列必须保留（封禁状态是列表的核心信息），
     空间不够时压缩操作列的按钮内边距。 */
  .users-table .col-action .btn{padding:4px 8px;font-size:12px}
}
CSS;
}
