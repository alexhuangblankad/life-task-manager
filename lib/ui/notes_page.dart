import 'package:flutter/material.dart';

import '../app_state.dart';
import '../model/note.dart';
import '../utils/date_text.dart';
import 'home_page.dart';
import 'markdown_view.dart';
import 'note_editor.dart';
import 'theme.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final notes = [...state.notes]..sort((a, b) => b.date.compareTo(a.date));
    final grouped = <String, List<Note>>{};
    for (final n in notes) {
      grouped.putIfAbsent(isoDate(n.date), () => []).add(n);
    }

    return PageScaffold(
      title: '杂记',
      subtitle: '${dateMonthFolder(state.month)} · 共 ${notes.length} 条（任务杂记 ${notes.where((n) => n.type == NoteType.task).length} / 日记 ${notes.where((n) => n.type == NoteType.diary).length}）',
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
        OutlinedButton.icon(
          onPressed: () => _writeDiary(context, DateTime.now()),
          icon: const Icon(Icons.edit_note, size: 18),
          label: const Text('写今天的日记'),
        ),
      ],
      child: notes.isEmpty
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
                      children: [
                        for (final n in entry.value) _NoteTile(state: state, note: n),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  static String _dateLabel(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : dateHeader(d);
  }

  Future<void> _writeDiary(BuildContext context, DateTime day) async {
    final text = await showNoteEditor(
      context,
      title: '${formatDateCn(day)} 的日记',
      hint: '今天发生了什么？留一句也算。',
    );
    if (text == null || text.trim().isEmpty) return;
    await state.saveDiary(day, text.trim());
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
      // 用正文首行当标题很难认，用户明确要求改掉。
      title: Text(
        note.subtaskTitle ?? note.taskTitle ?? firstLine,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          isDiary ? '日记' : '任务杂记',
          // 标题已经用了小任务名，这里补上它属于哪个大任务当上下文
          if (note.subtaskTitle != null && note.taskTitle != null) note.taskTitle!,
          if (note.mood != null) '心情 ${note.mood}/5',
          // 不再显示文件路径（用户要求删掉，看着烦）
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
