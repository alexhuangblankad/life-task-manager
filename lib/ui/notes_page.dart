import 'package:flutter/material.dart';

import '../app_state.dart';
import '../model/note.dart';
import '../model/task.dart';
import '../utils/date_text.dart';
import 'home_page.dart';
import 'markdown_view.dart';
import 'note_editor.dart';
import 'theme.dart';

/// 杂记页：**和待办页同构**
///
/// - 上面一栏按**大任务**分组，每条带进度条；小任务那一行能勾、能点开看它名下的杂记
///   （跨月份，直接读盘，所以点开时才知道全部条数）。
/// - 下面一栏是日记，还是按日期分组，行为和以前一样。
class NotesPage extends StatefulWidget {
  const NotesPage({super.key, required this.state});

  final AppState state;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  /// 只看本月有杂记的大任务（默认开：杂记页是来读杂记的，不是来看待办清单的）
  bool _onlyWithNotes = true;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final taskNotes = state.notes.where((n) => n.type == NoteType.task).toList();
    final diaries = state.notes.where((n) => n.type == NoteType.diary).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final groups = _taskGroups(taskNotes);

    return PageScaffold(
      title: '杂记',
      subtitle: '${dateMonthFolder(state.month)} · 任务杂记 ${taskNotes.length} 条 / 日记 ${diaries.length} 条',
      actions: [
        IconButton(
          tooltip: '上个月',
          onPressed: () => state.reloadMonth(DateTime(state.month.year, state.month.month - 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Text('${state.month.year} 年 ${state.month.month} 月'),
        IconButton(
          tooltip: '下个月',
          onPressed: () => state.reloadMonth(DateTime(state.month.year, state.month.month + 1)),
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text('只看有杂记的'),
          selected: _onlyWithNotes,
          onSelected: (v) => setState(() => _onlyWithNotes = v),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _writeDiary(context, DateTime.now()),
          icon: const Icon(Icons.edit_note, size: 18),
          label: const Text('写今天的日记'),
        ),
      ],
      child: state.notes.isEmpty
          ? EmptyHint(
              text: '${state.month.year} 年 ${state.month.month} 月还没有杂记',
              icon: Icons.edit_note_outlined,
              action: FilledButton(
                onPressed: () => _writeDiary(context, DateTime.now()),
                child: const Text('写今天的日记'),
              ),
            )
          : ListView(
              padding: Gaps.page,
              children: [
                _sectionTitle(context, '任务杂记', '完成任务时顺手记的那些，按大任务分组'),
                if (groups.isEmpty)
                  _hint(context, state.tasks.isEmpty
                      ? '还没有大任务。到「待办」里建一个，完成小任务时就能顺手记一句。'
                      : '这个月还没写过任务杂记。在「待办」里勾掉一个小任务就能写一条。')
                else
                  for (final g in groups)
                    _TaskNotesCard(
                      state: state,
                      group: g,
                      onlyWithNotes: _onlyWithNotes,
                      onChanged: () => setState(() {}),
                    ),
                const SizedBox(height: Gaps.l),
                _sectionTitle(context, '日记', '按天归档，一天一个文件'),
                if (diaries.isEmpty)
                  _hint(context, '这个月还没写日记。')
                else
                  ..._diaryBlocks(context, diaries),
              ],
            ),
    );
  }

  /// 把本月的任务杂记按大任务归堆。
  ///
  /// 认大任务优先用 ID；老杂记可能只有标题，那就退回按标题认。
  /// 实在认不到任何大任务的（任务被删了），单独归一堆放在最后 —— 杂记不能因为
  /// 任务没了就看不见。
  List<_TaskGroup> _taskGroups(List<Note> taskNotes) {
    final used = <int>{};
    final out = <_TaskGroup>[];

    for (final tf in state.tasks) {
      final mine = <Note>[];
      for (var i = 0; i < taskNotes.length; i++) {
        if (used.contains(i)) continue;
        final n = taskNotes[i];
        final hit = n.taskId != null ? n.taskId == tf.task.id : n.taskTitle == tf.task.title;
        if (hit) {
          mine.add(n);
          used.add(i);
        }
      }
      if (mine.isEmpty && _onlyWithNotes) continue;
      out.add(_TaskGroup(task: tf, notes: mine));
    }

    final orphans = <Note>[];
    for (var i = 0; i < taskNotes.length; i++) {
      if (!used.contains(i)) orphans.add(taskNotes[i]);
    }
    if (orphans.isNotEmpty) out.add(_TaskGroup(task: null, notes: orphans));

    return out;
  }

  List<Widget> _diaryBlocks(BuildContext context, List<Note> diaries) {
    final grouped = <String, List<Note>>{};
    for (final n in diaries) {
      grouped.putIfAbsent(isoDate(n.date), () => []).add(n);
    }
    return [
      for (final entry in grouped.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text(
            _dateLabel(entry.key),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Card(
          child: Column(
            children: [for (final n in entry.value) _NoteTile(state: state, note: n)],
          ),
        ),
      ],
    ];
  }

  Widget _sectionTitle(BuildContext context, String title, String hint) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  static String _dateLabel(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : dateHeader(d);
  }

  Future<void> _writeDiary(BuildContext context, DateTime day) async {
    final text = await showNoteEditor(
      context,
      title: '${formatDateCn(day)} 的日记',
      hint: '今天发生了什么？留一句也算。',
      onInsertImage: (name, bytes) => state.attachImage(name, bytes),
    );
    if (text == null || text.trim().isEmpty) return;
    await state.saveDiary(day, text.trim());
  }
}

/// 一坨：某个大任务（或「任务已被删」那一坨）名下的本月任务杂记
class _TaskGroup {
  const _TaskGroup({required this.task, required this.notes});

  final TaskFile? task;
  final List<Note> notes;

  String get title => task?.task.title ?? '其他任务杂记';
  BigTask? get big => task?.task;
}

class _TaskNotesCard extends StatelessWidget {
  const _TaskNotesCard({
    required this.state,
    required this.group,
    required this.onChanged,
    required this.onlyWithNotes,
  });

  final AppState state;
  final _TaskGroup group;
  final VoidCallback onChanged;
  final bool onlyWithNotes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final big = group.big;

    // 先把杂记分给各个小任务，分不掉的（没挂小任务、或者那个小任务已经被删/改名对不上了）
    // 统一放在这一坨的最后，绝不能因为对不上就看不见。
    final matched = <String, List<Note>>{};
    final loose = <Note>[];
    if (big != null) {
      for (final n in group.notes) {
        SubTask? hit;
        for (final st in big.subtasks) {
          if (n.belongsToSubtask(st.id, st.title)) {
            hit = st;
            break;
          }
        }
        if (hit == null) {
          loose.add(n);
        } else {
          matched.putIfAbsent(hit.id, () => []).add(n);
        }
      }
    } else {
      loose.addAll(group.notes);
    }

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                group.title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Tooltip(
              message: '本月 ${group.notes.length} 条任务杂记',
              child: Row(
                children: [
                  Icon(Icons.sticky_note_2_outlined, size: 15, color: scheme.primary),
                  const SizedBox(width: 3),
                  Text('${group.notes.length}', style: TextStyle(fontSize: 12, color: scheme.primary)),
                ],
              ),
            ),
          ],
        ),
        subtitle: big == null ? null : _progress(context, big),
        children: [
          if (big != null)
            for (final st in big.subtasks)
              if (!onlyWithNotes || (matched[st.id] ?? const []).isNotEmpty)
                _SubtaskNotesRow(
                  state: state,
                  tf: group.task!,
                  st: st,
                  monthNotes: matched[st.id] ?? const [],
                  onChanged: onChanged,
                ),
          if (big != null && big.subtasks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '这个大任务还没拆小任务；下面这些杂记没挂到具体小任务上。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          for (final n in loose) _NoteTile(state: state, note: n),
        ],
      ),
    );
  }

  Widget _progress(BuildContext context, BigTask big) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: big.progress, minHeight: 6),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${big.doneCount}/${big.totalCount}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Text(
            '点小任务看它名下的杂记',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 小任务一行：勾选状态和待办页共用同一份数据（这边勾了那边也变），
/// 点一下能看到它**所有月份**的杂记。
class _SubtaskNotesRow extends StatelessWidget {
  const _SubtaskNotesRow({
    required this.state,
    required this.tf,
    required this.st,
    required this.monthNotes,
    required this.onChanged,
  });

  final AppState state;
  final TaskFile tf;
  final SubTask st;

  /// 本月这个小任务名下的杂记（条数显示用；全部条数点开才读盘）
  final List<Note> monthNotes;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8, right: 8),
      leading: Checkbox(
        value: st.done,
        onChanged: (v) async {
          await state.toggleSubtask(tf, st.id, v ?? false);
          onChanged();
        },
      ),
      title: Text(
        st.title,
        style: st.done
            ? TextStyle(decoration: TextDecoration.lineThrough, color: scheme.onSurfaceVariant)
            : null,
      ),
      subtitle: Text(
        monthNotes.isEmpty ? '本月还没写杂记 · 点开看全部' : '本月 ${monthNotes.length} 条 · 点开看全部',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => showSubtaskNotes(context, state, tf, st, onChanged: onChanged),
    );
  }
}

/// 小任务名下**所有**任务杂记（跨月份，点开时才去盘上读）
Future<void> showSubtaskNotes(
  BuildContext context,
  AppState state,
  TaskFile tf,
  SubTask st, {
  VoidCallback? onChanged,
}) async {
  final all = await state.notesForSubtask(tf, st);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(st.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: dialogWidth(dialogContext, 640),
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${tf.task.title} · 共 ${all.length} 条任务杂记',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: all.isEmpty
                    ? const Center(child: Text('这个小任务名下还没有杂记。'))
                    : ListView.separated(
                        itemCount: all.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _SubtaskNoteEntry(
                          state: state,
                          note: all[i],
                          onChanged: () {
                            setState(() {});
                            onChanged?.call();
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final text = await showNoteEditor(
                dialogContext,
                title: '给「${st.title}」写一条',
                hint: '怎么做的、卡在哪、下次注意什么。',
                onInsertImage: (name, bytes) => state.attachImage(name, bytes),
              );
              if (text == null || text.trim().isEmpty) return;
              await state.saveTaskNote(
                day: DateTime.now(),
                body: text.trim(),
                taskId: tf.task.id,
                taskTitle: tf.task.title,
                subtaskId: st.id,
                subtaskTitle: st.title,
              );
              if (!dialogContext.mounted) return;
              final again = await state.notesForSubtask(tf, st);
              if (!dialogContext.mounted) return;
              setState(() => all
                ..clear()
                ..addAll(again));
              onChanged?.call();
            },
            child: const Text('写一条'),
          ),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('关闭')),
        ],
      ),
    ),
  );
}

class _SubtaskNoteEntry extends StatelessWidget {
  const _SubtaskNoteEntry({required this.state, required this.note, required this.onChanged});

  final AppState state;
  final Note note;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formatDate(note.date),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (note.mood != null) ...[
                const SizedBox(width: 8),
                Text('心情 ${note.mood}/5', style: Theme.of(context).textTheme.bodySmall),
              ],
              const Spacer(),
              IconButton(
                tooltip: '编辑',
                iconSize: 18,
                onPressed: () async {
                  final text = await showNoteEditor(
                    context,
                    title: '编辑任务杂记',
                    initialText: note.body,
                    onInsertImage: (name, bytes) => state.attachImage(name, bytes),
                  );
                  if (text == null) return;
                  await state.updateNote(note.copyWith(body: text));
                  onChanged();
                },
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: '删除（进回收站）',
                iconSize: 18,
                onPressed: () async {
                  await state.deleteNote(note);
                  onChanged();
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          MarkdownView(data: note.body),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.state, required this.note});

  final AppState state;
  final Note note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDiary = note.type == NoteType.diary;
    final firstLine = note.body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '（空）');

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(
        isDiary ? Icons.book_outlined : Icons.task_alt,
        size: 18,
        color: isDiary ? scheme.primary : Colors.orange,
      ),
      // 标题用**小任务的名字**（没有就退回大任务名、再退回正文首行）。
      title: Text(
        note.subtaskTitle ?? note.taskTitle ?? firstLine,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          isDiary ? '日记' : '任务杂记',
          if (note.subtaskTitle != null && note.taskTitle != null) note.taskTitle!,
          if (note.mood != null) '心情 ${note.mood}/5',
        ].join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: (v) async {
          switch (v) {
            case 'edit':
              final text = await showNoteEditor(
                context,
                title: isDiary ? '编辑日记' : '编辑任务杂记',
                initialText: note.body,
                onInsertImage: (name, bytes) => state.attachImage(name, bytes),
              );
              if (text != null) await state.updateNote(note.copyWith(body: text));
            case 'mood':
              final m = await _pickMood(context, note.mood);
              if (m != null) await state.updateNote(note.copyWith(mood: m.value, clearMood: m.value == 0));
            case 'delete':
              await state.deleteNote(note);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'mood', child: Text('记心情')),
          PopupMenuItem(value: 'delete', child: Text('删除（进回收站）')),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: MarkdownView(data: note.body),
          ),
        ),
      ],
    );
  }

  Future<({int value})?> _pickMood(BuildContext context, int? current) async {
    var mood = current ?? 3;
    return showDialog<({int value})>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('今天心情怎么样'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => mood = i),
                  icon: Icon(
                    i <= mood ? Icons.sentiment_satisfied_alt : Icons.sentiment_neutral,
                    color: i <= mood ? Colors.orange : null,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, (value: 0)), child: const Text('清除')),
            FilledButton(onPressed: () => Navigator.pop(context, (value: mood)), child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}
