<?php
declare(strict_types=1);

require_once __DIR__ . '/sync_data.php';

function render_login(?string $error = null): void
{
    $flash = admin_take_flash();
    ?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>凉次元 · 管理后台</title>
<style><?= admin_css() ?></style>
</head>
<body class="login-body">
  <form class="login-card" method="post" action="/user/?a=login">
    <h1>凉次元</h1>
    <p class="muted">管理后台</p>
    <?php if ($error !== null): ?>
      <div class="alert error"><?= admin_esc($error) ?></div>
    <?php endif; ?>
    <?php if ($flash !== null): ?>
      <div class="alert <?= admin_esc($flash['kind']) ?>"><?= admin_esc($flash['message']) ?></div>
    <?php endif; ?>
    <input type="hidden" name="csrf" value="<?= admin_esc(csrf_token()) ?>">
    <label>
      访问密码
      <input type="password" name="password" autocomplete="current-password" required autofocus>
    </label>
    <button type="submit">进入</button>
  </form>
</body>
</html>
    <?php
}

function render_page(string $title, string $body, string $active = ''): void
{
    $flash = admin_take_flash();
    $nav = [
        'users' => '用户',
        'comments' => '评论',
        'danmaku' => '弹幕',
    ];
    ?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title><?= admin_esc($title) ?> · 凉次元管理后台</title>
<style><?= admin_css() ?></style>
</head>
<body>
<header class="topbar">
  <div class="brand">凉次元 <span>管理后台</span></div>
  <nav>
    <?php foreach ($nav as $key => $label): ?>
      <a class="<?= $active === $key ? 'active' : '' ?>" href="/user/?a=<?= admin_esc($key) ?>"><?= admin_esc($label) ?></a>
    <?php endforeach; ?>
    <a class="logout" href="/user/?a=logout">退出</a>
  </nav>
</header>
<main>
  <?php if ($flash !== null): ?>
    <div class="alert <?= admin_esc($flash['kind']) ?>"><?= admin_esc($flash['message']) ?></div>
  <?php endif; ?>
  <?= $body ?>
</main>
</body>
</html>
    <?php
}

function render_users(): void
{
    $q = trim((string) ($_GET['q'] ?? ''));
    $pdo = admin_db();
    if ($q !== '') {
        $stmt = $pdo->prepare(
            'SELECT * FROM users
             WHERE email LIKE ? OR nickname LIKE ?
             ORDER BY id DESC LIMIT 200'
        );
        $like = '%' . $q . '%';
        $stmt->execute([$like, $like]);
    } else {
        $stmt = $pdo->query('SELECT * FROM users ORDER BY id DESC LIMIT 200');
    }
    $users = $stmt->fetchAll();

    // 每人一条统计：评论数、弹幕数、是否同步过数据。
    $stats = [];
    foreach ($pdo->query(
        'SELECT user_id, COUNT(*) AS c FROM comments WHERE deleted = 0 GROUP BY user_id'
    ) as $row) {
        $stats[(int) $row['user_id']]['comments'] = (int) $row['c'];
    }
    foreach ($pdo->query(
        'SELECT user_id, COUNT(*) AS c FROM danmaku WHERE deleted = 0 GROUP BY user_id'
    ) as $row) {
        $stats[(int) $row['user_id']]['danmaku'] = (int) $row['c'];
    }
    foreach ($pdo->query(
        'SELECT user_id, COUNT(*) AS c, MAX(updated_at) AS last FROM sync_blobs GROUP BY user_id'
    ) as $row) {
        $stats[(int) $row['user_id']]['syncCount'] = (int) $row['c'];
        $stats[(int) $row['user_id']]['syncLast'] = (int) $row['last'];
    }

    ob_start();
    ?>
    <form class="search" method="get" action="/user/">
      <input type="hidden" name="a" value="users">
      <input type="search" name="q" value="<?= admin_esc($q) ?>" placeholder="搜索邮箱或昵称">
      <button type="submit">搜索</button>
      <?php if ($q !== ''): ?>
        <a class="link" href="/user/?a=users">清除</a>
      <?php endif; ?>
    </form>

    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>用户</th>
            <th>称号</th>
            <th>评论</th>
            <th>弹幕</th>
            <th>同步</th>
            <th>状态</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
        <?php foreach ($users as $user): ?>
          <?php
            $id = (int) $user['id'];
            $s = $stats[$id] ?? [];
            $banned = (int) ($user['banned_until'] ?? 0) > time();
          ?>
          <tr>
            <td class="mono"><?= $id ?></td>
            <td>
              <a class="link" href="/user/?a=user&id=<?= $id ?>">
                <?= admin_esc((string) $user['nickname']) ?>
              </a>
              <div class="muted small"><?= admin_esc((string) $user['email']) ?></div>
            </td>
            <td><?= admin_esc((string) ($user['title'] ?? '')) ?: '<span class="muted">—</span>' ?></td>
            <td class="mono"><?= (int) ($s['comments'] ?? 0) ?></td>
            <td class="mono"><?= (int) ($s['danmaku'] ?? 0) ?></td>
            <td class="mono">
              <?php if (($s['syncCount'] ?? 0) > 0): ?>
                <?= (int) $s['syncCount'] ?> 项
              <?php else: ?>
                <span class="muted">—</span>
              <?php endif; ?>
            </td>
            <td>
              <?php if ($banned): ?>
                <span class="tag danger">已封禁</span>
              <?php else: ?>
                <span class="tag ok">正常</span>
              <?php endif; ?>
            </td>
            <td><a class="link" href="/user/?a=user&id=<?= $id ?>">详情</a></td>
          </tr>
        <?php endforeach; ?>
        <?php if (!$users): ?>
          <tr><td colspan="8" class="muted center">没有匹配的用户</td></tr>
        <?php endif; ?>
        </tbody>
      </table>
    </div>
    <?php
    render_page('用户', (string) ob_get_clean(), 'users');
}

function render_user_detail(int $id): void
{
    $user = admin_find_user($id);
    if (!$user) {
        render_page('用户', '<p class="muted">用户不存在。</p>', 'users');
        return;
    }
    $pdo = admin_db();
    $banned = (int) ($user['banned_until'] ?? 0) > time();

    $commentStmt = $pdo->prepare(
        'SELECT id, target_type, target_id, content, created_at, deleted
         FROM comments WHERE user_id = ? ORDER BY id DESC LIMIT 100'
    );
    $commentStmt->execute([$id]);
    $comments = $commentStmt->fetchAll();

    $danmakuStmt = $pdo->prepare(
        'SELECT id, bangumi_id, episode, content, created_at, deleted
         FROM danmaku WHERE user_id = ? ORDER BY id DESC LIMIT 100'
    );
    $danmakuStmt->execute([$id]);
    $danmaku = $danmakuStmt->fetchAll();

    $collect = collectible_summary($id);
    $snapshotKind = find_history_snapshot_kind($id);
    $history = $snapshotKind !== null ? parse_history_rows(sync_payload_json($id, $snapshotKind) ?? []) : [];
    $blocks = sync_blocks($id);

    ob_start();
    ?>
    <p><a class="link" href="/user/?a=users">← 返回用户列表</a></p>

    <section class="card">
      <h2><?= admin_esc((string) $user['nickname']) ?></h2>
      <div class="kv">
        <div><span class="muted">邮箱</span><?= admin_esc((string) $user['email']) ?></div>
        <div><span class="muted">用户 ID</span><span class="mono"><?= (int) $user['id'] ?></span></div>
        <div><span class="muted">称号</span><?= admin_esc((string) ($user['title'] ?? '')) ?: '—' ?></div>
        <div><span class="muted">注册时间</span><?= $user['created_at'] ? date('Y-m-d H:i', (int) $user['created_at']) : '—' ?></div>
        <div>
          <span class="muted">状态</span>
          <?php if ($banned): ?>
            <span class="tag danger">封禁至 <?= date('Y-m-d H:i', (int) $user['banned_until']) ?></span>
            <?php if (trim((string) $user['ban_reason']) !== ''): ?>
              <span class="muted small">（<?= admin_esc((string) $user['ban_reason']) ?>）</span>
            <?php endif; ?>
          <?php else: ?>
            <span class="tag ok">正常</span>
          <?php endif; ?>
        </div>
      </div>

      <div class="actions">
        <?php if ($banned): ?>
          <form method="post" action="/user/?a=unban">
            <?= csrf_field() ?>
            <input type="hidden" name="user_id" value="<?= (int) $user['id'] ?>">
            <button class="primary" type="submit">解封</button>
          </form>
        <?php else: ?>
          <form method="post" action="/user/?a=ban" class="ban-form">
            <?= csrf_field() ?>
            <input type="hidden" name="user_id" value="<?= (int) $user['id'] ?>">
            <select name="days">
              <option value="1">封 1 天</option>
              <option value="7" selected>封 7 天</option>
              <option value="30">封 30 天</option>
              <option value="0">永久封禁</option>
            </select>
            <input type="text" name="reason" placeholder="原因（可选，会展示给用户）" maxlength="200">
            <button class="danger" type="submit">封禁</button>
          </form>
        <?php endif; ?>
      </div>
    </section>

    <section class="card">
      <h2>观看记录 <span class="muted small"><?= count($history) ?> 部</span></h2>
      <?php if ($snapshotKind === null): ?>
        <p class="muted">该用户还没有同步过观看记录。</p>
      <?php elseif (!$history): ?>
        <p class="muted">已同步，但没有可展示的条目。</p>
      <?php else: ?>
        <div class="table-wrap">
          <table>
            <thead><tr><th>番剧</th><th>看到</th><th>已看集数</th><th>最后观看</th></tr></thead>
            <tbody>
            <?php foreach ($history as $row): ?>
              <tr>
                <td>
                  <div class="title-cell">
                    <?php if ($row['cover'] !== ''): ?>
                      <img src="<?= admin_esc($row['cover']) ?>" alt="" loading="lazy">
                    <?php endif; ?>
                    <div>
                      <div><?= admin_esc($row['title']) ?></div>
                      <?php if ($row['titleOriginal'] !== ''): ?>
                        <div class="muted small"><?= admin_esc($row['titleOriginal']) ?></div>
                      <?php endif; ?>
                    </div>
                  </div>
                </td>
                <td class="mono"><?= $row['lastEpisode'] > 0 ? '第 ' . $row['lastEpisode'] . ' 集' : '—' ?></td>
                <td class="mono"><?= (int) $row['episodeCount'] ?></td>
                <td class="mono"><?= $row['lastWatchTime'] > 0 ? date('Y-m-d H:i', (int) ($row['lastWatchTime'] / 1000)) : '—' ?></td>
              </tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </section>

    <section class="card">
      <h2>收藏</h2>
      <?php if ($collect['collectibles'] === null && $collect['collectchanges'] === null): ?>
        <p class="muted">该用户还没有同步过收藏。</p>
      <?php else: ?>
        <p class="muted small">
          收藏以 Hive 二进制格式同步，服务端无法解析出具体番剧，只能确认同步状态与体积。
        </p>
        <div class="kv">
          <?php if ($collect['collectibles'] !== null): ?>
            <div>
              <span class="muted">收藏数据</span>
              <span class="mono"><?= number_format($collect['collectibles']['size'] / 1024, 1) ?> KB</span>
              <span class="muted small">更新于 <?= date('Y-m-d H:i', $collect['collectibles']['updatedAt']) ?></span>
            </div>
          <?php endif; ?>
          <?php if ($collect['collectchanges'] !== null): ?>
            <div>
              <span class="muted">增量变更</span>
              <span class="mono"><?= number_format($collect['collectchanges']['size'] / 1024, 1) ?> KB</span>
              <span class="muted small">更新于 <?= date('Y-m-d H:i', $collect['collectchanges']['updatedAt']) ?></span>
            </div>
          <?php endif; ?>
        </div>
      <?php endif; ?>
    </section>

    <section class="card">
      <h2>评论 <span class="muted small">最近 100 条</span></h2>
      <?php if (!$comments): ?>
        <p class="muted">没有评论。</p>
      <?php else: ?>
        <div class="table-wrap">
          <table>
            <thead><tr><th>内容</th><th>目标</th><th>时间</th><th>状态</th><th></th></tr></thead>
            <tbody>
            <?php foreach ($comments as $c): ?>
              <tr>
                <td class="content-cell"><?= admin_esc((string) $c['content']) ?></td>
                <td class="mono small"><?= admin_esc((string) $c['target_type']) ?>#<?= (int) $c['target_id'] ?></td>
                <td class="mono small"><?= date('Y-m-d H:i', (int) $c['created_at']) ?></td>
                <td>
                  <?php if ((int) $c['deleted'] === 1): ?>
                    <span class="tag muted">已删除</span>
                  <?php else: ?>
                    <span class="tag ok">正常</span>
                  <?php endif; ?>
                </td>
                <td>
                  <form method="post" action="/user/?a=<?= (int) $c['deleted'] === 1 ? 'restore-comment' : 'delete-comment' ?>">
                    <?= csrf_field() ?>
                    <input type="hidden" name="comment_id" value="<?= (int) $c['id'] ?>">
                    <input type="hidden" name="back" value="/user/?a=user&id=<?= (int) $user['id'] ?>">
                    <button class="link-btn" type="submit"><?= (int) $c['deleted'] === 1 ? '恢复' : '删除' ?></button>
                  </form>
                </td>
              </tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </section>

    <section class="card">
      <h2>弹幕 <span class="muted small">最近 100 条</span></h2>
      <?php if (!$danmaku): ?>
        <p class="muted">没有弹幕。</p>
      <?php else: ?>
        <div class="table-wrap">
          <table>
            <thead><tr><th>内容</th><th>番剧/集</th><th>时间</th><th>状态</th><th></th></tr></thead>
            <tbody>
            <?php foreach ($danmaku as $d): ?>
              <tr>
                <td class="content-cell"><?= admin_esc((string) $d['content']) ?></td>
                <td class="mono small"><?= (int) $d['bangumi_id'] ?> / 第 <?= (int) $d['episode'] ?> 集</td>
                <td class="mono small"><?= date('Y-m-d H:i', (int) $d['created_at']) ?></td>
                <td>
                  <?php if ((int) $d['deleted'] === 1): ?>
                    <span class="tag muted">已删除</span>
                  <?php else: ?>
                    <span class="tag ok">正常</span>
                  <?php endif; ?>
                </td>
                <td>
                  <?php if ((int) $d['deleted'] !== 1): ?>
                    <form method="post" action="/user/?a=delete-danmaku">
                      <?= csrf_field() ?>
                      <input type="hidden" name="danmaku_id" value="<?= (int) $d['id'] ?>">
                      <input type="hidden" name="back" value="/user/?a=user&id=<?= (int) $user['id'] ?>">
                      <button class="link-btn" type="submit">删除</button>
                    </form>
                  <?php endif; ?>
                </td>
              </tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </section>

    <section class="card">
      <h2>同步数据块 <span class="muted small"><?= count($blocks) ?> 项</span></h2>
      <div class="table-wrap">
        <table>
          <thead><tr><th>类型</th><th>路径</th><th>体积</th><th>更新时间</th></tr></thead>
          <tbody>
          <?php foreach ($blocks as $b): ?>
            <?php $path = sync_kind_to_path((string) $b['kind']); ?>
            <tr>
              <td class="mono small"><?= admin_esc((string) $b['kind']) ?></td>
              <td class="mono small"><?= admin_esc($path ?? '—') ?></td>
              <td class="mono small"><?= number_format(((int) $b['size']) / 1024, 1) ?> KB</td>
              <td class="mono small"><?= date('Y-m-d H:i', (int) $b['updated_at']) ?></td>
            </tr>
          <?php endforeach; ?>
          <?php if (!$blocks): ?>
            <tr><td colspan="4" class="muted center">没有同步数据</td></tr>
          <?php endif; ?>
          </tbody>
        </table>
      </div>
    </section>
    <?php
    render_page('用户详情', (string) ob_get_clean(), 'users');
}

function render_comments(): void
{
    $showDeleted = isset($_GET['deleted']);
    $where = $showDeleted ? '' : 'WHERE c.deleted = 0';
    $sql = "SELECT c.*, u.nickname, u.email
            FROM comments c JOIN users u ON u.id = c.user_id
            {$where}
            ORDER BY c.id DESC LIMIT 200";
    $rows = admin_db()->query($sql)->fetchAll();

    ob_start();
    ?>
    <div class="toolbar">
      <span class="muted">最近 200 条<?= $showDeleted ? '（含已删除）' : '' ?></span>
      <?php if ($showDeleted): ?>
        <a class="link" href="/user/?a=comments">只看正常</a>
      <?php else: ?>
        <a class="link" href="/user/?a=comments&deleted=1">显示已删除</a>
      <?php endif; ?>
    </div>
    <div class="table-wrap">
      <table>
        <thead><tr><th>用户</th><th>内容</th><th>目标</th><th>时间</th><th>状态</th><th></th></tr></thead>
        <tbody>
        <?php foreach ($rows as $c): ?>
          <tr>
            <td>
              <a class="link" href="/user/?a=user&id=<?= (int) $c['user_id'] ?>"><?= admin_esc((string) $c['nickname']) ?></a>
              <div class="muted small"><?= admin_esc((string) $c['email']) ?></div>
            </td>
            <td class="content-cell"><?= admin_esc((string) $c['content']) ?></td>
            <td class="mono small"><?= admin_esc((string) $c['target_type']) ?>#<?= (int) $c['target_id'] ?></td>
            <td class="mono small"><?= date('Y-m-d H:i', (int) $c['created_at']) ?></td>
            <td>
              <?php if ((int) $c['deleted'] === 1): ?>
                <span class="tag muted">已删除</span>
              <?php else: ?>
                <span class="tag ok">正常</span>
              <?php endif; ?>
            </td>
            <td>
              <form method="post" action="/user/?a=<?= (int) $c['deleted'] === 1 ? 'restore-comment' : 'delete-comment' ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="comment_id" value="<?= (int) $c['id'] ?>">
                <input type="hidden" name="back" value="/user/?a=comments<?= $showDeleted ? '&deleted=1' : '' ?>">
                <button class="link-btn" type="submit"><?= (int) $c['deleted'] === 1 ? '恢复' : '删除' ?></button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
        <?php if (!$rows): ?>
          <tr><td colspan="6" class="muted center">没有评论</td></tr>
        <?php endif; ?>
        </tbody>
      </table>
    </div>
    <?php
    render_page('评论', (string) ob_get_clean(), 'comments');
}

function render_danmaku(): void
{
    $rows = admin_db()->query(
        'SELECT d.*, u.nickname, u.email
         FROM danmaku d JOIN users u ON u.id = d.user_id
         WHERE d.deleted = 0
         ORDER BY d.id DESC LIMIT 200'
    )->fetchAll();

    ob_start();
    ?>
    <div class="toolbar"><span class="muted">最近 200 条</span></div>
    <div class="table-wrap">
      <table>
        <thead><tr><th>用户</th><th>内容</th><th>番剧/集</th><th>时间</th><th></th></tr></thead>
        <tbody>
        <?php foreach ($rows as $d): ?>
          <tr>
            <td>
              <a class="link" href="/user/?a=user&id=<?= (int) $d['user_id'] ?>"><?= admin_esc((string) $d['nickname']) ?></a>
              <div class="muted small"><?= admin_esc((string) $d['email']) ?></div>
            </td>
            <td class="content-cell"><?= admin_esc((string) $d['content']) ?></td>
            <td class="mono small"><?= (int) $d['bangumi_id'] ?> / 第 <?= (int) $d['episode'] ?> 集</td>
            <td class="mono small"><?= date('Y-m-d H:i', (int) $d['created_at']) ?></td>
            <td>
              <form method="post" action="/user/?a=delete-danmaku">
                <?= csrf_field() ?>
                <input type="hidden" name="danmaku_id" value="<?= (int) $d['id'] ?>">
                <input type="hidden" name="back" value="/user/?a=danmaku">
                <button class="link-btn" type="submit">删除</button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
        <?php if (!$rows): ?>
          <tr><td colspan="5" class="muted center">没有弹幕</td></tr>
        <?php endif; ?>
        </tbody>
      </table>
    </div>
    <?php
    render_page('弹幕', (string) ob_get_clean(), 'danmaku');
}

/// 历史记录详情页（从用户详情里跳进来的独立视图，便于单独分享链接）。
function render_history(int $id): void
{
    $user = admin_find_user($id);
    if (!$user) {
        render_page('观看记录', '<p class="muted">用户不存在。</p>', 'users');
        return;
    }
    $kind = find_history_snapshot_kind($id);
    $rows = $kind !== null ? parse_history_rows(sync_payload_json($id, $kind) ?? []) : [];

    ob_start();
    ?>
    <p><a class="link" href="/user/?a=user&id=<?= (int) $id ?>">← 返回用户详情</a></p>
    <section class="card">
      <h2><?= admin_esc((string) $user['nickname']) ?> 的观看记录</h2>
      <?php if (!$rows): ?>
        <p class="muted">没有可展示的观看记录。</p>
      <?php else: ?>
        <div class="table-wrap">
          <table>
            <thead><tr><th>番剧</th><th>看到</th><th>已看集数</th><th>最后观看</th></tr></thead>
            <tbody>
            <?php foreach ($rows as $row): ?>
              <tr>
                <td><?= admin_esc($row['title']) ?></td>
                <td class="mono"><?= $row['lastEpisode'] > 0 ? '第 ' . $row['lastEpisode'] . ' 集' : '—' ?></td>
                <td class="mono"><?= (int) $row['episodeCount'] ?></td>
                <td class="mono"><?= $row['lastWatchTime'] > 0 ? date('Y-m-d H:i', (int) ($row['lastWatchTime'] / 1000)) : '—' ?></td>
              </tr>
            <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </section>
    <?php
    render_page('观看记录', (string) ob_get_clean(), 'users');
}

function admin_css(): string
{
    return <<<'CSS'
:root{
  --bg:#121016; --panel:#1b1820; --line:#2c2833; --text:#e8e4ee;
  --muted:#9b93a8; --accent:#b18cff; --ok:#5fd18c; --danger:#ff6b81;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);
  font:15px/1.6 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}
.topbar{display:flex;align-items:center;justify-content:space-between;
  padding:14px 24px;background:var(--panel);border-bottom:1px solid var(--line);
  position:sticky;top:0;z-index:10;flex-wrap:wrap;gap:12px}
.brand{font-weight:700;letter-spacing:1px}
.brand span{color:var(--muted);font-weight:400;font-size:13px;margin-left:6px}
.topbar nav{display:flex;gap:18px;align-items:center;flex-wrap:wrap}
.topbar nav a{color:var(--muted);padding:4px 0;border-bottom:2px solid transparent}
.topbar nav a.active{color:var(--text);border-bottom-color:var(--accent)}
.topbar nav a.logout{color:var(--danger)}
main{max-width:1180px;margin:0 auto;padding:24px 20px 80px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:12px;
  padding:20px;margin-bottom:18px}
.card h2{margin:0 0 14px;font-size:17px}
.muted{color:var(--muted)}
.small{font-size:12px}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px}
.center{text-align:center}
.kv{display:grid;gap:8px}
.kv>div{display:flex;gap:10px;align-items:baseline;flex-wrap:wrap}
.kv>div>span.muted{min-width:72px}
.table-wrap{overflow-x:auto;border:1px solid var(--line);border-radius:10px}
table{width:100%;border-collapse:collapse;font-size:14px}
th,td{padding:10px 12px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}
th{background:#221e29;color:var(--muted);font-weight:600;white-space:nowrap}
tr:last-child td{border-bottom:none}
.content-cell{max-width:420px;word-break:break-word;white-space:pre-wrap}
.title-cell{display:flex;gap:10px;align-items:center}
.title-cell img{width:34px;height:46px;object-fit:cover;border-radius:5px;flex:none}
.tag{display:inline-block;padding:1px 8px;border-radius:999px;font-size:12px;
  border:1px solid currentColor}
.tag.ok{color:var(--ok)}
.tag.danger{color:var(--danger)}
.tag.muted{color:var(--muted)}
.alert{padding:10px 14px;border-radius:9px;margin-bottom:16px;font-size:14px}
.alert.ok{background:#173626;color:#a6f0c4;border:1px solid #2f6b47}
.alert.error{background:#3a1a21;color:#ffb3bf;border:1px solid #6d2b38}
.toolbar{display:flex;justify-content:space-between;align-items:center;
  margin-bottom:12px;gap:12px;flex-wrap:wrap}
.search{display:flex;gap:8px;margin-bottom:16px;flex-wrap:wrap}
input[type=search],input[type=text],input[type=password],select{
  background:#151219;border:1px solid var(--line);color:var(--text);
  border-radius:8px;padding:8px 11px;font:inherit;min-width:0}
input:focus,select:focus{outline:2px solid var(--accent);outline-offset:-1px}
button{background:#2a2533;color:var(--text);border:1px solid var(--line);
  border-radius:8px;padding:8px 16px;font:inherit;cursor:pointer}
button:hover{background:#342e40}
button.primary{background:var(--accent);color:#17131f;border-color:transparent;font-weight:600}
button.danger{color:var(--danger);border-color:#6d2b38}
button.link-btn{background:none;border:none;padding:0;color:var(--accent);
  font-size:13px;cursor:pointer}
button.link-btn:hover{text-decoration:underline}
.actions{margin-top:16px;display:flex;gap:12px;flex-wrap:wrap}
.ban-form{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.login-body{display:flex;align-items:center;justify-content:center;min-height:100vh;padding:20px}
.login-card{background:var(--panel);border:1px solid var(--line);border-radius:16px;
  padding:32px;width:100%;max-width:360px;display:grid;gap:14px}
.login-card h1{margin:0;font-size:24px;letter-spacing:2px}
.login-card p{margin:0 0 6px}
.login-card label{display:grid;gap:6px;font-size:14px;color:var(--muted)}
.login-card button{margin-top:6px;background:var(--accent);color:#17131f;
  border-color:transparent;font-weight:600;padding:10px}
@media (max-width:640px){
  .topbar{padding:12px 16px}
  main{padding:16px 12px 60px}
  .card{padding:14px}
  th,td{padding:8px 9px}
  .content-cell{max-width:220px}
}
CSS;
}
