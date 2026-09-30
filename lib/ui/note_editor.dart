import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import 'markdown_view.dart';

/// 通用的杂记编辑器：左边写 markdown，右边实时预览。返回 null 表示取消。
///
/// 桌面端（Windows/macOS/Linux）支持**把图片拖进来**：图片会被复制进 vault 的
/// `附件/` 目录，正文里插一行 `![](附件/202609/xxx.png)`，插入位置跟着光标走。
/// [onInsertImage] 由调用方提供（它才知道 vault 在哪），返回 vault 相对路径。
Future<String?> showNoteEditor(
  BuildContext context, {
  required String title,
  String initialText = '',
  String hint = '想到什么写什么，支持 Markdown',
  bool allowEmpty = false,
  Future<String?> Function(String fileName, List<int> bytes)? onInsertImage,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NoteEditorDialog(
      title: title,
      initialText: initialText,
      hint: hint,
      allowEmpty: allowEmpty,
      onInsertImage: onInsertImage,
    ),
  );
}

class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({
    required this.title,
    required this.initialText,
    required this.hint,
    required this.allowEmpty,
    required this.onInsertImage,
  });

  final String title;
  final String initialText;
  final String hint;
  final bool allowEmpty;
  final Future<String?> Function(String fileName, List<int> bytes)? onInsertImage;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  bool _preview = true;
  bool _dragging = false;

  /// 拖拽插图只在桌面端开：手机上没人拖文件，而且 desktop_drop 也只支持桌面。
  bool get _dropEnabled => widget.onInsertImage != null && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 在光标处插入一段文字（拖图时把 ![](路径) 插进去）
  void _insertAtCursor(String text) {
    final value = _controller.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    final next = value.text.replaceRange(start, end, text);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  Future<void> _handleDrop(DropDoneDetails detail) async {
    setState(() => _dragging = false);
    final save = widget.onInsertImage;
    if (save == null) return;

    final pieces = <String>[];
    for (final file in detail.files) {
      final path = file.path;
      if (!_looksLikeImage(path)) continue;
      try {
        final bytes = await File(path).readAsBytes();
        final rel = await save(file.name, bytes);
        if (rel != null) pieces.add('![${_altFrom(path)}]($rel)');
      } catch (_) {
        // 单张图失败不影响别的
      }
    }
    if (pieces.isEmpty) return;
    if (!mounted) return;
    final before = _controller.text;
    final prefix = (before.isEmpty || before.endsWith('\n')) ? '' : '\n';
    _insertAtCursor('$prefix${pieces.join('\n')}\n');
  }

  static bool _looksLikeImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  static String _altFrom(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
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

    Widget body = _preview
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
        : editor;

    if (_dropEnabled) {
      body = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: _handleDrop,
        child: Stack(
          children: [
            Positioned.fill(child: body),
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '松手就把图片放进杂记里',
                      style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          if (_dropEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '可拖图片进来',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
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
        child: body,
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
