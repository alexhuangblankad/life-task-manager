import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/model/repeat.dart';
import 'package:life_task_manager/model/task.dart';

void main() {
  group('重复规则解析与展示', () {
    test('各种写法都能解析', () {
      expect(RepeatRule.parse('每天')!.kind, RepeatKind.daily);
      expect(RepeatRule.parse('🔁 每周一')!.day, 1);
      expect(RepeatRule.parse('每周日')!.day, 7);
      expect(RepeatRule.parse('每月15日')!.kind, RepeatKind.monthly);
      expect(RepeatRule.parse('每月15日')!.day, 15);
      expect(RepeatRule.parse('每月农历十五')!.kind, RepeatKind.lunarMonthly);
      expect(RepeatRule.parse('每月农历十五')!.day, 15);
      expect(RepeatRule.parse('每月农历廿三')!.day, 23);
      expect(RepeatRule.parse('每月农历初一')!.day, 1);
      expect(RepeatRule.parse('每年9月28日')!.kind, RepeatKind.yearly);
      expect(RepeatRule.parse('每年9月28日')!.month, 9);
      expect(RepeatRule.parse('每年农历八月十五')!.kind, RepeatKind.lunarYearly);
      expect(RepeatRule.parse('每年农历八月十五')!.month, 8);
      expect(RepeatRule.parse('每年农历八月十五')!.day, 15);
    });

    test('看不懂的就返回 null，绝不瞎猜', () {
      expect(RepeatRule.parse('随便写点什么'), isNull);
      expect(RepeatRule.parse(''), isNull);
      expect(RepeatRule.parse('每月99日'), isNull);
    });

    test('label 与 markdown 往返一致', () {
      for (final s in ['每天', '每周三', '每月15日', '每月农历十五', '每年9月28日']) {
        final r = RepeatRule.parse(s)!;
        expect(r.label, s);
        expect(RepeatRule.parse(r.toMarkdown())!.label, s);
      }
    });
  });

  group('发生日期计算', () {
    test('每天', () {
      final r = RepeatRule.parse('每天')!;
      expect(r.occursOn(DateTime(2026, 9, 29)), isTrue);
      expect(r.daysUntilNext(DateTime(2026, 9, 29)), 0);
    });

    test('每周（周一=1）', () {
      final r = RepeatRule.parse('每周一')!;
      expect(r.occursOn(DateTime(2026, 9, 28)), isTrue); // 2026-09-28 是周一
      expect(r.occursOn(DateTime(2026, 9, 29)), isFalse);
      expect(r.nextOccurrence(DateTime(2026, 9, 29)), DateTime(2026, 10, 5));
      expect(r.daysUntilNext(DateTime(2026, 9, 29)), 6);
    });

    test('每月 15 号', () {
      final r = RepeatRule.parse('每月15日')!;
      expect(r.occursOn(DateTime(2026, 10, 15)), isTrue);
      expect(r.occursOn(DateTime(2026, 10, 16)), isFalse);
      expect(r.nextOccurrence(DateTime(2026, 9, 29)), DateTime(2026, 10, 15));
    });

    test('每月农历十五（要靠农历换算）', () {
      final r = RepeatRule.parse('每月农历十五')!;
      // 2026-09-25 是农历八月十五（已用农历库核对过）
      expect(r.occursOn(DateTime(2026, 9, 25)), isTrue);
      expect(r.occursOn(DateTime(2026, 9, 26)), isFalse);
      // 下一次应该是农历九月十五
      final next = r.nextOccurrence(DateTime(2026, 9, 26))!;
      expect(next.isAfter(DateTime(2026, 9, 26)), isTrue);
      expect(next.month, anyOf(10, 11));
    });

    test('每年农历八月十五 = 中秋', () {
      final r = RepeatRule.parse('每年农历八月十五')!;
      expect(r.occursOn(DateTime(2026, 9, 25)), isTrue);
      expect(r.occursOn(DateTime(2026, 9, 24)), isFalse);
      expect(r.occursOn(DateTime(2027, 9, 15)), isTrue, reason: '2027 中秋在 9 月 15 日');
    });

    test('每年公历固定日', () {
      final r = RepeatRule.parse('每年9月28日')!;
      expect(r.occursOn(DateTime(2026, 9, 28)), isTrue);
      expect(r.occursOn(DateTime(2027, 9, 28)), isTrue);
      expect(r.occursOn(DateTime(2026, 9, 27)), isFalse);
    });
  });

  group('写进 md 文件', () {
    test('定时任务能存进文件并读回来', () {
      const raw = '''---
id: t-1
title: 日常
---

# 日常

## 子任务
- [ ] 交房租 🔁 每月15日 ^s-rent01
- [ ] 上香 🔁 每月农历十五 ^s-incense
- [ ] 周会 🔁 每周一 ⏳ 2026-09-29 ^s-meeting
''';
      final t = parseTaskFile(raw);
      expect(t.task.subtasks.length, 3);

      final rent = t.task.subtasks[0];
      expect(rent.title, '交房租');
      expect(rent.repeat!.label, '每月15日');
      expect(rent.repeatsOn(DateTime(2026, 10, 15)), isTrue);

      final incense = t.task.subtasks[1];
      expect(incense.repeat!.label, '每月农历十五');
      expect(incense.repeatsOn(DateTime(2026, 9, 25)), isTrue);

      final meeting = t.task.subtasks[2];
      expect(meeting.repeat!.label, '每周一');
      expect(meeting.scheduled, DateTime(2026, 9, 29), reason: '重复规则不能把计划日期吃掉');
    });

    test('新建带重复规则的任务行，格式正确', () {
      final line = renderSubtaskLine(SubTask(
        id: 's-1',
        title: '交房租',
        repeat: RepeatRule.parse('每月15日'),
      ));
      expect(line, '- [ ] 交房租 🔁 每月15日 ^s-1');
      expect(parseSubtaskLine(line)!.repeat!.label, '每月15日');
    });

    test('取消重复规则', () {
      const raw = '# 日常\n\n## 子任务\n- [ ] 交房租 🔁 每月15日 ^s-1\n';
      final st = parseTaskFile(raw).task.subtasks.single;
      final out = updateSubtask(raw, st.copyWith(clearRepeat: true));
      expect(out.contains('🔁'), isFalse);
      expect(out.contains('- [ ] 交房租 ^s-1'), isTrue);
    });
  });
}
