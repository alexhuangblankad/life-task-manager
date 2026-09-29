import 'package:flutter/material.dart';

import '../app_state.dart';
import 'ai_score_card.dart';
import '../core/countdown.dart';
import 'home_page.dart';
import 'profile_dialog.dart';
import 'theme.dart';

class CountdownPage extends StatelessWidget {
  const CountdownPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: '人生倒计时',
      subtitle: '大任务都在往截止日跑，你也是',
      actions: [
        OutlinedButton.icon(
          onPressed: () => showProfileEditor(context, state),
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('设置期限'),
        ),
      ],
      child: ListView(
        padding: Gaps.page,
        children: [
          _LifeCard(state: state),
          const SizedBox(height: Gaps.l),
          AiScoreCard(state: state),
          const SizedBox(height: Gaps.l),
          _TaskDeadlineSection(state: state),
        ],
      ),
    );
  }
}

class _LifeCard extends StatelessWidget {
  const _LifeCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final profile = state.profile;
    final target = profile.lifeTarget;

    if (!profile.configured) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('还没设置人生期限', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('填了出生日期和预期寿命，这里就会开始倒计时。先想清楚再开——数字会一直跳。'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => showProfileEditor(context, state),
                icon: const Icon(Icons.add),
                label: const Text('去设置'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<DateTime>(
          valueListenable: state.tick,
          builder: (context, now, _) {
            final c = computeCountdown(now, target!, start: profile.lifeStart);
            final scheme = Theme.of(context).colorScheme;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('人生还剩', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (!profile.lifeCountdownEnabled)
                      Chip(
                        label: const Text('已在设置里关闭（仅展示）'),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                  ],
                ),
                const SizedBox(height: Gaps.m),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    _BigNumber(value: c.years.toString(), unit: '年'),
                    _BigNumber(value: c.days.toString(), unit: '天'),
                    if (profile.showSeconds) ...[
                      Text(
                        '${c.hours.toString().padLeft(2, '0')}:${c.minutes.toString().padLeft(2, '0')}:${c.seconds.toString().padLeft(2, '0')}',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: scheme.primary,
                            ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Gaps.l),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: c.percentElapsed,
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: Gaps.s),
                Text(
                  '总计 ${c.totalDays} 天 · 已经走完 ${(c.percentElapsed * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    _MiniStat(label: '今年还剩', value: '${_daysLeftInYear(now)} 天'),
                    _MiniStat(label: '本月还剩', value: '${_daysLeftInMonth(now)} 天'),
                    _MiniStat(label: '本周还剩', value: '${7 - (now.weekday - 1)} 天'),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static int _daysLeftInYear(DateTime now) {
    final end = DateTime(now.year, 12, 31);
    return calendarDaysBetween(now, end);
  }

  static int _daysLeftInMonth(DateTime now) {
    final end = DateTime(now.year, now.month + 1, 0);
    return calendarDaysBetween(now, end);
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber({required this.value, required this.unit});
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.displaySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: style),
        const SizedBox(width: 2),
        Text(unit, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 10),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// 所有未完成小任务的截止日倒计时（按紧急度排序）
class _TaskDeadlineSection extends StatelessWidget {
  const _TaskDeadlineSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final items = state.allSubtasksWithDue;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('任务倒计时', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              items.isEmpty ? '还没有带截止日期的小任务' : '共 ${items.length} 个待办有截止日期，最近的排在最前',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Gaps.m),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('到「待办」里给小事加上 📅 截止日期，这里就会盯着它'),
              )
            else
              ValueListenableBuilder<DateTime>(
                valueListenable: state.tick,
                builder: (context, now, _) {
                  return Column(
                    children: [
                      for (final item in items.take(12))
                        _DeadlineRow(
                          title: item.subtask.title,
                          taskTitle: item.task.task.title,
                          due: item.subtask.due!,
                          now: now,
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.title, required this.taskTitle, required this.due, required this.now});

  final String title;
  final String taskTitle;
  final DateTime due;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = calendarDaysBetween(now, due);
    final overdue = left < 0;
    final urgent = left >= 0 && left <= 3;
    final color = overdue ? scheme.error : (urgent ? Colors.orange : scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(overdue ? Icons.warning_amber_rounded : Icons.schedule, size: 16, color: color),
          const SizedBox(width: Gaps.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  taskTitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            overdue ? '逾期 ${-left} 天' : (left == 0 ? '今天到期' : '还剩 $left 天'),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
