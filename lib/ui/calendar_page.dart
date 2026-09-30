import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../app_state.dart';
import '../core/chinese_calendar.dart';
import '../core/history_today.dart';
import '../core/ids.dart';
import '../model/event.dart';
import '../model/reminder_rule.dart';
import '../model/repeat.dart';
import '../utils/date_text.dart';
import 'home_page.dart';
import 'markdown_view.dart';
import 'note_editor.dart';
import 'remind_picker.dart';
import 'repeat_picker.dart';
import 'theme.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.state});

  final AppState state;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _selected = DateTime.now();
  late DateTime _focused = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return PageScaffold(
      title: '日历',
      subtitle: '日程和待办叠在同一天上看',
      actions: [
        OutlinedButton.icon(
          onPressed: () => _writeDiary(context, _selected),
          icon: const Icon(Icons.edit_note, size: 18),
          label: const Text('写日记'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => _showEventDialog(context, s, _selected),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新增日程'),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, c) {
          // 手机（窄屏）：上下布局 —— 月历在上、选中那天的日程/待办占满下方。
          //
          // 注意：以前这里是固定的 Row（日历 400 宽 + Expanded 放当日日程），
          // 手机上 400 + 分隔线就把宽度吃光，当日日程只剩十几 dp，**整块看不见**。
          final narrow = c.maxWidth < 700;
          if (narrow) {
            // 整页一起滚（不是只滚下面那一小块）：
            // 下面固定成一个窄条的话，能看到的信息太少，日程一多就得在里面再滚一次。
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                      child: Column(
                        children: [
                          _buildCalendar(context, s, 64),
                          const SizedBox(height: 4),
                          const _Legend(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // embedded：跟着整页滚，不再自己滚（避免两层滚动打架）
                  _DayPanel(
                    state: s,
                    day: _selected,
                    embedded: true,
                    onWriteDiary: () => _writeDiary(context, _selected),
                  ),
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  padding: Gaps.page,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // PC 上原来每格 52 有点挤（数字+农历+圆点），拉高一点更透气
                      Card(child: Padding(padding: const EdgeInsets.all(8), child: _buildCalendar(context, s, 62))),
                      const SizedBox(height: Gaps.m),
                      const _Legend(),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _DayPanel(state: s, day: _selected, onWriteDiary: () => _writeDiary(context, _selected))),
            ],
          );
        },
      ),
    );
  }

  void _shiftMonth(int delta) {
    final m = DateTime(_focused.year, _focused.month + delta, 1);
    setState(() => _focused = m);
    widget.state.reloadMonth(m);
  }

  /// [cellH] 每格高度：手机上按可用高度算出来，别再写死
  Widget _buildCalendar(BuildContext context, AppState s, double cellH) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 月份 + 左右箭头自己画一行：三个东西都在同一个 48 高的 Row 里垂直居中，
        // 不会出现「月份和箭头不齐平」的问题（TableCalendar 自带表头做不到随字号自适应）
        SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                onPressed: () => _shiftMonth(-1),
                tooltip: '上个月',
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_focused.year}年${_focused.month}月',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _shiftMonth(1),
                tooltip: '下个月',
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        TableCalendar<Object>(
      locale: 'zh_CN',
      firstDay: DateTime(2000, 1, 1),
      lastDay: DateTime(2100, 12, 31),
      focusedDay: _focused,
      selectedDayPredicate: (d) => isSameDay(d, _selected),
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: '月'},
      // 隐藏自带表头（上面自己画了一行），每格高度由调用方按可用空间算
      headerVisible: false,
      rowHeight: cellH,
      daysOfWeekHeight: 28,
      eventLoader: (day) => [
        ...s.eventsOfDay(day),
        ...s.subtasksDueOn(day),
        ...s.subtasksPlannedOn(day),
      ],
      onDaySelected: (selected, focused) {
        setState(() {
          _selected = selected;
          _focused = focused;
        });
      },
      onPageChanged: (focused) {
        _focused = focused;
        s.reloadMonth(focused);
      },
      calendarBuilders: CalendarBuilders<Object>(
        // 格子里除了日期，再塞一行农历/节日/节气的小字（可在设置里关掉）
        defaultBuilder: (context, day, focusedDay) => _dayCell(context, day, s),
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return null;
          final hasEvent = events.any((e) => e is CalendarEvent);
          final hasTask = events.any((e) => e is! CalendarEvent);
          final scheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasEvent)
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
                if (hasEvent && hasTask) const SizedBox(width: 3),
                if (hasTask)
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
              ],
            ),
          );
        },
      ),
        ),
      ],
    );
  }

  /// 日历格：日期数字 + 农历/节日小字 + 休/班标记
  Widget _dayCell(BuildContext context, DateTime day, AppState s) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = s.calendarPrefs;
    final isSelected = isSameDay(day, _selected);
    final isToday = isSameDay(day, DateTime.now());
    final outside = day.month != _focused.month;

    String? sub;
    Color subColor = scheme.onSurfaceVariant;
    if (prefs.showLunar || prefs.showHoliday) {
      final cn = ChineseDay.of(day);
      if (prefs.showLunar && cn.isFestival) {
        sub = cn.festivals.first;
        subColor = scheme.primary;
      } else if (prefs.showHoliday && cn.isStatutoryRest) {
        sub = '休';
        subColor = const Color(0xFFD32F2F);
      } else if (prefs.showHoliday && cn.isAdjustedWorkday) {
        sub = '班';
        subColor = scheme.onSurfaceVariant;
      } else if (prefs.showLunar && cn.jieQi.isNotEmpty) {
        sub = cn.jieQi;
        subColor = const Color(0xFF2E7D32);
      } else if (prefs.showLunar) {
        sub = cn.lunarShort;
      }
    }

    final fg = isSelected
        ? scheme.onPrimary
        : (isToday ? scheme.primary : (outside ? scheme.outline : scheme.onSurface));

    // 长节日名（「全民国防教育日」这种）以前会把整个格子连日期数字一起缩到很小，
    // 现在只压小字、不动数字：超过 5 个字截断加省略号
    final subText = (sub != null && sub.length > 5) ? '${sub.substring(0, 5)}…' : sub;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSelected ? scheme.primary : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        // 底部留一条给小圆点（标记画在格子底部，不留位置就会压在农历小字上）
        padding: const EdgeInsets.only(top: 5, bottom: 12),
        child: Column(
          // 靠上排、不居中：格子数都一样高，日期数字自然就在同一条水平线上
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: fg,
                fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
                fontSize: 14,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            // 小字位置**固定高度**：没有小字的日子也占位，
            // 否则有农历的格子会被挤高一截，日期数字上下就对不齐了
            SizedBox(
              height: 13,
              child: subText == null
                  ? null
                  : FittedBox(
                      // 只让小字自己缩放，日期数字保持固定大小
                      fit: BoxFit.scaleDown,
                      child: Text(
                        subText,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.0,
                          color: isSelected ? scheme.onPrimary : subColor,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _writeDiary(BuildContext context, DateTime day) async {
    final s = widget.state;
    final existing = await s.diaryOf(day);
    if (!context.mounted) return;
    final text = await showNoteEditor(
      context,
      title: '${formatDateCn(day)} 的日记',
      initialText: existing == null ? '' : '\n',
      hint: '今天发生了什么？留一句也算。',
      onInsertImage: (name, bytes) => s.attachImage(name, bytes),
    );
    if (text == null || text.trim().isEmpty) return;
    await s.saveDiary(day, text.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已写入 ${dateHeader(day)} 的日记')));
    }
  }

  Future<void> _showEventDialog(BuildContext context, AppState s, DateTime day) async {
    final title = TextEditingController();
    var allDay = false;
    var start = DateTime(day.year, day.month, day.day, 9);
    var end = DateTime(day.year, day.month, day.day, 10);
    String? taskId;
    RemindRule? reminder;
    RepeatRule? repeat;

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('新增日程 · ${formatDateCn(day)}'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '日程内容'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allDay,
                    onChanged: (v) => setState(() => allDay = v),
                    title: const Text('全天'),
                  ),
                  if (!allDay)
                    Row(
                      children: [
                        Expanded(child: _timeField(context, setState, '开始', start, (d) => start = d)),
                        const SizedBox(width: 8),
                        Expanded(child: _timeField(context, setState, '结束', end, (d) => end = d)),
                      ],
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: taskId,
                    decoration: const InputDecoration(labelText: '关联大任务（可选）'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('不关联')),
                      ...s.tasks.map((t) => DropdownMenuItem(value: t.task.id, child: Text(t.task.title))),
                    ],
                    onChanged: (v) => setState(() => taskId = v),
                  ),
                  const SizedBox(height: 12),
                  EventRemindPicker(
                    initial: reminder,
                    onChanged: (v) => setState(() => reminder = v),
                    start: allDay ? null : start,
                  ),
                  const Divider(height: 22),
                  RepeatPicker(
                    initial: repeat,
                    onChanged: (v) => setState(() => repeat = v),
                    title: '重复 🔁',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '周期性提醒放这儿：比如「每月农历初一、十五」吃素，'
                    '或「每周一三五」跑步。设了重复，后面每个月的那几天都会自动出现并提醒。',
                    style: Theme.of(context).textTheme.bodySmall,
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
                  await s.upsertEvent(CalendarEvent(
                    id: newEventId(),
                    title: t,
                    start: allDay ? DateTime(day.year, day.month, day.day) : start,
                    end: allDay ? null : end,
                    allDay: allDay,
                    taskId: taskId,
                    reminder: reminder,
                    repeat: repeat,
                  ));
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('添加'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _timeField(BuildContext context, StateSetter setState, String label, DateTime value, void Function(DateTime) onChanged) {
    return InkWell(
      onTap: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
        );
        if (t != null) {
          setState(() => onChanged(DateTime(value.year, value.month, value.day, t.hour, t.minute)));
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text('${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'),
      ),
    );
  }
}

class _GreetingBanner extends StatelessWidget {
  const _GreetingBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onPrimaryContainer, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget dot(Color c) => Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    return Wrap(
      spacing: 16,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [dot(scheme.primary), const SizedBox(width: 5), const Text('日程')]),
        Row(mainAxisSize: MainAxisSize.min, children: [dot(Colors.orange), const SizedBox(width: 5), const Text('待办到期')]),
      ],
    );
  }
}

class _DayPanel extends StatelessWidget {
  const _DayPanel({
    required this.state,
    required this.day,
    required this.onWriteDiary,
    this.embedded = false,
  });

  final AppState state;
  final DateTime day;
  final VoidCallback onWriteDiary;

  /// true = 自己是外面某个滚动视图里的一段，不要再套一层滚动
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final events = state.eventsOfDay(day);
    final dueTasks = state.subtasksDueOn(day);
    final plannedTasks = state
        .subtasksPlannedOn(day)
        .where((p) => !dueTasks.any((d) => d.subtask.id == p.subtask.id))
        .toList();

    return FutureBuilder(
      future: state.diaryOf(day),
      builder: (context, snapshot) {
        final diary = snapshot.data;
        final cn = ChineseDay.of(day);
        final prefs = state.calendarPrefs;
        final greeting = cn.greeting;
        final repeats = state.repeatsOn(day);
        final history = prefs.showHistory
            ? (state.history?.of(day) ?? const <HistoryEvent>[])
            : const <HistoryEvent>[];

        final items = <Widget>[
            Text(dateHeader(day), style: Theme.of(context).textTheme.titleLarge),
            if (prefs.showLunar || prefs.showHoliday)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  cn.detailLine,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            if (prefs.showYiJi)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '宜：${cn.yi.take(4).join('、')}　忌：${cn.ji.take(4).join('、')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (prefs.showGreeting && greeting != null) ...[
              const SizedBox(height: Gaps.m),
              _GreetingBanner(text: greeting),
            ],
            const SizedBox(height: Gaps.m),
            if (repeats.isNotEmpty) ...[
              _Section(
                title: '今天该做的（定时任务）',
                count: repeats.length,
                empty: '',
                children: [
                  for (final item in repeats)
                    CheckboxListTile(
                      dense: true,
                      value: state.isRepeatDoneOn(item.subtask.id, day),
                      onChanged: (_) => state.toggleRepeatDone(item.subtask.id, day),
                      title: Text(item.subtask.title),
                      subtitle: Text(
                        '${item.task.task.title} · ${item.subtask.repeat!.label}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      secondary: Icon(Icons.repeat, size: 18, color: Theme.of(context).colorScheme.primary),
                    ),
                ],
              ),
              const SizedBox(height: Gaps.m),
            ],
            _Section(
              title: '日程',
              count: events.length,
              empty: '这天没有日程',
              children: [
                for (final e in events)
                  ListTile(
                    dense: true,
                    leading: Checkbox(
                      value: e.done,
                      onChanged: (v) => state.upsertEvent(e.copyWith(done: v ?? false)),
                    ),
                    title: Text(e.title, style: e.done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                    subtitle: Text(
                      [
                        e.timeLabel,
                        if (e.repeat != null) '🔁 ${e.repeat!.label}',
                        if (e.reminder != null) '🔔 ${e.reminder!.label}',
                        if (e.taskId != null)
                          '关联：${state.tasks.where((t) => t.task.id == e.taskId).map((t) => t.task.title).join()}',
                        if (e.note != null) e.note!,
                      ].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '写日程杂记',
                          icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                          onPressed: () async {
                            final text = await showNoteEditor(
                              context,
                              title: '日程杂记 · ${e.title}',
                              initialText: e.note ?? '',
                            );
                            if (text != null) await state.upsertEvent(e.copyWith(note: text.trim()));
                          },
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => state.deleteEvent(e.id),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Gaps.m),
            _Section(
              title: '计划这天做的事',
              count: plannedTasks.length,
              empty: '这天没有安排要做的事（到「待办」里给小任务填「计划哪天做 ⏳」）',
              children: [
                for (final item in plannedTasks)
                  CheckboxListTile(
                    dense: true,
                    value: item.subtask.done,
                    onChanged: (v) => state.toggleSubtask(item.task, item.subtask.id, v ?? false),
                    title: Text(item.subtask.title),
                    subtitle: Text(item.task.task.title, style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
            const SizedBox(height: Gaps.m),
            _Section(
              title: '到期待办',
              count: dueTasks.length,
              empty: '这天没有到期的待办',
              children: [
                for (final item in dueTasks)
                  CheckboxListTile(
                    dense: true,
                    value: item.subtask.done,
                    onChanged: (v) => state.toggleSubtask(item.task, item.subtask.id, v ?? false),
                    title: Text(item.subtask.title),
                    subtitle: Text(
                      item.task.task.title,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Gaps.m),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Gaps.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('这天写的日记', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: onWriteDiary,
                          icon: const Icon(Icons.edit, size: 16),
                          label: Text(diary == null ? '写今天的' : '追加'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (diary == null || diary.body.trim().isEmpty)
                      Text(
                        '还没写。写完按天存档，以后翻日历就能看回来。',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      MarkdownView(data: diary.body),
                  ],
                ),
              ),
            ),
            if (prefs.showHistory) ...[
              const SizedBox(height: Gaps.m),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Gaps.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_stories_outlined, size: 18),
                          const SizedBox(width: 6),
                          Text('历史上的今天', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (history.isEmpty)
                        Text(
                          '这天没有收录的事件',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        for (final e in history)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 52,
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    e.year,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      if (e.desc.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            e.desc,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      if (history.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '数据来源：${state.history?.source ?? ""}（已打包在本地，不联网）',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                  fontSize: 11,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ];

        // embedded = 跟着外面那层一起滚（整页滚动时别套两层，会打架）
        if (embedded) {
          return Padding(
            padding: Gaps.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: items,
            ),
          );
        }
        return ListView(padding: Gaps.page, children: items);
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.count, required this.empty, required this.children});

  final String title;
  final int count;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.l, Gaps.m, Gaps.s, Gaps.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 6),
                  if (count > 0)
                    Chip(
                      label: Text('$count'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(empty, style: Theme.of(context).textTheme.bodySmall),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}
