import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:life_task_manager/core/llm_client.dart';
import 'package:life_task_manager/core/report.dart';
import 'package:life_task_manager/model/ai_config.dart';
import 'package:life_task_manager/model/event.dart';
import 'package:life_task_manager/model/note.dart';
import 'package:life_task_manager/model/report_cycle.dart';
import 'package:life_task_manager/model/task.dart';

/// http 包默认按 latin1 解 body，中文会炸；模拟真实服务端带 charset=utf-8
http.Response _json(String body) => http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});

PeriodSummary _summary({
  String label = '2026-09',
  String suffix = '月报',
  String title = '2026 年 9 月',
  int daysTotal = 30,
  int daysElapsed = 30,
  int tasksDone = 0,
  int tasksOverdue = 0,
  int diaryDays = 0,
  int taskNoteCount = 0,
  int repeatDone = 0,
  int repeatMissed = 0,
}) =>
    PeriodSummary(
      label: label,
      suffix: suffix,
      title: title,
      daysTotal: daysTotal,
      daysElapsed: daysElapsed,
      tasksDone: tasksDone,
      tasksOverdue: tasksOverdue,
      subtasksOpen: 0,
      doneTitles: const [],
      diaryDays: diaryDays,
      diaryChars: 0,
      avgMood: null,
      diarySnippets: const [],
      taskNoteCount: taskNoteCount,
      taskNoteChars: 0,
      taskNoteSnippets: const [],
      eventsTotal: 0,
      eventsDone: 0,
      repeatDone: repeatDone,
      repeatMissed: repeatMissed,
    );

void main() {
  group('报告周期（周报是「选周几总结上一周」）', () {
    test('每周选周一 → 上一周（上周一 ~ 上周日）', () {
      const c = ReportCycle(unit: ReportUnit.week, weekday: 1);
      final p = c.previousPeriod(DateTime(2026, 9, 29)); // 周二
      expect(p.first, DateTime(2026, 9, 21));
      expect(p.last, DateTime(2026, 9, 27));
      expect(p.label, '2026-09-21');
      expect(p.suffix, '周报');
    });

    test('每周：那天正好是周一，算的也是刚过去的那一周', () {
      const c = ReportCycle(unit: ReportUnit.week, weekday: 1);
      final p = c.previousPeriod(DateTime(2026, 9, 28)); // 周一
      expect(p.first, DateTime(2026, 9, 21));
      expect(p.last, DateTime(2026, 9, 27));
    });

    test('每周选周日 → 上一周还是周一到周日', () {
      const c = ReportCycle(unit: ReportUnit.week, weekday: 7);
      final p = c.previousPeriod(DateTime(2026, 10, 4)); // 周日
      expect(p.first, DateTime(2026, 9, 21));
      expect(p.last, DateTime(2026, 9, 27));
    });

    test('每两周：期长 14 天', () {
      const c = ReportCycle(unit: ReportUnit.biweek, weekday: 1);
      final p = c.previousPeriod(DateTime(2026, 9, 29));
      expect(p.last.difference(p.first).inDays + 1, 14);
      expect(p.suffix, '双周报');
    });

    test('每月 1 号 → 上个月整月', () {
      const c = ReportCycle(unit: ReportUnit.month, monthDay: 1);
      final p = c.previousPeriod(DateTime(2026, 9, 29));
      expect(p.first, DateTime(2026, 8, 1));
      expect(p.last, DateTime(2026, 8, 31));
      expect(p.label, '2026-08');
      expect(p.suffix, '月报');
    });

    test('每月：跨年也对', () {
      const c = ReportCycle(unit: ReportUnit.month, monthDay: 5);
      final p = c.previousPeriod(DateTime(2027, 1, 5));
      expect(p.first, DateTime(2026, 12, 1));
      expect(p.last, DateTime(2026, 12, 31));
    });

    test('每季度：9 月看的是 Q2', () {
      const c = ReportCycle(unit: ReportUnit.quarter, monthDay: 1);
      final p = c.previousPeriod(DateTime(2026, 9, 29));
      expect(p.label, '2026-Q2');
      expect(p.first, DateTime(2026, 4, 1));
      expect(p.last, DateTime(2026, 6, 30));
      expect(p.suffix, '季报');
    });

    test('每季度：1 月看的是去年 Q4', () {
      const c = ReportCycle(unit: ReportUnit.quarter, monthDay: 10);
      final p = c.previousPeriod(DateTime(2026, 1, 10));
      expect(p.label, '2025-Q4');
      expect(p.first, DateTime(2025, 10, 1));
      expect(p.last, DateTime(2025, 12, 31));
    });

    test('自定义天数：期长固定、首尾不重叠', () {
      const c = ReportCycle(unit: ReportUnit.custom, customDays: 10);
      final today = DateTime(2026, 9, 29);
      final a = c.previousPeriod(today);
      expect(a.last.difference(a.first).inDays + 1, 10);
      expect(a.last.isBefore(today), isTrue);
      final b = c.previousPeriod(a.first); // 再往前一期
      expect(b.last.add(const Duration(days: 1)), a.first);
    });

    test('哪天该生成', () {
      expect(const ReportCycle(unit: ReportUnit.week, weekday: 7).shouldRunOn(DateTime(2026, 10, 4)), isTrue);
      expect(const ReportCycle(unit: ReportUnit.week, weekday: 3).shouldRunOn(DateTime(2026, 10, 4)), isFalse);
      expect(const ReportCycle(unit: ReportUnit.month, monthDay: 1).shouldRunOn(DateTime(2026, 10, 1)), isTrue);
      expect(const ReportCycle(unit: ReportUnit.month, monthDay: 1).shouldRunOn(DateTime(2026, 10, 2)), isFalse);
      expect(const ReportCycle(unit: ReportUnit.quarter, monthDay: 1).shouldRunOn(DateTime(2026, 4, 1)), isTrue);
      expect(const ReportCycle(unit: ReportUnit.quarter, monthDay: 1).shouldRunOn(DateTime(2026, 5, 1)), isFalse);
    });

    test('说明文案说人话', () {
      expect(const ReportCycle(unit: ReportUnit.week, weekday: 7).description.contains('每周日总结上一周'), isTrue);
      expect(const ReportCycle(unit: ReportUnit.month, monthDay: 1).description.contains('每月 1 号总结上个月'), isTrue);
    });
  });

  group('客观分（规则写死，能复现）', () {
    test('一件事没记录 → 中性分，不夸也不骂', () {
      expect(_summary().objectiveScore, 28);
    });

    test('全勤 → 100', () {
      final s = _summary(tasksDone: 10, diaryDays: 30, taskNoteCount: 8, repeatDone: 4);
      expect(s.objectiveScore, 100);
    });

    test('完成率一半、日记一半', () {
      final s = _summary(tasksDone: 5, tasksOverdue: 5, diaryDays: 15, taskNoteCount: 4, repeatDone: 2, repeatMissed: 2);
      // 20 + 12.5 + 7.5 + 10 = 50
      expect(s.objectiveScore, 50);
    });

    test('逾期多会拉低分', () {
      final a = _summary(tasksDone: 8, tasksOverdue: 2);
      final b = _summary(tasksDone: 2, tasksOverdue: 8);
      expect(a.objectiveScore, greaterThan(b.objectiveScore));
    });
  });

  group('统计（从真实数据结构算）', () {
    test('完成时间只算本期的', () {
      const raw = '''
---
id: t-1
title: 毕设
---

## 子任务
- [x] 九月的 ✅ 2026-09-10 ^s-1
- [x] 十月的 ✅ 2026-10-02 ^s-2
- [ ] 没做完的 📅 2026-09-20 ^s-3
''';
      final tf = parseTaskFile(raw);
      final s = PeriodSummary.build(
        label: '2026-09',
        suffix: '月报',
        title: '2026 年 9 月',
        first: DateTime(2026, 9, 1),
        last: DateTime(2026, 9, 30),
        tasks: [tf],
        notes: const [],
        events: const [],
        now: DateTime(2026, 10, 1),
      );
      expect(s.tasksDone, 1); // 只有 9 月那条算
      expect(s.tasksOverdue, 1); // 9/20 到期没做完
      expect(s.doneTitles.single.title, '九月的');
    });

    test('日记和任务杂记分开算，且只算本期的', () {
      final notes = [
        Note(id: 'n1', type: NoteType.diary, date: DateTime(2026, 9, 3), body: '今天挺好'),
        Note(id: 'n2', type: NoteType.diary, date: DateTime(2026, 9, 4), body: '还行', mood: 4),
        Note(id: 'n3', type: NoteType.task, date: DateTime(2026, 9, 4), body: '做完这个事，感想是……', taskTitle: '毕设'),
        Note(id: 'n4', type: NoteType.diary, date: DateTime(2026, 10, 1), body: '下个月的'),
      ];
      final s = PeriodSummary.build(
        label: '2026-09',
        suffix: '月报',
        title: '2026 年 9 月',
        first: DateTime(2026, 9, 1),
        last: DateTime(2026, 9, 30),
        tasks: const [],
        notes: notes,
        events: const [],
        now: DateTime(2026, 10, 1),
      );
      expect(s.diaryDays, 2);
      expect(s.taskNoteCount, 1);
      expect(s.avgMood, 4.0);
    });

    test('日程按开始时间归档', () {
      final events = [
        CalendarEvent(id: 'e1', title: '开会', start: DateTime(2026, 9, 8, 14), done: true),
        CalendarEvent(id: 'e2', title: '体检', start: DateTime(2026, 9, 9, 8)),
      ];
      final s = PeriodSummary.build(
        label: '2026-09',
        suffix: '月报',
        title: '2026 年 9 月',
        first: DateTime(2026, 9, 1),
        last: DateTime(2026, 9, 30),
        tasks: const [],
        notes: const [],
        events: events,
        now: DateTime(2026, 10, 1),
      );
      expect(s.eventsTotal, 2);
      expect(s.eventsDone, 1);
    });

    test('周报只覆盖 7 天', () {
      final s = PeriodSummary.build(
        label: '2026-09-21',
        suffix: '周报',
        title: '2026 年 9 月 21 日 ~ 9 月 27 日',
        first: DateTime(2026, 9, 21),
        last: DateTime(2026, 9, 27),
        tasks: const [],
        notes: const [],
        events: const [],
        now: DateTime(2026, 9, 29),
      );
      expect(s.daysTotal, 7);
      expect(s.daysElapsed, 7);
    });
  });

  group('模型返回解析（它经常不守规矩）', () {
    test('标准 JSON', () {
      final r = AiReview.parse('{"score": 82, "comment": "还行", "highlights": ["a"], "suggestions": ["b"]}');
      expect(r.score, 82);
      expect(r.comment, '还行');
      expect(r.highlights, ['a']);
      expect(r.suggestions, ['b']);
    });

    test('带 ```json 围栏也能解析', () {
      final r = AiReview.parse('```json\n{"score": 77, "comment": "ok"}\n```');
      expect(r.score, 77);
      expect(r.comment, 'ok');
    });

    test('前后多说几句废话也能抠出来', () {
      final r = AiReview.parse('好的，这是结果：\n{"score": "90分", "comment": "不错"}\n希望有帮助！');
      expect(r.score, 90);
      expect(r.comment, '不错');
    });

    test('中文键名也认', () {
      final r = AiReview.parse('{"评分": 66, "评语": "一般", "亮点": ["x"], "建议": ["y"]}');
      expect(r.score, 66);
      expect(r.comment, '一般');
      expect(r.highlights, ['x']);
    });

    test('完全不是 JSON：至少把原文当评语留着', () {
      final r = AiReview.parse('这个月你做得还可以，就是日记写少了。');
      expect(r.score, isNull);
      expect(r.comment, contains('日记写少了'));
    });

    test('分数超范围会被夹回 0-100', () {
      expect(AiReview.parse('{"score": 130}').score, 100);
    });
  });

  group('提示词', () {
    test('带上统计和「不许编」的要求', () {
      final s = _summary(tasksDone: 3);
      final p = buildReportPrompt(s);
      expect(p.contains('2026 年 9 月'), isTrue);
      expect(p.contains('完成小任务 3 件'), isTrue);
      expect(p.contains('不要编造'), isTrue);
      expect(p.contains('只输出 JSON'), isTrue);
    });

    test('额外要求会拼进去', () {
      final p = buildReportPrompt(_summary(), extra: '多说缺点');
      expect(p.contains('多说缺点'), isTrue);
    });
  });

  group('月报渲染', () {
    test('md 里有评分表和 AI 部分', () {
      final report = PeriodReport(
        summary: _summary(tasksDone: 4, diaryDays: 10),
        generatedAt: DateTime(2026, 10, 1, 9),
        review: const AiReview(score: 80, comment: '这个月节奏还行。', highlights: ['坚持写日记'], suggestions: ['早点睡']),
        providerName: 'DeepSeek 深度求索',
        modelName: 'deepseek-chat',
      );
      final md = report.toMarkdown();
      expect(md.contains('objective_score:'), isTrue);
      expect(md.contains('ai_score: 80'), isTrue);
      expect(md.contains('## AI 评语'), isTrue);
      expect(md.contains('这个月节奏还行。'), isTrue);
      expect(md.contains('## 亮点'), isTrue);
      expect(md.contains('## 下个月可以试试'), isTrue);
    });

    test('AI 挂了也照出报告，错误写进去', () {
      final report = PeriodReport(
        summary: _summary(),
        generatedAt: DateTime(2026, 10, 1),
        aiError: 'API Key 不对或没权限（401）',
      );
      final md = report.toMarkdown();
      expect(md.contains('AI 评语这次没生成'), isTrue);
      expect(md.contains('401'), isTrue);
      expect(report.overallScore, report.summary.objectiveScore);
    });

    test('综合分是客观分和 AI 分的平均', () {
      final report = PeriodReport(
        summary: _summary(tasksDone: 10, diaryDays: 30, taskNoteCount: 8, repeatDone: 4), // 100
        generatedAt: DateTime(2026, 10, 1),
        review: const AiReview(score: 80),
      );
      expect(report.overallScore, 90);
    });
  });

  group('AI 配置', () {
    test('没填 key 就不算配好', () {
      const c = AiConfig(enabled: true, providerId: 'deepseek');
      expect(c.ready, isFalse);
      expect(c.copyWith(apiKey: 'sk-123').ready, isTrue);
    });

    test('本机 Ollama 不用 key', () {
      const c = AiConfig(enabled: true, providerId: 'ollama');
      expect(c.ready, isTrue);
      expect(c.effectiveBaseUrl, 'http://127.0.0.1:11434/v1');
    });

    test('模型名留空就用发行商默认', () {
      const c = AiConfig(providerId: 'qwen');
      expect(c.effectiveModel, 'qwen-plus');
      expect(c.copyWith(model: 'qwen-max').effectiveModel, 'qwen-max');
    });

    test('存进设备配置再读回来，周期和 key 都在', () {
      const c = AiConfig(
        enabled: true,
        providerId: 'zhipu',
        apiKey: 'sk-abc',
        cycle: ReportCycle(unit: ReportUnit.biweek, weekday: 5, monthDay: 3, customDays: 21),
      );
      final back = AiConfig.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.providerId, 'zhipu');
      expect(back.apiKey, 'sk-abc');
      expect(back.cycle.unit, ReportUnit.biweek);
      expect(back.cycle.weekday, 5);
    });

    test('key 在界面上打码', () {
      expect(maskKey(''), '未填');
      expect(maskKey('sk-1234567890abcdef'), 'sk-1****cdef');
    });
  });

  group('调用模型（用假客户端，不打真网络）', () {
    test('OpenAI 兼容：取到内容', () async {
      final mock = MockClient((req) async {
        expect(req.url.toString(), 'https://api.test/v1/chat/completions');
        expect(req.headers['Authorization'], 'Bearer sk-test');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['model'], 'test-model');
        return _json(jsonEncode({'choices': [{'message': {'content': '好'}}]}));
      });
      final out = await LlmClient(client: mock).chat(
        cfg: const AiConfig(enabled: true, providerId: 'custom', apiKey: 'sk-test', baseUrl: 'https://api.test/v1', model: 'test-model'),
        systemPrompt: 's',
        userPrompt: 'u',
      );
      expect(out, '好');
    });

    test('401 翻译成人话', () async {
      final mock = MockClient((_) async => http.Response('{"error":"bad key"}', 401));
      expect(
        () => LlmClient(client: mock).chat(
          cfg: const AiConfig(enabled: true, providerId: 'custom', apiKey: 'x', baseUrl: 'https://api.test/v1', model: 'm'),
          systemPrompt: 's',
          userPrompt: 'u',
        ),
        throwsA(predicate((e) => e is LlmException && e.message.contains('API Key'))),
      );
    });

    test('Anthropic 走自己的 /v1/messages', () async {
      final mock = MockClient((req) async {
        expect(req.url.toString(), 'https://api.anthropic.com/v1/messages');
        expect(req.headers['x-api-key'], 'sk-ant');
        return _json(jsonEncode({'content': [{'type': 'text', 'text': '嗨'}]}));
      });
      final out = await LlmClient(client: mock).chat(
        cfg: const AiConfig(enabled: true, providerId: 'anthropic', apiKey: 'sk-ant', model: 'claude-3-5-haiku-20241022'),
        systemPrompt: 's',
        userPrompt: 'u',
      );
      expect(out, '嗨');
    });

    test('没配好就直接说，不发请求', () async {
      var called = false;
      final mock = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      expect(
        () => LlmClient(client: mock).chat(
          cfg: const AiConfig(enabled: false, providerId: 'deepseek'),
          systemPrompt: 's',
          userPrompt: 'u',
        ),
        throwsA(isA<LlmException>()),
      );
      expect(called, isFalse);
    });
  });
}
