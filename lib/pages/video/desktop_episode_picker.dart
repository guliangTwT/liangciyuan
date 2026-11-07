import 'package:flutter/material.dart';

import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/video_controller.dart';

/// 电脑端进入播放页时的选集面板。
///
/// 电脑端没有手机那样的「下方 Tab」，直接开播会导致用户看不到选集入口，
/// 想换集必须先播一集再进侧边栏。这里在开播前先让用户选好。
class DesktopEpisodePickerSheet extends StatefulWidget {
  const DesktopEpisodePickerSheet({
    super.key,
    required this.title,
    required this.roads,
    required this.initialEpisode,
    required this.initialRoad,
    this.resumeLabel,
  });

  final String title;
  final List<Road> roads;

  /// 默认选中的集数（有观看记录时即为上次看到的集）。
  final int initialEpisode;
  final int initialRoad;

  /// 「继续观看第 N 集」按钮的文案；null 表示没有观看记录。
  final String? resumeLabel;

  @override
  State<DesktopEpisodePickerSheet> createState() =>
      _DesktopEpisodePickerSheetState();
}

class _DesktopEpisodePickerSheetState extends State<DesktopEpisodePickerSheet> {
  late int _road = widget.initialRoad.clamp(0, widget.roads.length - 1);
  late int _episode = _clampEpisode(widget.initialEpisode);

  int _clampEpisode(int value) {
    final length = widget.roads[_road].data.length;
    if (length == 0) return 0;
    return value.clamp(1, length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final road = widget.roads[_road];
    final identifiers = road.identifier;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MaterialBottomSheetHeader(
          title: '选集',
          description: widget.title,
          onClose: () => Navigator.of(context).pop(),
        ),
        if (widget.roads.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < widget.roads.length; i++)
                  ChoiceChip(
                    label: Text(widget.roads[i].name),
                    selected: i == _road,
                    onSelected: (_) => setState(() {
                      _road = i;
                      _episode = _clampEpisode(_episode);
                    }),
                  ),
              ],
            ),
          ),
        Flexible(
          child: road.data.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      '这一路线没有可播放的集数',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 96,
                    mainAxisExtent: 44,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: road.data.length,
                  itemBuilder: (context, index) {
                    final episode = index + 1;
                    final selected = episode == _episode;
                    final label = index < identifiers.length &&
                            identifiers[index].trim().isNotEmpty
                        ? identifiers[index].trim()
                        : '第 $episode 集';
                    return Material(
                      color: selected
                          ? colors.primary
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => setState(() => _episode = episode),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: selected
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _episode <= 0
                        ? null
                        : () => Navigator.of(context).pop(
                              VideoEpisodeSelection(
                                episode: _episode,
                                road: _road,
                              ),
                            ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      widget.resumeLabel != null &&
                              _episode == widget.initialEpisode &&
                              _road == widget.initialRoad
                          ? widget.resumeLabel!
                          : '播放第 $_episode 集',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
