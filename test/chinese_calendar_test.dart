import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/core/chinese_calendar.dart';

/// 农历/节假日是算出来的，不是编的；这些日期都用 lunar 库实测核对过。
void main() {
  group('农历与节日', () {
    test('2026-09-29 是农历八月十九', () {
      final cn = ChineseDay.of(DateTime(2026, 9, 29));
      expect(cn.lunarShort, '十九');
      expect(cn.lunarFull, contains('八月'));
      expect(cn.detailLine, contains('八月十九'));
    });

    test('节气：2026-04-05 清明', () {
      final cn = ChineseDay.of(DateTime(2026, 4, 5));
      expect(cn.jieQi, '清明');
      expect(cn.cellLabel, '清明', reason: '没有节日时格子里应显示节气');
    });

    test('传统节日：2026-09-25 中秋', () {
      final cn = ChineseDay.of(DateTime(2026, 9, 25));
      expect(cn.festivals, contains('中秋节'));
      expect(cn.isFestival, isTrue);
      expect(cn.cellLabel, '中秋节');
      expect(cn.greeting, isNotNull, reason: '中秋应该有祝福文案');
    });

    test('公历节日：元旦 / 国庆', () {
      expect(ChineseDay.of(DateTime(2026, 1, 1)).festivals, contains('元旦节'));
      expect(ChineseDay.of(DateTime(2026, 10, 1)).festivals, contains('国庆节'));
    });

    test('农历十五那天 lunarShort 是十五，初一显示月份', () {
      expect(ChineseDay.of(DateTime(2026, 9, 25)).lunarShort, '十五');
      expect(ChineseDay.of(DateTime(2026, 2, 17)).lunarShort, '正月', reason: '初一显示"正月"更好认');
    });
  });

  group('法定节假日', () {
    test('2026 的数据表有：国庆放假、劳动节放假', () {
      final national = ChineseDay.of(DateTime(2026, 10, 1));
      expect(national.statutory, isNotNull);
      expect(national.isStatutoryRest, isTrue);

      final labour = ChineseDay.of(DateTime(2026, 5, 1));
      expect(labour.statutory, isNotNull);
    });

    test('数据表没覆盖到的年份不能崩，也不能瞎猜', () {
      // 法定节假日表是按年硬编码的，2027 年还没进包
      final future = ChineseDay.of(DateTime(2027, 2, 6)); // 2027 春节
      expect(future.festivals, contains('春节'), reason: '农历节日照样能算');
      expect(future.statutory, isNull, reason: '没有数据就不显示，不能编');
      expect(future.isStatutoryRest, isFalse);
    });

    test('休息日判断：法定休算休，周末算休', () {
      expect(ChineseDay.of(DateTime(2026, 10, 3)).isRestDay, isTrue, reason: '国庆假期里');
      expect(ChineseDay.of(DateTime(2026, 9, 26)).isRestDay, isTrue, reason: '2026-09-26 是周六');
      expect(ChineseDay.of(DateTime(2026, 9, 29)).isRestDay, isFalse, reason: '周二，普通工作日');
    });
  });

  group('宜忌与文案', () {
    test('宜忌有内容（黄历数据在包里）', () {
      final cn = ChineseDay.of(DateTime(2026, 9, 29));
      expect(cn.yi, isNotEmpty);
      expect(cn.ji, isNotEmpty);
    });

    test('不是节日的日子没有祝福文案', () {
      expect(ChineseDay.of(DateTime(2026, 9, 29)).greeting, isNull);
    });

    test('祝福文案覆盖了主要节日', () {
      for (final f in ['春节', '中秋节', '元旦', '国庆节', '端午', '清明']) {
        expect(kFestivalGreetings.keys.any((k) => k.contains(f) || f.contains(k)), isTrue,
            reason: '$f 应该有祝福文案');
      }
    });
  });
}
