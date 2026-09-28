import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/ids.dart';
import '../model/reminder_rule.dart';
import '../model/repeat.dart';
import '../model/task.dart';
import 'home_page.dart';
import 'remind_picker.dart';
import 'theme.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: '待办',
      subtitle: '大任务往下拆小任务，小任务可以挂截止日期、写任务杂记',
      actions: [
        FilledButton.icon(
          onPressed: () => _showNewTaskDialog(context, state),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新增大任务'),
        ),
      ],
      child: state.tasks.isEmpty
          ? EmptyHint(
              text: '还没有大任务。先写一个你真正想完成的事。',
              icon: Icons.flag_outlined,
              action: FilledButton(
                onPressed: () => _showNewTaskDialog(context, state),
                child: const Text('新增大任务'),
              ),
            )
          : ListView.separated(
              padding: Gaps.page,
              itemCount: state.tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: Gaps.m),
              itemBuilder: (_, i) => _TaskCard(state: state, tf: state.tasks[i]),
            ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.state, required this.tf});

  final AppState state;
  final TaskFile tf;

  @override
  Widget build(BuildContext context) {
    final task = tf.task;
    final scheme = Theme.of(context).colorScheme;
    final notes = state.notesForTask(task.id);

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
        title: Row(
          children: [
            Expanded(child: Text(task.title, style: Theme.of(context).textTheme.titleMedium)),
            _dueBadge(context, task.effectiveDeadline),
            if (notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Tooltip(
                  message: '有 ${notes.length} 条任务杂记',
                  child: Icon(Icons.sticky_note_2_outlined, size: 16, color: scheme.primary),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: task.progress, minHeight: 6),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${task.doneCount}/${task.totalCount}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (task.description.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.description.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                await _showEditTaskDialog(context, state, tf);
              case 'note':
                await _showTaskNoteDialog(context, state, tf, null);
              case 'open':
                await _openTaskFile(context, tf);
              case 'delete':
                final ok = await _confirm(context, '删除大任务', '文件会先进回收站（留 30 天），不会直接消失。');
                if (ok) await state.deleteTask(tf);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑大任务')),
            PopupMenuItem(value: 'note', child: Text('写任务杂记')),
            PopupMenuItem(value: 'open', child: Text('查看源文件（Markdown）')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        children: [
          for (final st in task.subtasks)
            _SubtaskRow(state: state, tf: tf, st: st),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showAddSubtaskDialog(context, state, tf),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加小任务'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dueBadge(BuildContext context, DateTime? due) {
    if (due == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final left = DateTime(due.year, due.month, due.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final color = left < 0
        ? Theme.of(context).colorScheme.error
        : (left <= 3 ? Colors.orange : Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          Icon(Icons.event, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            left < 0 ? '逾期 ${-left} 天' : (left == 0 ? '今天' : '剩 $left 天'),
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<void> _openTaskFile(BuildContext context, TaskFile tf) async {
    final raw = await state.repo.readFileOrNull(tf.task.filePath) ?? tf.raw;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tf.task.filePath),
        content: SizedBox(
          width: 720,
          height: 480,
          child: SingleChildScrollView(
            child: SelectableText(raw, style: const TextStyle(fontFamily: 'Consolas', fontSize: 13, height: 1.5)),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({required this.state, required this.tf, required this.st});

  final AppState state;
  final TaskFile tf;
  final SubTask st;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = st.isOverdueAt(DateTime.now());
    return CheckboxListTile(
      value: st.done,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (v) async {
        await state.toggleSubtask(tf, st.id, v ?? false);
        if ((v ?? false) && context.mounted) {
          await _showTaskNoteDialog(context, state, tf, st);
        }
      },
      title: Text(
        st.title,
        style: st.done
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: scheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: Row(
        children: [
          if (st.isRepeating) ...[
            Icon(Icons.repeat, size: 13, color: scheme.primary),
            const SizedBox(width: 3),
            Text(
              st.repeat!.label,
              style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
          ],
          if (st.reminder != null) ...[
            Icon(Icons.notifications_active_outlined, size: 13, color: scheme.tertiary),
            const SizedBox(width: 3),
            Text(
              st.reminder!.label,
              style: TextStyle(fontSize: 12, color: scheme.tertiary),
            ),
            const SizedBox(width: 10),
          ],
          if (st.scheduled != null) ...[
            Icon(Icons.play_circle_outline, size: 13, color: scheme.primary),
            const SizedBox(width: 3),
            Text(
              '计划 ${formatDate(st.scheduled!)}',
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
            const SizedBox(width: 10),
          ],
          if (st.due != null) ...[
            Icon(Icons.event, size: 13, color: overdue ? scheme.error : scheme.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(
              formatDate(st.due!),
              style: TextStyle(fontSize: 12, color: overdue ? scheme.error : scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 10),
          ],
          if (st.priority != Priority.none) ...[
            Text(Priority.marks[st.priority] ?? '', style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 3),
            Text('${Priority.labels[st.priority]}优先', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          if (st.doneAt != null) ...[
            const SizedBox(width: 10),
            Text('✅ ${formatDate(st.doneAt!)}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
      secondary: PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: (v) async {
          switch (v) {
            case 'note':
              await _showTaskNoteDialog(context, state, tf, st);
            case 'edit':
              await _showEditSubtaskDialog(context, state, tf, st);
            case 'delete':
              await state.deleteSubtask(tf, st.id);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'note', child: Text('写任务杂记')),
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }
}

// ─────────────────────────── 弹窗 ───────────────────────────

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
      ],
    ),
  );
  return r ?? false;
}

Future<void> _showNewTaskDialog(BuildContext context, AppState state) async {
  final title = TextEditingController();
  final desc = TextEditingController();
  final tags = TextEditingController();
  DateTime? deadline;

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('新增大任务'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '大任务名称', hintText: '例：草坪机器人毕设'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: desc,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '一句话描述（可留空）'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          locale: const Locale('zh', 'CN'),
                        );
                        if (d != null) setState(() => deadline = d);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: '截止日期（可留空）'),
                        child: Text(deadline == null ? '未设置' : formatDate(deadline!)),
                      ),
                    ),
                  ),
                  if (deadline != null)
                    IconButton(onPressed: () => setState(() => deadline = null), icon: const Icon(Icons.clear)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tags,
                decoration: const InputDecoration(labelText: '标签（逗号分隔，可留空）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final t = title.text.trim();
              if (t.isEmpty) return;
              await state.createTask(
                title: t,
                description: desc.text.trim(),
                deadline: deadline,
                tags: tags.text.split(RegExp(r'[,，]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    ),
  );
}

/// 重复规则选择器（定时任务用）
class _RepeatPicker extends StatefulWidget {
  const _RepeatPicker({required this.initial, required this.onChanged});

  final RepeatRule? initial;
  final ValueChanged<RepeatRule?> onChanged;

  @override
  State<_RepeatPicker> createState() => _RepeatPickerState();
}

class _RepeatPickerState extends State<_RepeatPicker> {
  static const _kinds = ['不重复', '每天', '每周', '每月', '每月农历', '每年'];

  late String _kind;
  late int _day;
  late int _month;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    if (r == null) {
      _kind = '不重复';
      _day = 1;
      _month = 1;
    } else {
      _kind = switch (r.kind) {
        RepeatKind.daily => '每天',
        RepeatKind.weekly => '每周',
        RepeatKind.monthly => '每月',
        RepeatKind.lunarMonthly => '每月农历',
        RepeatKind.yearly || RepeatKind.lunarYearly => '每年',
      };
      _day = r.day ?? 1;
      _month = r.month ?? 1;
    }
  }

  void _emit() {
    switch (_kind) {
      case '不重复':
        widget.onChanged(null);
      case '每天':
        widget.onChanged(const RepeatRule(kind: RepeatKind.daily));
      case '每周':
        widget.onChanged(RepeatRule(kind: RepeatKind.weekly, day: _day.clamp(1, 7)));
      case '每月':
        widget.onChanged(RepeatRule(kind: RepeatKind.monthly, day: _day.clamp(1, 31)));
      case '每月农历':
        widget.onChanged(RepeatRule(kind: RepeatKind.lunarMonthly, day: _day.clamp(1, 30)));
      case '每年':
        widget.onChanged(RepeatRule(
          kind: widget.initial?.kind == RepeatKind.lunarYearly ? RepeatKind.lunarYearly : RepeatKind.yearly,
          month: _month.clamp(1, 12),
          day: _day.clamp(1, 31),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: const InputDecoration(
            labelText: '定时任务 🔁',
            helperText: '例：每月15日交房租、每月农历十五上香、每周一开组会',
          ),
          items: [for (final k in _kinds) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _kind = v);
            _emit();
          },
        ),
        if (_kind == '每周')
          DropdownButtonFormField<int>(
            initialValue: _day.clamp(1, 7),
            decoration: const InputDecoration(labelText: '周几'),
            items: [
              for (var i = 1; i <= 7; i++)
                DropdownMenuItem(value: i, child: Text(['一', '二', '三', '四', '五', '六', '日'][i - 1])),
            ],
            onChanged: (v) {
              setState(() => _day = v ?? 1);
              _emit();
            },
          ),
        if (_kind == '每年')
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _month.toString(),
                  decoration: const InputDecoration(labelText: '月份'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    _month = int.tryParse(v) ?? 1;
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: _day.toString(),
                  decoration: const InputDecoration(labelText: '几号'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    _day = int.tryParse(v) ?? 1;
                    _emit();
                  },
                ),
              ),
            ],
          )
        else if (_kind == '每月' || _kind == '每月农历')
          TextFormField(
            initialValue: _day.toString(),
            decoration: InputDecoration(
              labelText: '几号',
              helperText: _kind == '每月农历' ? '农历：1-30，例如 15 = 十五' : '公历：1-31',
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              _day = int.tryParse(v) ?? 1;
              _emit();
            },
          ),
        if (_kind != '不重复' && _kind != '每天')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '规则：${widget.initial?.label ?? ""}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

Future<void> _showAddSubtaskDialog(BuildContext context, AppState state, TaskFile tf) async {
  final title = TextEditingController();
  DateTime? due;
  DateTime? scheduled;
  RepeatRule? repeat;
  RemindRule? reminder;
  var priority = Priority.none;

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('给「${tf.task.title}」加小任务'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '小任务',
                  helperText: '没有截止日期也完全可以，写个「计划哪天做」就行',
                ),
                onSubmitted: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _dateField(
                context,
                label: '计划哪天做 ⏳',
                hint: '这天想动这件事（可不填）',
                value: scheduled,
                onChanged: (d) => setState(() => scheduled = d),
              ),
              const SizedBox(height: 10),
              _dateField(
                context,
                label: '截止日期 📅',
                hint: '最晚什么时候做完（可不填）',
                value: due,
                onChanged: (d) => setState(() => due = d),
              ),
              const SizedBox(height: 12),
              _RepeatPicker(
                initial: repeat,
                onChanged: (r) => setState(() => repeat = r),
              ),
              const SizedBox(height: 12),
              RemindPicker(
                initial: reminder,
                onChanged: (r) => setState(() => reminder = r),
                hasDue: due != null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: Priority.none, label: Text('无')),
                  ButtonSegment(value: Priority.low, label: Text('低 🔽')),
                  ButtonSegment(value: Priority.medium, label: Text('中 🔼')),
                  ButtonSegment(value: Priority.high, label: Text('高 ⏫')),
                ],
                selected: {priority},
                onSelectionChanged: (s) => setState(() => priority = s.first),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final t = title.text.trim();
              if (t.isEmpty) return;
              await state.addSubtask(
                tf,
                SubTask(
                  id: newSubtaskId(),
                  title: t,
                  due: due,
                  scheduled: scheduled,
                  repeat: repeat,
                  reminder: reminder,
                  priority: priority,
                ),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    ),
  );
}

/// 日期选择框（计划日期 / 截止日期共用）
Widget _dateField(
  BuildContext context, {
  required String label,
  required String hint,
  required DateTime? value,
  required ValueChanged<DateTime?> onChanged,
}) {
  return Row(
    children: [
      Expanded(
        child: InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              locale: const Locale('zh', 'CN'),
            );
            if (d != null) onChanged(d);
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, helperText: hint),
            child: Text(value == null ? '未设置' : formatDate(value)),
          ),
        ),
      ),
      if (value != null)
        IconButton(tooltip: '清除', onPressed: () => onChanged(null), icon: const Icon(Icons.clear)),
    ],
  );
}

Future<void> _showEditSubtaskDialog(BuildContext context, AppState state, TaskFile tf, SubTask st) async {
  final title = TextEditingController(text: st.title);
  DateTime? due = st.due;
  DateTime? scheduled = st.scheduled;
  RepeatRule? repeat = st.repeat;
  RemindRule? reminder = st.reminder;
  var priority = st.priority;

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('编辑小任务'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: '标题')),
              const SizedBox(height: 12),
              _dateField(
                context,
                label: '计划哪天做 ⏳',
                hint: '想哪天动这件事',
                value: scheduled,
                onChanged: (d) => setState(() => scheduled = d),
              ),
              const SizedBox(height: 10),
              _dateField(
                context,
                label: '截止日期 📅',
                hint: '最晚什么时候做完',
                value: due,
                onChanged: (d) => setState(() => due = d),
              ),
              const SizedBox(height: 12),
              _RepeatPicker(
                initial: repeat,
                onChanged: (r) => setState(() => repeat = r),
              ),
              const SizedBox(height: 12),
              RemindPicker(
                initial: reminder,
                onChanged: (r) => setState(() => reminder = r),
                hasDue: due != null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: Priority.none, label: Text('无')),
                  ButtonSegment(value: Priority.low, label: Text('低')),
                  ButtonSegment(value: Priority.medium, label: Text('中')),
                  ButtonSegment(value: Priority.high, label: Text('高')),
                ],
                selected: {priority},
                onSelectionChanged: (s) => setState(() => priority = s.first),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await state.editSubtask(
                tf,
                st.copyWith(
                  title: title.text.trim(),
                  due: due,
                  clearDue: due == null,
                  scheduled: scheduled,
                  clearScheduled: scheduled == null,
                  repeat: repeat,
                  clearRepeat: repeat == null,
                  reminder: reminder,
                  clearReminder: reminder == null,
                  priority: priority,
                ),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

/// 完成小任务后写任务杂记（可跳过、可事后补）
Future<void> _showTaskNoteDialog(BuildContext context, AppState state, TaskFile tf, SubTask? st) async {
  final existing = state.notes.where((n) => n.taskId == tf.task.id).toList();
  final controller = TextEditingController();

  final text = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(st == null ? '写任务杂记 · ${tf.task.title}' : '完成了「${st.title}」'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('顺手记一句：怎么做的、卡在哪、下次注意什么。不想写可以直接跳过。'),
            const SizedBox(height: 10),
            if (existing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '这个任务已经有 ${existing.length} 条杂记：${existing.map((n) => formatDate(n.date)).join('、')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            TextField(
              controller: controller,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(hintText: '例：仿真参数调好了，但转弯半径还得再压一压'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('跳过')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存杂记'),
        ),
      ],
    ),
  );

  final trimmed = (text ?? '').trim();
  controller.dispose();
  if (trimmed.isEmpty) return; // 跳过、或者写了空的 → 什么都不做

  await state.saveTaskNote(
    day: DateTime.now(),
    body: trimmed,
    taskTitle: tf.task.title,
    taskId: tf.task.id,
    subtaskTitle: st?.title,
  );
}

Future<void> _showEditTaskDialog(BuildContext context, AppState state, TaskFile tf) async {
  final title = TextEditingController(text: tf.task.title);
  final desc = TextEditingController(text: tf.task.description);
  DateTime? deadline = tf.task.deadline;

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('编辑大任务'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: '名称')),
              const SizedBox(height: 12),
              TextField(controller: desc, maxLines: 4, decoration: const InputDecoration(labelText: '描述')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: deadline ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          locale: const Locale('zh', 'CN'),
                        );
                        if (d != null) setState(() => deadline = d);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: '截止日期'),
                        child: Text(deadline == null ? '未设置' : formatDate(deadline!)),
                      ),
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => deadline = null), icon: const Icon(Icons.clear)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await state.updateTaskMeta(
                tf,
                title: title.text.trim().isEmpty ? null : title.text.trim(),
                description: desc.text,
                deadline: deadline,
                clearDeadline: deadline == null,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}
