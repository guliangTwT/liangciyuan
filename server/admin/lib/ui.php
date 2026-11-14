<?php
declare(strict_types=1);

/**
 * 后台的通用渲染组件。
 *
 * 全部返回 HTML 字符串，页面里直接 echo。所有用户可控内容都必须经过
 * admin_esc()，这里不做二次转义，避免出现双重编码。
 */

function ui_icon(string $name, int $size = 20): string
{
    // 内联 SVG，避免额外请求与图标字体依赖。
    $paths = [
        'dashboard' => '<rect x="3" y="3" width="7" height="9" rx="2"/><rect x="14" y="3" width="7" height="5" rx="2"/><rect x="14" y="12" width="7" height="9" rx="2"/><rect x="3" y="16" width="7" height="5" rx="2"/>',
        'users' => '<circle cx="9" cy="8" r="3.2"/><path d="M3.5 20c0-3.2 2.6-5.2 5.5-5.2s5.5 2 5.5 5.2"/><path d="M16 11.2a2.8 2.8 0 1 0 0-5.6"/><path d="M17.5 20c0-2.4-1-4-2.6-4.8"/>',
        'comments' => '<path d="M4 5.5h16v10.2H9.4L5.6 19v-3.3H4z"/><path d="M8 9h8"/><path d="M8 12.4h5"/>',
        'danmaku' => '<path d="M3 6.5h18v7.2H3z"/><path d="M7 17.6h3.5"/><path d="M13.5 17.6H17"/>',
        'shield' => '<path d="M12 3.4 19 6v5.5c0 4.2-2.9 7.6-7 9.1-4.1-1.5-7-4.9-7-9.1V6z"/><path d="M9.2 12.1l2 2 3.6-3.8"/>',
        'log' => '<path d="M6 3.5h9l4 4V20.5H6z"/><path d="M14.6 3.6V8h4.2"/><path d="M9 12.5h6"/><path d="M9 16h4"/>',
        'search' => '<circle cx="10.8" cy="10.8" r="6.2"/><path d="M15.4 15.4 20 20"/>',
        'clock' => '<circle cx="12" cy="12" r="8.4"/><path d="M12 7.4V12l3.2 2"/>',
        'arrow-left' => '<path d="M14.5 5.5 8 12l6.5 6.5"/>',
        'arrow-right' => '<path d="M9.5 5.5 16 12l-6.5 6.5"/>',
        'check' => '<path d="M5 12.8 9.6 17.4 19 8"/>',
        'x' => '<path d="M6 6l12 12"/><path d="M18 6 6 18"/>',
        'trash' => '<path d="M4.5 7h15"/><path d="M9.5 7V4.6h5V7"/><path d="M6.6 7l.9 12.4h9l.9-12.4"/>',
        'restore' => '<path d="M4.6 10.2A8 8 0 1 1 6 16.4"/><path d="M4.4 4.6v5.8h5.8"/>',
        'external' => '<path d="M13.5 4.5H20v6.5"/><path d="M20 4.5 11 13.5"/><path d="M18 14.5v4.9H4.6V6h4.9"/>',
        'refresh' => '<path d="M20 12a8 8 0 1 1-2.4-5.7"/><path d="M20 4.4v5.2h-5.2"/>',
        'logout' => '<path d="M9.5 4.5H5v15h4.5"/><path d="M13 12h7"/><path d="M17.2 8.2 21 12l-3.8 3.8"/>',
        'menu' => '<path d="M4 7h16"/><path d="M4 12h16"/><path d="M4 17h16"/>',
    ];
    $path = $paths[$name] ?? $paths['dashboard'];
    return '<svg class="ic" width="' . $size . '" height="' . $size . '" viewBox="0 0 24 24" fill="none"'
        . ' stroke="currentColor" stroke-width="1.7" stroke-linecap="round"'
        . ' stroke-linejoin="round" aria-hidden="true">' . $path . '</svg>';
}

function ui_badge(string $label, string $kind = 'muted'): string
{
    return '<span class="badge ' . admin_esc($kind) . '">' . admin_esc($label) . '</span>';
}

function ui_empty(string $title, string $hint = '', string $icon = 'search'): string
{
    return '<div class="empty">' . ui_icon($icon, 28)
        . '<div class="empty-title">' . admin_esc($title) . '</div>'
        . ($hint === '' ? '' : '<div class="empty-hint">' . admin_esc($hint) . '</div>')
        . '</div>';
}

function ui_time(int $timestamp): string
{
    if ($timestamp <= 0) {
        return '—';
    }
    return date('Y-m-d H:i', $timestamp);
}

/// 相对时间，列表里比绝对时间更容易扫。
function ui_ago(int $timestamp): string
{
    if ($timestamp <= 0) {
        return '—';
    }
    $diff = admin_now() - $timestamp;
    if ($diff < 60) {
        return '刚刚';
    }
    if ($diff < 3600) {
        return intdiv($diff, 60) . ' 分钟前';
    }
    if ($diff < 86400) {
        return intdiv($diff, 3600) . ' 小时前';
    }
    if ($diff < 86400 * 30) {
        return intdiv($diff, 86400) . ' 天前';
    }
    return date('Y-m-d', $timestamp);
}

/// 分页条。$base 是已带查询参数的 URL，页码用 &p= 拼接。
function ui_pager(array $page, string $base): string
{
    if ($page['pages'] <= 1) {
        return '';
    }
    $sep = str_contains($base, '?') ? '&' : '?';
    $link = static fn(int $p): string => $base . $sep . 'p=' . $p;
    $current = $page['page'];
    $pages = $page['pages'];

    // 始终显示首末页与当前页附近两页，中间用省略号。
    $shown = [1, $pages];
    for ($i = $current - 2; $i <= $current + 2; $i++) {
        if ($i >= 1 && $i <= $pages) {
            $shown[] = $i;
        }
    }
    $shown = array_values(array_unique($shown));
    sort($shown);

    $html = '<nav class="pager" aria-label="分页">';
    $html .= $current > 1
        ? '<a class="pg" href="' . admin_esc($link($current - 1)) . '" rel="prev">' . ui_icon('arrow-left', 16) . '</a>'
        : '<span class="pg disabled">' . ui_icon('arrow-left', 16) . '</span>';

    $previous = 0;
    foreach ($shown as $number) {
        if ($previous !== 0 && $number - $previous > 1) {
            $html .= '<span class="pg gap">…</span>';
        }
        $html .= $number === $current
            ? '<span class="pg current" aria-current="page">' . $number . '</span>'
            : '<a class="pg" href="' . admin_esc($link($number)) . '">' . $number . '</a>';
        $previous = $number;
    }

    $html .= $current < $pages
        ? '<a class="pg" href="' . admin_esc($link($current + 1)) . '" rel="next">' . ui_icon('arrow-right', 16) . '</a>'
        : '<span class="pg disabled">' . ui_icon('arrow-right', 16) . '</span>';
    $html .= '</nav>';
    return $html;
}

function ui_pager_summary(array $page, string $unit = '条'): string
{
    if ($page['total'] === 0) {
        return '共 0 ' . $unit;
    }
    return '第 ' . $page['from'] . '–' . $page['to'] . ' ' . $unit . ' · 共 ' . $page['total'] . ' ' . $unit;
}

/// 拼一个带全部当前筛选条件的链接，只覆盖指定的键。
function ui_link(array $params): string
{
    $query = http_build_query(array_filter(
        $params,
        static fn($value): bool => $value !== '' && $value !== null && $value !== 0 && $value !== '0'
    ));
    return '/user/' . ($query === '' ? '' : '?' . $query);
}

/// 顶部标题区。
function ui_page_head(string $title, string $subtitle = '', string $actions = ''): string
{
    return '<header class="page-head"><div class="page-head-text">'
        . '<h1>' . admin_esc($title) . '</h1>'
        . ($subtitle === '' ? '' : '<p>' . admin_esc($subtitle) . '</p>')
        . '</div>'
        . ($actions === '' ? '' : '<div class="page-head-actions">' . $actions . '</div>')
        . '</header>';
}

/// 数值卡片。
function ui_stat(
    string $label,
    string $value,
    string $hint = '',
    string $icon = 'users',
    string $tone = '',
    string $href = ''
): string {
    $inner = '<div class="stat-top">' . ui_icon($icon, 18)
        . '<span class="stat-label">' . admin_esc($label) . '</span></div>'
        . '<div class="stat-value">' . admin_esc($value) . '</div>'
        . ($hint === '' ? '' : '<div class="stat-hint">' . admin_esc($hint) . '</div>');
    $class = 'stat' . ($tone === '' ? '' : ' ' . $tone);
    return $href === ''
        ? '<div class="' . $class . '">' . $inner . '</div>'
        : '<a class="' . $class . '" href="' . admin_esc($href) . '">' . $inner . '</a>';
}

/// 近 7 天的柱状图。$series 形如 ['11-08' => 12, ...]，按时间顺序。
function ui_bars(array $series, string $tone = 'primary'): string
{
    if (!$series) {
        return '';
    }
    $max = max(1, max($series));
    $html = '<div class="bars ' . admin_esc($tone) . '">';
    foreach ($series as $label => $value) {
        $height = $value <= 0 ? 3 : max(4, (int) round($value / $max * 64));
        // 注意闭合标签必须是 </span>：写成 </div> 会让浏览器做错误恢复，
        // 后续兄弟节点被甩出网格，整页排版全乱。
        $html .= '<div class="bar-col" title="'
            . admin_esc((string) $label . '：' . $value) . '">'
            . '<span class="bar" style="height:' . $height . 'px"></span>'
            . '<span class="bar-label">' . admin_esc((string) $label) . '</span>'
            . '</div>';
    }
    $html .= '</div>';
    return $html;
}

/// 内容预览：超长文本截断，保留换行。
function ui_excerpt(string $text, int $maxLength = 140): string
{
    $text = trim($text);
    if (mb_strlen($text, 'UTF-8') <= $maxLength) {
        return admin_esc($text);
    }
    return admin_esc(mb_substr($text, 0, $maxLength, 'UTF-8')) . '<span class="muted">…</span>';
}
