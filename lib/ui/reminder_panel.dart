/// 小铃铛：把「人生倒计时 + 今天到期的待办 + 今天该做的定时任务」放一个框里，
/// 并且能立刻触发一次系统通知（不用等定时器）。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/countdown.dart';
import '../model/task.dart';
import 'theme.dart';

Future<void> showReminderPanel(BuildContext context, AppState state) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ReminderPanel(state: state),
  );
}

class _ReminderPanel extends StatefulWidget {
  const _ReminderPanel({required this.state});
  final AppState state;

  @override
  State<_ReminderPanel> createState() => _ReminderPanelState();
}

class _ReminderPanelState extends State<_ReminderPanel> {
  String _lastNotify = '';
  bool _sending = false;

  AppState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final due = s.allSubtasksWithDue.where((i) {
          final left = calendarDaysBetween(today, i.subtask.due!);
          return left <= 0;
        }).toList();
        final repeats = s.repeatsOn(today);
        final planned = s.subtasksPlannedOn(today).where((i) => !i.subtask.done).toList();
        final target = s.profile.lifeTarget;

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.notifications_active_outlined, size: 20),
              const SizedBox(width: 8),
              const Text('提醒'),
              const Spacer(),
              IconButton(
                tooltip: '立刻提醒一次（弹系统通知）',
                onPressed: _sending ? null : _notifyNow,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined, size: 18),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            height: 460,
            child: ListView(
              children: [
                // 人生倒计时
                if (target != null && s.profile.lifeCountdownEnabled)
                  _Box(
                    child: Row(
                      children: [
                        const Icon(Icons.hourglass_bottom, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(builder: (context) {
                            final c = computeCountdown(now, target, start: s.profile.lifeStart);
                            return Text(
                              '人生还剩 ${c.years} 年 ${c.days} 天 ${c.hours.toString().padLeft(2, '0')}:'
                              '${c.minutes.toString().padLeft(2, '0')}:${c.seconds.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),

                // 定时任务
                _Group(
                  title: '今天该做的（定时任务）',
                  empty: '今天没有定时任务',
                  children: [
                    for (final item in repeats)
                      CheckboxListTile(
                        dense: true,
                        value: s.isRepeatDoneOn(item.subtask.id, today),
                        onChanged: (_) => s.toggleRepeatDone(item.subtask.id, today),
                        title: Text(item.subtask.title),
                        subtitle: Text('${item.task.task.title} · ${item.subtask.repeat!.label}'),
                        secondary: Icon(Icons.repeat, size: 18, color: Theme.of(context).colorScheme.primary),
                      ),
                  ],
                ),

                // 到期待办
                _Group(
                  title: '到期的待办',
                  empty: '没有到期或逾期的待办',
                  children: [
                    for (final item in due)
                      CheckboxListTile(
                        dense: true,
                        value: item.subtask.done,
                        onChanged: (v) => s.toggleSubtask(item.task, item.subtask.id, v ?? false),
                        title: Text(item.subtask.title),
                        subtitle: Text(
                          '${item.task.task.title} · ${formatDate(item.subtask.due!)}'
                          '${item.subtask.due!.isBefore(today) ? "（已逾期）" : ""}',
                        ),
                      ),
                  ],
                ),

                // 今天计划做的
                _Group(
                  title: '今天计划做的',
                  empty: '今天没有安排',
                  children: [
                    for (final item in planned)
                      CheckboxListTile(
                        dense: true,
                        value: item.subtask.done,
                        onChanged: (v) => s.toggleSubtask(item.task, item.subtask.id, v ?? false),
                        title: Text(item.subtask.title),
                        subtitle: Text(item.task.task.title),
                      ),
                  ],
                ),

                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: s.calendarPrefs.remindOnTaskDay,
                  onChanged: (v) => s.saveCalendarPrefs(s.calendarPrefs.copyWith(remindOnTaskDay: v)),
                  title: const Text('到期当天弹 Windows 通知'),
                  subtitle: const Text('每天每条只弹一次；通知记录存在本机，重启不会重复弹'),
                ),
                if (_lastNotify.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_lastNotify, style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        );
      },
    );
  }

  Future<void> _notifyNow() async {
    setState(() => _sending = true);
    final n = await s.notifyNow();
    if (mounted) {
      setState(() {
        _sending = false;
        _lastNotify = n == 0 ? '这次没有需要提醒的（或者已经提醒过了）' : '弹了 $n 条通知';
      });
    }
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: Gaps.m),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.empty, required this.children});

  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              empty,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

/// 给待办页复用：把 SubTask 的显示文案拼好（标题 + 规则）
String subtaskLine(SubTask st) => st.isRepeating ? '${st.title} · ${st.repeat!.label}' : st.title;
