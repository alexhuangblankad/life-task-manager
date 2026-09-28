import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/core/countdown.dart';

void main() {
  group('倒计时', () {
    test('整一年：刚好一年整', () {
      final c = computeCountdown(DateTime(2026, 9, 28, 12), DateTime(2027, 9, 28, 12));
      expect(c.years, 1);
      expect(c.days, 0);
      expect(c.hours, 0);
      expect(c.totalDays, 365);
      expect(c.expired, isFalse);
    });

    test('跨闰年：2024-02-28 → 2025-02-28 是整一年', () {
      final c = computeCountdown(DateTime(2024, 2, 28, 10), DateTime(2025, 2, 28, 10));
      expect(c.years, 1);
      expect(c.days, 0);
    });

    test('整一年差一天时不能算成一年', () {
      final c = computeCountdown(DateTime(2026, 9, 28, 12), DateTime(2027, 9, 28, 11, 59));
      expect(c.years, 0);
      expect(c.days, 364);
    });

    test('纯天数', () {
      final c = computeCountdown(DateTime(2026, 9, 28, 9), DateTime(2026, 10, 1, 9));
      expect(c.years, 0);
      expect(c.days, 3);
      expect(c.totalDays, 3);
    });

    test('时分秒', () {
      final c = computeCountdown(DateTime(2026, 9, 28), DateTime(2026, 9, 28, 1, 2, 3));
      expect(c.hours, 1);
      expect(c.minutes, 2);
      expect(c.seconds, 3);
    });

    test('已到期', () {
      final c = computeCountdown(DateTime(2026, 9, 28), DateTime(2026, 9, 27));
      expect(c.expired, isTrue);
      expect(c.compact, '已到期');
      expect(c.totalSeconds, 0);
    });

    test('进度百分比', () {
      final c = computeCountdown(DateTime(2025, 1, 1), DateTime(2026, 1, 1), start: DateTime(2020, 1, 1));
      expect(c.percentElapsed, closeTo(5 / 6, 0.001));
    });

    test('日历天数差不被时分秒影响（夏令时/跨日边界）', () {
      expect(calendarDaysBetween(DateTime(2026, 9, 28, 23, 59), DateTime(2026, 9, 29, 0, 1)), 1);
      expect(calendarDaysBetween(DateTime(2026, 9, 28, 0, 1), DateTime(2026, 9, 28, 23, 59)), 0);
    });

    test('compact 文案', () {
      final c = computeCountdown(DateTime(2026, 9, 28), DateTime(2027, 9, 30, 4, 5, 6));
      expect(c.compact, '1 年 2 天 04:05:06');
    });

    test('不足一年时只显示天', () {
      final c = computeCountdown(DateTime(2026, 9, 28, 1), DateTime(2026, 9, 30, 2, 3, 4));
      expect(c.compact, '2 天 01:03:04');
    });
  });
}
