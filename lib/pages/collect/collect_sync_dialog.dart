import 'package:flutter/material.dart';

import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/services/sync/account_sync_service.dart';

enum CollectSyncDestination { accountSettings }

/// 追番页「同步」按钮覆盖的内容。
///
/// 说明：早期这里只有「云端收藏」一步，用户想同步观看记录还得去设置页。
/// 现在三项内容都在这里完成，与账号页的「立即同步全部数据」一致。
enum CollectSyncStep {
  shield(
    SyncContent.shield,
    '同步关键词与正则规则',
    Icons.shield_rounded,
  ),
  history(
    SyncContent.history,
    '同步看到第几集与播放进度',
    Icons.history_rounded,
  ),
  collect(
    SyncContent.collect,
    '合并本地与账号云端收藏',
    Icons.cloud_sync_rounded,
  );

  const CollectSyncStep(this.content, this._description, this._icon);

  /// 步骤对应的同步内容。步骤名一律取 [SyncContent.label]，
  /// 与 [AccountSyncService] 返回的结果保持同一来源，避免两边字符串写歪
  /// （曾因「云端收藏」对「收藏」不相等，把成功的步骤显示成未完成）。
  final SyncContent content;
  final String _description;
  final IconData _icon;

  String get title => content.label;
}

enum _StepStatus { waiting, running, succeeded, failed, skipped }

enum _SyncPhase { ready, running, finished }

class _StepState {
  _StepState(this.step);

  final CollectSyncStep step;
  _StepStatus status = _StepStatus.waiting;
  String? message;
  double? progress;
}

/// 显示同步计划，并逐步执行。
class CollectSyncDialog extends StatefulWidget {
  const CollectSyncDialog({
    super.key,
    required this.steps,
    required this.canSync,
    required this.onSync,
    this.blockedReason,
    this.reloadCollectibles,
  });

  /// 本次要同步的步骤（由调用方按设置决定）。
  final List<CollectSyncStep> steps;
  final bool canSync;

  /// 未满足条件时的说明（例如「未登录」）。
  final String? blockedReason;

  /// 执行同步；返回本次结果。
  final Future<FullSyncResult> Function()? onSync;

  /// 收藏同步完成后刷新列表。
  final void Function()? reloadCollectibles;

  @override
  State<CollectSyncDialog> createState() => _CollectSyncDialogState();
}

class _CollectSyncDialogState extends State<CollectSyncDialog> {
  late List<_StepState> _steps = _createSteps();
  _SyncPhase _phase = _SyncPhase.ready;
  FullSyncResult? _result;

  bool get _running => _phase == _SyncPhase.running;
  bool get _finished => _phase == _SyncPhase.finished;

  List<_StepState> _createSteps() => [
    for (final step in widget.steps) _StepState(step),
  ];

  // Removed routes can stay mounted until their exit animation ends.
  bool get _active => mounted && (ModalRoute.of(context)?.isActive ?? false);
  bool get _hasFailure =>
      _steps.any((step) => step.status == _StepStatus.failed) ||
      (_result?.hasFailure ?? false);
  bool get _hasSuccess => _steps.any((step) => step.status == _StepStatus.succeeded);

  Future<void> _start() async {
    if (_running || !widget.canSync) return;
    setState(() {
      _steps = _createSteps();
      _result = null;
      _phase = _SyncPhase.running;
    });
    // 先把所有步骤标成进行中，真正的工作由 AccountSyncService 顺序执行。
    setState(() {
      for (final state in _steps) {
        state.status = _StepStatus.running;
      }
    });
    // 让出一帧，保证进度状态在开始网络请求前先渲染出来。
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!_active) return;

    FullSyncResult result;
    try {
      result = await (widget.onSync?.call() ??
          Future.value(const FullSyncResult(succeeded: [], failures: [])));
    } catch (e) {
      result = FullSyncResult(
        succeeded: const [],
        failures: ['连接中断，请检查网络或设置：$e'],
      );
    }
    if (!_active) return;
    widget.reloadCollectibles?.call();

    // 按实际结果回填每一步的状态。
    setState(() {
      for (final state in _steps) {
        final name = state.step.title;
        final succeeded = result.succeeded.contains(name);
        state.status = succeeded
            ? _StepStatus.succeeded
            : _StepStatus.failed;
        if (!succeeded) {
          state.message = result.failures
              .where((failure) => failure.startsWith('$name：'))
              .map((failure) => failure.substring(name.length + 1))
              .firstOrNull;
        } else {
          state.message = null;
        }
      }
      _result = result;
      _phase = _SyncPhase.finished;
    });
  }

  String get _title {
    if (!widget.canSync) return '开启云同步';
    if (_running) return '正在同步';
    if (!_finished) return '同步到账号';
    if (!_hasFailure) return '同步已完成';
    if (_hasSuccess) return '部分同步完成';
    return '同步未完成';
  }

  String? get _description {
    if (!widget.canSync) return widget.blockedReason ?? '登录账号并开启同步后可用';
    if (_running) return '请保持应用开启';
    if (!_finished) return '收藏、观看记录与弹幕屏蔽词';
    return _result?.message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final failed = _finished && _hasFailure;
    final description = _description;
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 440),
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: colors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        scrollable: true,
        iconPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        icon: Center(
          child: AnimatedSwitcher(
            duration: duration,
            child: _running
                ? LoadingIndicator(
                    key: const ValueKey('syncing'),
                    size: 64,
                    color: colors.primary,
                    semanticsLabel: '正在同步',
                  )
                : StateIconBadge(
                    key: ValueKey((_finished, failed)),
                    icon: failed
                        ? Icons.sync_problem_rounded
                        : _finished
                        ? Icons.done_all_rounded
                        : Icons.sync_rounded,
                    size: 64,
                    iconSize: 32,
                    backgroundColor: failed
                        ? colors.errorContainer
                        : colors.primaryContainer,
                    foregroundColor: failed
                        ? colors.onErrorContainer
                        : colors.onPrimaryContainer,
                  ),
          ),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        title: Semantics(
          liveRegion: true,
          child: Text(_title, textAlign: TextAlign.center),
        ),
        titleTextStyle: theme.textTheme.headlineSmall?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        content: SizedBox(
          width: 392,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (description != null) ...[
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: failed ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (!widget.canSync)
                _setupRow(CollectSyncDestination.accountSettings)
              else
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  _stepRow(_steps[i], i),
                ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actionsOverflowButtonSpacing: 8,
        actions: _running
            ? null
            : [
                if (!_finished || failed)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      widget.canSync && !_finished ? '取消' : '关闭',
                    ),
                  ),
                if (widget.canSync)
                  StateActionButton(
                    onPressed: _finished && !failed
                        ? () => Navigator.of(context).pop()
                        : _start,
                    icon: _finished
                        ? (failed ? Icons.refresh_rounded : Icons.check_rounded)
                        : Icons.sync_rounded,
                    text: _finished ? (failed ? '重新同步' : '完成') : '开始同步',
                  ),
              ],
      ),
    );
  }

  BorderRadius _rowRadius(int index, int length) => BorderRadius.vertical(
    top: Radius.circular(index == 0 ? 20 : 4),
    bottom: Radius.circular(index == length - 1 ? 20 : 4),
  );

  Widget _setupRow(CollectSyncDestination destination) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (title, description, icon) = switch (destination) {
      CollectSyncDestination.accountSettings => (
        '凉次元账号',
        '登录账号，开启云同步',
        Icons.cloud_sync_rounded,
      ),
    };
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: colors.primary),
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).pop(destination),
      ),
    );
  }

  Widget _stepRow(_StepState state, int index) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = state.status == _StepStatus.running;
    final failed = state.status == _StepStatus.failed;
    final skipped = state.status == _StepStatus.skipped;
    final detail = state.status == _StepStatus.waiting
        ? (_running ? null : state.step._description)
        : state.message;
    final foreground = failed
        ? colors.onErrorContainer
        : active
        ? colors.onSecondaryContainer
        : colors.onSurface;
    final statusLabel = switch (state.status) {
      _StepStatus.waiting => _running ? '等待中' : null,
      _StepStatus.running => '同步中',
      _StepStatus.succeeded => '已完成',
      _StepStatus.failed => '未完成',
      _StepStatus.skipped => '未完成',
    };
    final icon = switch (state.status) {
      _StepStatus.succeeded => Icons.check_circle_rounded,
      _StepStatus.failed || _StepStatus.skipped => Icons.error_outline_rounded,
      _ => state.step._icon,
    };
    return Semantics(
      container: true,
      child: Material(
        color: failed || skipped
            ? colors.errorContainer
            : active
            ? colors.secondaryContainer
            : colors.surfaceContainerLow,
        borderRadius: _rowRadius(index, _steps.length),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  icon,
                  size: 24,
                  color: failed || skipped ? colors.onErrorContainer : foreground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          state.step.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: failed || skipped
                                ? colors.onErrorContainer
                                : foreground,
                          ),
                        ),
                        if (statusLabel != null)
                          Text(
                            statusLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: active || failed || skipped
                                  ? (failed || skipped
                                      ? colors.onErrorContainer
                                      : foreground)
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: active || failed || skipped
                              ? (failed || skipped
                                  ? colors.onErrorContainer
                                  : foreground)
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if ((failed || skipped) && _finished) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: colors.onErrorContainer,
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => Navigator.of(context).pop(
                          CollectSyncDestination.accountSettings,
                        ),
                        icon: const Icon(Icons.settings_rounded, size: 18),
                        label: const Text('检查设置'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
