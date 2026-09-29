/// 倒计时页上的「最近一期复盘」卡片：直接显示 AI 报告的评分和评语。
///
/// 为什么放倒计时页：倒计时是「还剩多少时间」，报告是「这段时间干得怎么样」——
/// 两个放一起才有对照感（催命的不只是时间，还有上一期的分数）。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/report.dart';
import 'theme.dart';

class AiScoreCard extends StatefulWidget {
  const AiScoreCard({super.key, required this.state});

  final AppState state;

  @override
  State<AiScoreCard> createState() => _AiScoreCardState();
}

class _AiScoreCardState extends State<AiScoreCard> {
  Future<LatestReport?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<LatestReport?> _load() => widget.state.latestReport();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.l),
        child: FutureBuilder<LatestReport?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 80,
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }

            final r = snap.data;
            if (r == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('最近一期复盘', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '还没生成过报告。到「设置 → AI 周报/月报」里配好 API Key，就能按周/月自动总结并打分了。',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              );
            }

            final color = r.overall >= 70
                ? scheme.primary
                : (r.overall >= 45 ? scheme.tertiary : scheme.error);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('最近一期复盘', style: theme.textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(r.suffix, style: theme.textTheme.bodySmall),
                    ),
                    const Spacer(),
                    Text(r.period, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${r.overall}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('分 · ${r.verdict}', style: theme.textTheme.bodyMedium),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('客观 ${r.objective}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        Text(
                          r.ai == null ? 'AI 未评' : 'AI ${r.ai}',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
                if (r.comment != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    r.comment!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _openFull(context, r),
                    icon: const Icon(Icons.article_outlined, size: 16),
                    label: const Text('看全文'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openFull(BuildContext context, LatestReport r) async {
    final text = await widget.state.readReport(r.fileName);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r.period} · ${r.suffix}'),
        content: SizedBox(
          width: dialogWidth(context, 680),
          height: 520,
          child: SingleChildScrollView(child: SelectableText(text ?? '读不到这个文件')),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }
}
