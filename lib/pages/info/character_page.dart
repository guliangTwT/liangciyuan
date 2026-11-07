import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:kazumi/bean/card/account_comment_card.dart';
import 'package:kazumi/bean/dialog/comment_composer_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/connected_tabs.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/modules/character/character_full_item.dart';
import 'package:kazumi/pages/info/character_info_view.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/account/account_service.dart';

class CharacterPage extends StatefulWidget {
  const CharacterPage({
    super.key,
    required this.characterID,
    required this.characterName,
    required this.characterRelation,
    this.actorNames = const [],
  });

  final int characterID;
  final String characterName;
  final String characterRelation;
  final List<String> actorNames;

  @override
  State<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends State<CharacterPage> {
  CharacterFullItem? _character;
  List<AccountComment> _comments = [];
  bool _loadingComments = true;
  bool _commentsError = false;

  Future<void> _loadCharacter() async {
    setState(() {
      _character = null;
    });
    try {
      final character =
          await BangumiApi.getCharacterByCharacterID(widget.characterID);
      if (!mounted) return;
      setState(() {
        _character = character;
      });
    } catch (_) {
      // id==0 的模板触发既有错误视图与重试入口，避免卡在骨架屏。
      if (!mounted) return;
      setState(() {
        _character = CharacterFullItem.fromTemplate();
      });
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _loadingComments = true;
      _commentsError = false;
    });
    try {
      // 人物吐槽也存凉次元账号服务；资料本身仍来自 Bangumi。
      final account = AccountService()..ensureLoaded();
      final page = await AccountApi.instance.listComments(
        targetType: 'character',
        targetId: widget.characterID,
        token: account.loggedIn ? account.token : null,
      );
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _loadingComments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentsError = true;
        _loadingComments = false;
      });
    }
  }

  Future<void> _composeComment() async {
    final account = AccountService()..ensureLoaded();
    if (!account.loggedIn) {
      KazumiDialog.showToast(message: '发表评论需要先登录凉次元账号');
      context.pushNamed('/settings/account');
      return;
    }
    final draft = await showCommentComposerSheet(
      context,
      title: '发表评论',
      hintText: '聊聊这个角色……',
    );
    if (draft == null || !mounted) return;
    try {
      await AccountApi.instance.createComment(
        token: account.token,
        targetType: 'character',
        targetId: widget.characterID,
        content: draft.content,
        spoiler: draft.spoiler,
      );
      if (!mounted) return;
      KazumiDialog.showToast(message: '评论已发布');
      await _loadComments();
    } catch (e) {
      if (!mounted) return;
      if (e is AccountException && e.statusCode == 401) {
        await AccountService().logout();
      }
      if (!mounted) return;
      KazumiDialog.showToast(
        message: e is AccountException ? e.message : '发布失败，请稍后重试',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCharacter();
      _loadComments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.characterName.trim();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            MaterialBottomSheetHeader(
              title: name.isEmpty ? '人物' : name,
              onClose: () => Navigator.of(context).pop(),
            ),
            const ConnectedTabs(
              padding: materialBottomSheetTabsPadding,
              labels: ['资料', '吐槽'],
            ),
            Expanded(
              child: TabBarView(
                children: [_characterInfoBody, _characterCommentsBody],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget get _characterInfoBody {
    final character = _character;
    if (character != null && character.id == 0) {
      return GeneralErrorWidget(
        title: '人物资料加载失败',
        errMsg: '请检查网络连接后重试。',
        onRetry: _loadCharacter,
      );
    }

    if (character == null) {
      return const SingleChildScrollView(
        padding: materialBottomSheetContentPadding,
        child: Skeletonizer.zone(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Bone(height: 300, width: double.infinity, uniRadius: 28),
            SizedBox(height: 24),
            Bone.multiText(lines: 5),
          ],
        )),
      );
    }
    return CharacterInfoView(
      character: character,
      characterName: widget.characterName,
      characterRelation: widget.characterRelation,
      actorNames: widget.actorNames,
    );
  }

  Widget get _characterCommentsBody {
    return CustomScrollView(
      scrollBehavior: const ScrollBehavior().copyWith(
        scrollbars: false,
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
        },
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(child: _composeEntry()),
        ),
        SliverPadding(
          padding: materialBottomSheetContentPadding,
          sliver: _commentsSliver,
        ),
      ],
    );
  }

  Widget _composeEntry() {
    final colors = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: _composeComment,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(16),
        backgroundColor: colors.surfaceContainerLow,
        foregroundColor: colors.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_rounded, size: 18),
          const SizedBox(width: 10),
          const Expanded(child: Text('写点评论……')),
          const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    );
  }

  Widget get _commentsSliver {
    if (_loadingComments) {
      return SliverList.builder(
        itemCount: 3,
        itemBuilder: (context, _) => const AccountCommentCardBone(),
      );
    }
    if (_commentsError) {
      return SliverFillRemaining(
        child: GeneralErrorWidget(
          title: '人物吐槽加载失败',
          errMsg: '请检查网络连接后重试。',
          onRetry: _loadComments,
        ),
      );
    }
    if (_comments.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: GeneralEmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: '还没有评论',
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // Keep loaded images alive to prevent scroll jumps.
          return KeepAlive(
            keepAlive: true,
            child: IndexedSemantics(
              index: index,
              child: AccountCommentCard(
                _comments[index],
                onAvatarTap: (userId) =>
                    context.pushNamed('/settings/profile/$userId'),
              ),
            ),
          );
        },
        childCount: _comments.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
      ),
    );
  }
}
