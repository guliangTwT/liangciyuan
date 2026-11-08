import 'package:flutter/material.dart';

import 'package:kazumi/bean/dialog/dialog_helper.dart';

/// 评论/评论草稿：内容 + 是否剧透。
class CommentDraft {
  const CommentDraft({required this.content, required this.spoiler});

  final String content;
  final bool spoiler;
}

Future<CommentDraft?> showCommentComposerSheet(
  BuildContext context, {
  required String title,
  required String hintText,
  int maxLength = 500,
}) {
  return showModalBottomSheet<CommentDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: CommentComposer(
        title: title,
        hintText: hintText,
        maxLength: maxLength,
      ),
    ),
  );
}

class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.title,
    required this.hintText,
    this.maxLength = 500,
  });

  final String title;
  final String hintText;
  final int maxLength;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final _controller = TextEditingController();
  bool _spoiler = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      KazumiDialog.showToast(message: '先写点什么再发布吧');
      return;
    }
    Navigator.of(context).pop(
      CommentDraft(content: content, spoiler: _spoiler),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: widget.maxLength,
            decoration: InputDecoration(
              hintText: widget.hintText,
              border: const OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _spoiler,
            onChanged: (value) => setState(() => _spoiler = value),
            title: const Text('含剧透（默认折叠内容）'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('发布'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}