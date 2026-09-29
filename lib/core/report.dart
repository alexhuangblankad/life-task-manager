/// 周期报告：**周报**和**月报**共用一套逻辑。
///
/// 设计上分两层：
///   1. [PeriodSummary] —— 纯函数统计，不打网络，测试能直接跑
///   2. [PeriodReport] —— 把统计 + 模型输出渲染成一篇 md
///
/// 存到：月报/202609-月报.md、周报/2026-09-21-周报.md
library;

import 'dart:convert';

import '../model/event.dart';
import '../model/note.dart';
import '../model/task.dart';

class PeriodSummary {
  const PeriodSummary({
    required this.label,
    required this.suffix,
    required this.title,
    required this.daysTotal,
    required this.daysElapsed,
    required this.tasksDone,
    required this.tasksOverdue,
    required this.subtasksOpen,
    required this.doneTitles,
    required this.diaryDays,
    required this.diaryChars,
    required this.avgMood,
    required this.diarySnippets,
    required this.taskNoteCount,
    required this.taskNoteChars,
    required this.taskNoteSnippets,
    required this.eventsTotal,
    required this.eventsDone,
    required this.repeatDone,
    required this.repeatMissed,
    this.daysLeftStart,
    this.daysLeftEnd,
  });

  /// 文件名里的标识：2026-09 / 2026-09-21 / 2026-Q3
  final String label;

  /// 周报 / 双周报 / 月报 / 季报 / 周期报
  final String suffix;

  /// 「2026 年 9 月 21 日 ~ 9 月 27 日」
  final String title;

  final int daysTotal;
  final int daysElapsed;

  final int tasksDone;

  /// 本期该做完、但没做完的
  final int tasksOverdue;
  final int subtasksOpen;

  /// 完成清单：(小任务标题, 属于哪个大任务)
  final List<({String title, String task})> doneTitles;

  final int diaryDays;
  final int diaryChars;
  final double? avgMood;
  final List<String> diarySnippets;

  final int taskNoteCount;
  final int taskNoteChars;
  final List<String> taskNoteSnippets;

  final int eventsTotal;
  final int eventsDone;

  final int repeatDone;
  final int repeatMissed;

  /// 人生倒计时：期初 / 期末还剩多少天（没设倒计时就是 null）
  final int? daysLeftStart;
  final int? daysLeftEnd;

  /// 客观分 0-100。规则写死，方便复现和对比：
  ///   任务完成率 40 + 日记覆盖 25 + 任务杂记 15 + 定时任务 20
  /// 没有对应数据时给中性分，不惩罚也没奖励。
  int get objectiveScore {
    double s = 0;

    final totalTasks = tasksDone + tasksOverdue;
    if (totalTasks > 0) {
      s += 40 * tasksDone / totalTasks;
    } else {
      s += tasksDone > 0 ? 30 : 16;
    }

    if (daysTotal > 0) {
      s += 25 * (diaryDays / daysTotal).clamp(0, 1);
    }

    s += 15 * (taskNoteCount / 8).clamp(0, 1);

    final totalRepeat = repeatDone + repeatMissed;
    if (totalRepeat > 0) {
      s += 20 * repeatDone / totalRepeat;
    } else {
      s += 12;
    }

    return s.round().clamp(0, 100);
  }

  /// 月报：某个月
  static DateTime monthRangeOf(DateTime anchor) => DateTime(anchor.year, anchor.month, 1);

  /// 周报：某天所在周的周一
  static DateTime mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String monthLabel(DateTime d) => '${d.year}-${_two(d.month)}';

  static String dayLabel(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  /// 算某期（周或月）的统计。纯计算，不碰磁盘、不碰网络。
  static PeriodSummary build({
    required String label,
    required String suffix,
    required String title,
    required DateTime first,
    required DateTime last,
    required List<TaskFile> tasks,
    required List<Note> notes,
    required List<CalendarEvent> events,
    List<({String title, String task, bool done})> repeatOccurrences = const [],
    DateTime? now,
    int? daysLeftStart,
    int? daysLeftEnd,
  }) {
    final today = now ?? DateTime.now();
    final daysTotal = last.difference(first).inDays + 1;

    final inRange = (DateTime d) {
      final x = DateTime(d.year, d.month, d.day);
      return !x.isBefore(first) && !x.isAfter(last);
    };

    final started = !today.isBefore(first);
    final isOngoing = inRange(today);
    final cutoff = isOngoing ? today : last;
    final elapsed = isOngoing
        ? today.difference(first).inDays + 1
        : (started ? daysTotal : 0);

    var done = 0;
    var overdue = 0;
    var open = 0;
    final doneTitles = <({String title, String task})>[];

    for (final tf in tasks) {
      for (final st in tf.task.subtasks) {
        if (st.done && st.doneAt != null && inRange(st.doneAt!)) {
          done++;
          doneTitles.add((title: st.title, task: tf.task.title));
        } else if (!st.done && st.due != null && !st.due!.isAfter(cutoff)) {
          overdue++;
        } else if (!st.done) {
          open++;
        }
      }
    }

    var diaryDays = 0;
    var diaryChars = 0;
    final moods = <int>[];
    final diarySnippets = <String>[];
    var taskNoteCount = 0;
    var taskNoteChars = 0;
    final taskNoteSnippets = <String>[];

    for (final n in notes) {
      if (n.isEmpty) continue;
      if (n.type == NoteType.diary) {
        if (!inRange(n.date)) continue;
        diaryDays++;
        diaryChars += n.body.length;
        if (n.mood != null) moods.add(n.mood!);
        diarySnippets.add('${n.date.month}/${n.date.day}：${_snip(n.body)}');
      } else {
        if (!inRange(n.date)) continue;
        taskNoteCount++;
        taskNoteChars += n.body.length;
        final who = n.subtaskTitle ?? n.taskTitle ?? '任务';
        taskNoteSnippets.add('$who：${_snip(n.body)}');
      }
    }

    var eventsTotal = 0;
    var eventsDone = 0;
    for (final e in events) {
      if (!inRange(e.start)) continue;
      eventsTotal++;
      if (e.done) eventsDone++;
    }

    var repeatDone = 0;
    var repeatMissed = 0;
    for (final r in repeatOccurrences) {
      if (r.done) {
        repeatDone++;
      } else {
        repeatMissed++;
      }
    }

    return PeriodSummary(
      label: label,
      suffix: suffix,
      title: title,
      daysTotal: daysTotal,
      daysElapsed: elapsed,
      tasksDone: done,
      tasksOverdue: overdue,
      subtasksOpen: open,
      doneTitles: _cap(doneTitles, 40),
      diaryDays: diaryDays,
      diaryChars: diaryChars,
      avgMood: moods.isEmpty ? null : moods.reduce((a, b) => a + b) / moods.length,
      diarySnippets: _cap(diarySnippets, 14),
      taskNoteCount: taskNoteCount,
      taskNoteChars: taskNoteChars,
      taskNoteSnippets: _cap(taskNoteSnippets, 12),
      eventsTotal: eventsTotal,
      eventsDone: eventsDone,
      repeatDone: repeatDone,
      repeatMissed: repeatMissed,
      daysLeftStart: daysLeftStart,
      daysLeftEnd: daysLeftEnd,
    );
  }

  static List<T> _cap<T>(List<T> list, int max) => list.length <= max ? list : list.sublist(list.length - max);

  static String _snip(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= 160 ? t : '${t.substring(0, 160)}…';
  }

  /// 给模型看的那段（客观事实，不许它编）
  String get digest {
    final b = StringBuffer()
      ..writeln('【$title（$suffix）客观统计】')
      ..writeln('- 本期 $daysTotal 天，已统计 $daysElapsed 天')
      ..writeln('- 完成小任务 $tasksDone 件；本期到期未完成 $tasksOverdue 件；还没到期/没排期的 $subtasksOpen 件')
      ..writeln('- 日记：写了 $diaryDays 天（覆盖 ${(diaryDays / daysTotal * 100).round()}%），'
          '共 $diaryChars 字${avgMood == null ? '' : '，平均心情 ${avgMood!.toStringAsFixed(1)}/5'}')
      ..writeln('- 任务杂记：$taskNoteCount 条，共 $taskNoteChars 字')
      ..writeln('- 日程：$eventsTotal 条，完成 $eventsDone 条');

    if (repeatDone + repeatMissed > 0) {
      b.writeln('- 定时任务：应做 ${repeatDone + repeatMissed} 次，完成 $repeatDone 次');
    }
    if (daysLeftStart != null && daysLeftEnd != null) {
      b.writeln('- 人生倒计时：期初还剩 $daysLeftStart 天 → 期末还剩 $daysLeftEnd 天');
    }

    if (doneTitles.isNotEmpty) {
      b.writeln('\n【完成的事】');
      for (final d in doneTitles) {
        b.writeln('- ${d.title}（大任务：${d.task}）');
      }
    }
    if (diarySnippets.isNotEmpty) {
      b.writeln('\n【日记摘录】');
      for (final s in diarySnippets) {
        b.writeln('- $s');
      }
    }
    if (taskNoteSnippets.isNotEmpty) {
      b.writeln('\n【任务杂记摘录】');
      for (final s in taskNoteSnippets) {
        b.writeln('- $s');
      }
    }
    return b.toString().trimRight();
  }
}

/// 从模型返回的文字里抠出结果。模型经常带 ```json 围栏或是多写几句废话，
/// 所以按「第一个 { 到最后一个 }」截，能解析就行，不要求它守规矩。
class AiReview {
  const AiReview({this.score, this.comment, this.highlights = const [], this.suggestions = const []});

  final int? score;
  final String? comment;
  final List<String> highlights;
  final List<String> suggestions;

  static AiReview parse(String raw) {
    var text = raw.trim();
    final fence = RegExp(r'```(?:json)?', caseSensitive: false);
    text = text.replaceAll(fence, '').replaceAll('```', '').trim();

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final candidate = text.substring(start, end + 1);
      try {
        final obj = jsonDecode(candidate);
        if (obj is Map) return _fromMap(obj.cast<String, dynamic>());
      } catch (_) {
        // 落到下面的兜底
      }
    }
    // 解析不出来：至少把原文当评语留着，别丢
    return AiReview(comment: raw.trim());
  }

  static AiReview _fromMap(Map<String, dynamic> m) {
    int? scoreOf(Object? v) {
      if (v is int) return v.clamp(0, 100);
      if (v is num) return v.round().clamp(0, 100);
      if (v == null) return null;
      final m2 = RegExp(r'\d{1,3}').firstMatch(v.toString());
      return m2 == null ? null : int.parse(m2.group(0)!).clamp(0, 100);
    }

    List<String> listOf(Object? v) {
      if (v == null) return const [];
      if (v is List) {
        return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      final s = v.toString().trim();
      if (s.isEmpty) return const [];
      return s
          .split(RegExp(r'[\n;；]'))
          .map((e) => e.trim().replaceFirst(RegExp(r'^[-•\d.、\s]+'), ''))
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final comment = (m['comment'] ?? m['评语'] ?? m['summary'] ?? '').toString().trim();
    return AiReview(
      score: scoreOf(m['score'] ?? m['评分'] ?? m['分数']),
      comment: comment.isEmpty ? null : comment,
      highlights: listOf(m['highlights'] ?? m['亮点']),
      suggestions: listOf(m['suggestions'] ?? m['建议']),
    );
  }
}

class PeriodReport {
  PeriodReport({
    required this.summary,
    required this.generatedAt,
    this.review,
    this.aiError,
    this.providerName = '',
    this.modelName = '',
  });

  final PeriodSummary summary;
  final DateTime generatedAt;
  final AiReview? review;

  /// 调模型失败时记下来（客观分照样出，不能因为网络问题就没报告）
  final String? aiError;

  final String providerName;
  final String modelName;

  String get label => summary.label;

  int get overallScore {
    final ai = review?.score;
    if (ai == null) return summary.objectiveScore;
    return ((summary.objectiveScore + ai) / 2).round();
  }

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('---')
      ..writeln('suffix: ${summary.suffix}')
      ..writeln('label: ${summary.label}')
      ..writeln('period: ${summary.title}')
      ..writeln('objective_score: ${summary.objectiveScore}')
      ..writeln('ai_score: ${review?.score ?? 'null'}')
      ..writeln('overall_score: $overallScore')
      ..writeln('generated_at: ${generatedAt.toIso8601String()}')
      ..writeln('provider: ${providerName.isEmpty ? '-' : providerName}')
      ..writeln('model: ${modelName.isEmpty ? '-' : modelName}')
      ..writeln('---')
      ..writeln()
      ..writeln('# ${summary.title} · ${summary.suffix}')
      ..writeln()
      ..writeln('## 评分')
      ..writeln()
      ..writeln('| 项目 | 分数 |')
      ..writeln('| --- | --- |')
      ..writeln('| 客观分（完成率 / 日记 / 杂记 / 定时任务） | ${summary.objectiveScore} |')
      ..writeln('| AI 主观分 | ${review?.score ?? '未评分'} |')
      ..writeln('| **综合** | **$overallScore** |')
      ..writeln()
      ..writeln('## 这一期的事实')
      ..writeln()
      ..writeln('- 完成小任务 **${summary.tasksDone}** 件，本期到期未完成 ${summary.tasksOverdue} 件')
      ..writeln('- 日记写了 **${summary.diaryDays}** 天（覆盖 ${(summary.diaryDays / summary.daysTotal * 100).round()}%），共 ${summary.diaryChars} 字'
          '${summary.avgMood == null ? '' : '，平均心情 ${summary.avgMood!.toStringAsFixed(1)}/5'}')
      ..writeln('- 任务杂记 ${summary.taskNoteCount} 条，共 ${summary.taskNoteChars} 字')
      ..writeln('- 日程 ${summary.eventsTotal} 条，完成 ${summary.eventsDone} 条');
    if (summary.repeatDone + summary.repeatMissed > 0) {
      b.writeln('- 定时任务应做 ${summary.repeatDone + summary.repeatMissed} 次，完成 ${summary.repeatDone} 次');
    }
    if (summary.daysLeftStart != null && summary.daysLeftEnd != null) {
      b.writeln('- 人生倒计时：期初还剩 ${summary.daysLeftStart} 天 → 期末还剩 ${summary.daysLeftEnd} 天');
    }

    if (aiError != null) {
      b
        ..writeln()
        ..writeln('> AI 评语这次没生成：$aiError');
    }

    if (review?.comment != null) {
      b
        ..writeln()
        ..writeln('## AI 评语')
        ..writeln()
        ..writeln(review!.comment);
    }
    if (review != null && review!.highlights.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## 亮点')
        ..writeln();
      for (final h in review!.highlights) {
        b.writeln('- $h');
      }
    }
    if (review != null && review!.suggestions.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## ${_nextWord(summary.suffix)}可以试试')
        ..writeln();
      for (final s in review!.suggestions) {
        b.writeln('- $s');
      }
    }
    if (summary.doneTitles.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## 完成清单')
        ..writeln();
      for (final d in summary.doneTitles) {
        b.writeln('- ${d.title}　<sub>${d.task}</sub>');
      }
    }
    b.writeln();
    return b.toString();
  }
}

/// 「下周」「下个月」这种词
String _nextWord(String suffix) => suffix.contains('周') ? '下周' : (suffix == '季报' ? '下个季度' : '下个月');

/// 拼给模型的提示词。要求它只输出 JSON，好解析。
String buildReportPrompt(PeriodSummary s, {String extra = ''}) {
  final next = s.suffix.contains('周') ? '下一周' : (s.suffix == '季报' ? '下个季度' : '下个月');
  final b = StringBuffer()
    ..writeln('你是我的复盘助理。下面是一期（${s.suffix}）的客观统计和摘录，请写一份复盘。')
    ..writeln()
    ..writeln(s.digest)
    ..writeln()
    ..writeln('要求：')
    ..writeln('1. score：0-100 的主观评分。综合看坚持度、思考深度、生活节奏，不要只按完成率打。')
    ..writeln('2. comment：3-6 句评语。直接、具体、不吹捧、不空洞，别用"继续加油"这种废话。')
    ..writeln('3. highlights：2-4 条亮点，必须能从上面的摘录里找到依据。')
    ..writeln('4. suggestions：2-3 条$next能直接执行的具体建议。')
    ..writeln('5. 如果记录很少，就照实说，不要编造没发生过的事。');
  if (extra.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('额外要求：${extra.trim()}');
  }
  b
    ..writeln()
    ..writeln('只输出 JSON，不要任何解释和 markdown 围栏：')
    ..writeln('{"score": 数字, "comment": "评语", "highlights": ["…"], "suggestions": ["…"]}');
  return b.toString();
}

/// 「最近一期报告」的摘要（倒计时页要显示评分和评语，不用读整篇）
class LatestReport {
  const LatestReport({
    required this.fileName,
    required this.period,
    required this.suffix,
    required this.objective,
    required this.overall,
    this.ai,
    this.comment,
    this.provider = '',
    this.model = '',
  });

  final String fileName;

  /// 「2026 年 9 月」或「2026 年 9 月 21 日 ~ 9 月 27 日」
  final String period;

  /// 周报 / 月报 / 季报 / 双周报 / 周期报
  final String suffix;

  final int objective;
  final int? ai;
  final int overall;
  final String? comment;
  final String provider;
  final String model;

  /// 综合分对应的说法
  String get verdict {
    if (overall >= 85) return '这个阶段很稳';
    if (overall >= 70) return '整体不错';
    if (overall >= 55) return '还行，有提升空间';
    if (overall >= 40) return '有点松，下期紧一紧';
    return '这段基本躺平了';
  }
}
