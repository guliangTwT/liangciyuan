<?php
declare(strict_types=1);

/**
 * 读取用户同步的观看记录与收藏。
 *
 * 客户端同步的数据分两类，格式完全不同：
 *
 * 1. 观看记录：`p_<base64(路径)>` 形式的 blob，内容是可读 JSON
 *    （history/snapshot.json），能解析出番剧名与进度。
 * 2. 收藏：`collectibles` / `collectchanges`，是 Hive 的二进制文件，
 *    PHP 无法解析出具体番剧——只能报告"是否同步过"和体积。
 *
 * 这里如实区分这两种情况，不假装能读出收藏内容。
 */

/// 把 sync_blobs.kind 还原成客户端里的路径。
function sync_kind_to_path(string $kind): ?string
{
    if (strncmp($kind, 'p_', 2) !== 0) {
        return null;
    }
    $b64 = substr($kind, 2);
    $pad = strlen($b64) % 4;
    if ($pad !== 0) {
        $b64 .= str_repeat('=', 4 - $pad);
    }
    $decoded = base64_decode(strtr($b64, '-_', '+/'), true);
    return $decoded === false ? null : $decoded;
}

/// 该用户的全部同步块（kind、体积、更新时间）。
function sync_blocks(int $userId): array
{
    $stmt = admin_db()->prepare(
        'SELECT kind, length(payload) AS size, updated_at
         FROM sync_blobs WHERE user_id = ? ORDER BY updated_at DESC'
    );
    $stmt->execute([$userId]);
    return $stmt->fetchAll();
}

/// 读出某个 kind 的原始 JSON（payload 是 base64）。
function sync_payload_json(int $userId, string $kind): ?array
{
    $stmt = admin_db()->prepare(
        'SELECT payload FROM sync_blobs WHERE user_id = ? AND kind = ?'
    );
    $stmt->execute([$userId, $kind]);
    $row = $stmt->fetch();
    if (!$row) {
        return null;
    }
    $raw = base64_decode((string) $row['payload'], true);
    if ($raw === false) {
        return null;
    }
    $json = json_decode($raw, true);
    return is_array($json) ? $json : null;
}

/// 找出观看记录快照所在的 kind。
function find_history_snapshot_kind(int $userId): ?string
{
    foreach (sync_blocks($userId) as $block) {
        $path = sync_kind_to_path((string) $block['kind']);
        if ($path !== null && str_contains($path, 'history') && str_ends_with($path, 'snapshot.json')) {
            return (string) $block['kind'];
        }
    }
    return null;
}

/// 把历史记录里的 histories 整理成表格行。
function parse_history_rows(array $snapshot): array
{
    $histories = $snapshot['histories'] ?? [];
    if (!is_array($histories)) {
        return [];
    }
    $rows = [];
    foreach ($histories as $history) {
        if (!is_array($history)) {
            continue;
        }
        $item = $history['bangumiItem'] ?? [];
        if (!is_array($item)) {
            $item = [];
        }
        $nameCn = trim((string) ($item['nameCn'] ?? ''));
        $name = trim((string) ($item['name'] ?? ''));
        $title = $nameCn !== '' ? $nameCn : $name;
        if ($title === '') {
            $title = '（未知条目）';
        }

        // 进度条数 = 看过的集数；取最近一次观看时间用于排序。
        $progresses = $history['progresses'] ?? [];
        $episodeCount = is_array($progresses) ? count($progresses) : 0;
        $lastWatch = (int) ($history['lastWatchTime'] ?? 0);

        $rows[] = [
            'title' => $title,
            'titleOriginal' => $name !== $title ? $name : '',
            'bangumiId' => (int) ($item['id'] ?? 0),
            'cover' => extract_cover($item['images'] ?? ''),
            'lastEpisode' => (int) ($history['lastWatchEpisode'] ?? 0),
            'episodeCount' => $episodeCount,
            'lastWatchTime' => $lastWatch,
            'adapter' => (string) ($history['adapterName'] ?? ''),
        ];
    }
    usort($rows, static fn(array $a, array $b): int => $b['lastWatchTime'] <=> $a['lastWatchTime']);
    return $rows;
}

/// images 字段在不同版本里是字符串或数组，统一取出一个封面地址。
function extract_cover(mixed $images): string
{
    if (is_string($images) && $images !== '') {
        $decoded = json_decode($images, true);
        if (is_array($decoded)) {
            return (string) ($decoded['large'] ?? $decoded['common'] ?? $decoded['medium'] ?? '');
        }
        return $images;
    }
    if (is_array($images)) {
        return (string) ($images['large'] ?? $images['common'] ?? $images['medium'] ?? '');
    }
    return '';
}

/// 收藏：只能报告同步状态，无法解析出条目（Hive 二进制）。
function collectible_summary(int $userId): array
{
    $result = ['collectibles' => null, 'collectchanges' => null];
    foreach (sync_blocks($userId) as $block) {
        $kind = (string) $block['kind'];
        if ($kind === 'collectibles' || $kind === 'collectchanges') {
            $result[$kind] = [
                'size' => (int) $block['size'],
                'updatedAt' => (int) $block['updated_at'],
            ];
        }
    }
    return $result;
}
