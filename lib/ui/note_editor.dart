import 'package:flutter/material.dart';

import 'markdown_view.dart';

/// 通用的杂记编辑器：左边写 markdown，右边实时预览。返回 null 表示取消。
Future<String?> showNoteEditor(
  BuildContext context, {
  required String title,
  String initialText = '',
  String hint = '想到什么写什么，支持 Markdown',
  bool allowEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NoteEditorDialog(
      title: title,
      initialText: initialText,
      hint: hint,
      allowEmpty: allowEmpty,
    ),
  );
}

class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({
    required this.title,
    required this.initialText,
    required this.hint,
    required this.allowEmpty,
  });

  final String title;
  final String initialText;
  final String hint;
  final bool allowEmpty;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  bool _preview = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final editor = TextField(
      controller: _controller,
      maxLines: null,
      expands: true,
      autofocus: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(height: 1.6),
      decoration: InputDecoration(
        hintText: widget.hint,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(12),
      ),
    );

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          IconButton(
            tooltip: _preview ? '只看编辑' : '打开预览',
            onPressed: () => setState(() => _preview = !_preview),
            icon: Icon(_preview ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          ),
        ],
      ),
      content: SizedBox(
        width: size.width * 0.7,
        height: size.height * 0.6,
        child: _preview
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: editor),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) => value.text.trim().isEmpty
                            ? Text('预览区', style: TextStyle(color: scheme.outline))
                            : MarkdownView(data: value.text),
                      ),
                    ),
                  ),
                ],
              )
            : editor,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
