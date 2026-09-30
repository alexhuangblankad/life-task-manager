import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/current_vault.dart';

/// 统一的 Markdown 渲染（杂记、任务描述、月报都用它）
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data, this.shrinkWrap = true});

  final String data;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MarkdownBody(
      data: data,
      selectable: true,
      shrinkWrap: shrinkWrap,
      // 杂记里拖进来的图存成相对 vault 的路径（附件/202609/xxx.png），
      // 默认的 imageBuilder 只会当成网络图去加载，所以要自己解析成磁盘文件。
      imageBuilder: (uri, title, alt) => _Image(uri: uri, title: title, alt: alt),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: Theme.of(context).textTheme.bodyMedium,
        h1: Theme.of(context).textTheme.titleLarge,
        h2: Theme.of(context).textTheme.titleMedium,
        h3: Theme.of(context).textTheme.titleSmall,
        blockquoteDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
      ),
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({required this.uri, this.title, this.alt});

  final Uri uri;
  final String? title;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final raw = uri.toString();
    final isRemote = raw.startsWith('http://') || raw.startsWith('https://');

    if (isRemote) {
      return Image.network(
        raw,
        errorBuilder: (context, _, _) => _broken(context, raw),
      );
    }

    final path = CurrentVault.resolve(raw);
    if (path == null) return _broken(context, alt ?? raw);
    // 先确认文件在不在：不在就直接给占位，别先渲染一个会闪一下的破图
    // （也让这个行为是同步可测的，不用等异步解码失败）
    if (!File(path).existsSync()) return _broken(context, alt ?? raw);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Image.file(
        File(path),
        errorBuilder: (context, _, _) => _broken(context, alt ?? raw),
      ),
    );
  }

  /// 图找不到时别把整页搞崩，也别留一片空白 —— 给个能看出是哪张图的占位。
  Widget _broken(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '图片没找到：$label',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
