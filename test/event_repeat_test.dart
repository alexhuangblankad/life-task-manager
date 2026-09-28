import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/model/event.dart';
import 'package:life_task_manager/model/repeat.dart';

void main() {
  group('多日子重复（每月初一、十五这种）', () {
    test('每月农历初一、十五', () {
      final r = RepeatRule.parse('🔁 每月农历初一、十五')!;
      expect(r.kind, RepeatKind.lunarMonthly);
      expect(r.effectiveDays, [1, 15]);
      expect(r.isMulti, isTrue);
      expect(r.label, '每月农历初一、十五');
      // 写回 md 再读回来一致
      expect(RepeatRule.parse(r.toMarkdown())!.effectiveDays, [1, 15]);
    });

    test('中文数字和阿拉伯数字都认', () {
      expect(RepeatRule.parse('每月农历1、15')!.effectiveDays, [1, 15]);
      expect(RepeatRule.parse('每月农历初一，十五')!.effectiveDays, [1, 15]);
      expect(RepeatRule.parse('每月1、15号')!.effectiveDays, [1, 15]);
      expect(RepeatRule.parse('每月1,15日')!.effectiveDays, [1, 15]);
    });

    test('每周一、三、五', () {
      final r = RepeatRule.parse('🔁 每周一、三、五')!;
      expect(r.kind, RepeatKind.weekly);
      expect(r.effectiveDays, [1, 3, 5]);
      expect(r.label, '每周一、三、五');
      expect(RepeatRule.parse(r.toMarkdown())!.effectiveDays, [1, 3, 5]);
    });

    test('单个日子的老写法照旧', () {
      final r = RepeatRule.parse('🔁 每月15日')!;
      expect(r.day, 15);
      expect(r.effectiveDays, [15]);
      expect(r.isMulti, isFalse);
      expect(r.label, '每月15日');
    });

    test('农历初一和十五那天都命中（2026-09-11 是八月初一，09-25 是八月十五）', () {
      final r = RepeatRule(kind: RepeatKind.lunarMonthly, daysList: const [1, 15]);
      expect(r.occursOn(DateTime(2026, 9, 11)), isTrue);
      expect(r.occursOn(DateTime(2026, 9, 25)), isTrue);
      expect(r.occursOn(DateTime(2026, 9, 20)), isFalse);
    });

    test('每周一三五那几天都命中', () {
      final r = RepeatRule(kind: RepeatKind.weekly, daysList: const [1, 3, 5]);
      expect(r.occursOn(DateTime(2026, 9, 28)), isTrue); // 周一
      expect(r.occursOn(DateTime(2026, 9, 30)), isTrue); // 周三
      expect(r.occursOn(DateTime(2026, 10, 2)), isTrue); // 周五
      expect(r.occursOn(DateTime(2026, 9, 29)), isFalse); // 周二
    });

    test('下次发生算得出来', () {
      final r = RepeatRule(kind: RepeatKind.lunarMonthly, daysList: const [1, 15]);
      // 中秋（八月十五）是 09-25，农历八月 30 天 → 下一个初一是 10-10
      final next = r.nextOccurrence(DateTime(2026, 9, 26));
      expect(next, DateTime(2026, 10, 10));
    });
  });

  group('日程带重复规则', () {
    CalendarEvent make({RepeatRule? repeat}) => CalendarEvent(
          id: 'e1',
          title: '吃素',
          start: DateTime(2026, 9, 1, 8, 0),
          repeat: repeat ?? RepeatRule(kind: RepeatKind.lunarMonthly, daysList: const [1, 15]),
          reminder: null,
        );

    test('命中的日子会出现，别的日子不出现', () {
      final e = make();
      expect(e.occursOnDay(DateTime(2026, 9, 11)), isTrue); // 八月初一
      expect(e.occursOnDay(DateTime(2026, 9, 25)), isTrue); // 八月十五
      expect(e.occursOnDay(DateTime(2026, 9, 20)), isFalse);
    });

    test('重复不往前追溯（创建之前的日子不算）', () {
      final e = CalendarEvent(
        id: 'e2',
        title: '吃素',
        start: DateTime(2026, 9, 20),
        repeat: RepeatRule(kind: RepeatKind.lunarMonthly, daysList: const [1, 15]),
      );
      expect(e.occursOnDay(DateTime(2026, 9, 11)), isFalse); // 早于开始那天
      expect(e.occursOnDay(DateTime(2026, 9, 25)), isTrue);
    });

    test('一次性日程就是原来那样', () {
      final e = CalendarEvent(id: 'e3', title: '体检', start: DateTime(2026, 9, 8, 9));
      expect(e.occursOnDay(DateTime(2026, 9, 8)), isTrue);
      expect(e.occursOnDay(DateTime(2026, 9, 9)), isFalse);
      expect(e.isRepeating, isFalse);
    });

    test('存 JSON 再读回来，重复规则还在', () {
      final e = make();
      final back = CalendarEvent.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(back.repeat?.kind, RepeatKind.lunarMonthly);
      expect(back.repeat?.effectiveDays, [1, 15]);
      expect(back.occursOnDay(DateTime(2026, 9, 25)), isTrue);
    });

    test('每周一次的日程', () {
      final e = CalendarEvent(
        id: 'e4',
        title: '周会',
        start: DateTime(2026, 9, 28, 10),
        repeat: const RepeatRule(kind: RepeatKind.weekly, day: 1),
      );
      expect(e.occursOnDay(DateTime(2026, 10, 5)), isTrue); // 下周一
      expect(e.occursOnDay(DateTime(2026, 10, 6)), isFalse);
    });
  });
}
