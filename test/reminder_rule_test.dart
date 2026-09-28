import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/model/event.dart';
import 'package:life_task_manager/model/reminder_rule.dart';
import 'package:life_task_manager/model/task.dart';

void main() {
  group('任务提醒规则 🔔', () {
    test('各种写法都能解析', () {
      expect(RemindRule.parse('到期当天')!.kind, RemindKind.onDueDay);
      expect(RemindRule.parse('🔔 到期当天')!.kind, RemindKind.onDueDay);
      expect(RemindRule.parse('🔔 提前3天')!.days, 3);
      expect(RemindRule.parse('提前7天')!.days, 7);
      expect(RemindRule.parse('乱写') == null, isTrue);
    });

    test('指定时间能解析（含 T 形式）', () {
      final a = RemindRule.parse('🔔 2026-10-02 09:30')!;
      expect(a.kind, RemindKind.atTime);
      expect(a.at, DateTime(2026, 10, 2, 9, 30));
      final b = RemindRule.parse('2026-10-02T09:30')!;
      expect(b.at, DateTime(2026, 10, 2, 9, 30));
    });

    test('触发时刻：到期当天 = 当天 9 点', () {
      final r = const RemindRule.onDueDay();
      expect(r.fireAt(DateTime(2026, 10, 8)), DateTime(2026, 10, 8, 9));
    });

    test('触发时刻：提前3天', () {
      final r = RemindRule.daysBefore(3);
      expect(r.fireAt(DateTime(2026, 10, 8)), DateTime(2026, 10, 5, 9));
    });

    test('没有到期日期时算不出触发时刻', () {
      expect(const RemindRule.onDueDay().fireAt(null), isNull);
      expect(RemindRule.daysBefore(1).fireAt(null), isNull);
    });

    test('文案', () {
      expect(const RemindRule.onDueDay().label, '到期当天');
      expect(RemindRule.daysBefore(3).label, '提前3天');
      expect(RemindRule.at(DateTime(2026, 10, 2, 9, 0)).label, '2026-10-02 09:00');
      expect(const RemindRule.minutesBefore(0).label, '开始时');
      expect(const RemindRule.minutesBefore(30).label, '提前30分钟');
      expect(const RemindRule.minutesBefore(60).label, '提前1小时');
    });

    test('写进 md 再读回来还是同一条', () {
      final r = RemindRule.daysBefore(3);
      expect(r.toMarkdown(), '🔔 提前3天');
      expect(RemindRule.parse(r.toMarkdown())!.days, 3);
    });
  });

  group('日程提醒（相对开始时间）', () {
    test('提前30分钟 / 开始时', () {
      final start = DateTime(2026, 10, 8, 14, 0);
      expect(const RemindRule.minutesBefore(30).fireFrom(start), DateTime(2026, 10, 8, 13, 30));
      expect(const RemindRule.minutesBefore(0).fireFrom(start), start);
      expect(const RemindRule.minutesBefore(1440).fireFrom(start), DateTime(2026, 10, 7, 14, 0));
    });

    test('日程的 remindAt 用开始时间算', () {
      final e = CalendarEvent(
        id: 'e1',
        title: '开会',
        start: DateTime(2026, 10, 8, 14, 0),
        reminder: const RemindRule.minutesBefore(30),
      );
      expect(e.remindAt, DateTime(2026, 10, 8, 13, 30));
      expect(e.copyWith(title: '改').remindAt, DateTime(2026, 10, 8, 13, 30));
      expect(e.copyWith(clearReminder: true).remindAt, isNull);
    });

    test('日程存 JSON 再读回来提醒还在', () {
      final e = CalendarEvent(
        id: 'e2',
        title: '体检',
        start: DateTime(2026, 10, 8, 8, 30),
        reminder: const RemindRule.minutesBefore(60),
      );
      final back = CalendarEvent.fromJson(e.toJson());
      expect(back.reminder?.kind, RemindKind.minutesBefore);
      expect(back.reminder?.minutes, 60);
      expect(back.remindAt, DateTime(2026, 10, 8, 7, 30));
    });
  });

  group('小任务带提醒写进 md', () {
    test('一行里 重复 + 提醒 都能读回', () {
      const line = '- [ ] 交房租 🔁 每月15日 📅 2026-10-15 🔔 提前3天 ^s-abc123';
      final st = parseSubtaskLine(line)!;
      expect(st.title, '交房租');
      expect(st.repeat!.label, '每月15日');
      expect(st.reminder!.days, 3);
      expect(st.due, DateTime(2026, 10, 15));
      expect(st.id, 's-abc123');
    });

    test('渲染回去也带 🔔', () {
      final st = SubTask(
        id: 's-x1',
        title: '面试',
        due: DateTime(2026, 10, 2),
        reminder: RemindRule.at(DateTime(2026, 10, 1, 20, 0)),
      );
      final line = renderSubtaskLine(st);
      expect(line.contains('🔔 2026-10-01 20:00'), isTrue);
      final back = parseSubtaskLine(line)!;
      expect(back.reminder!.at, DateTime(2026, 10, 1, 20, 0));
    });
  });
}
