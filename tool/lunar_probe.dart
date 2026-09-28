/// 农历/节假日数据探针：确认 lunar 包的 API 与数据覆盖范围。
library;

import 'package:lunar/lunar.dart';

void main() {
  final samples = [
    DateTime(2026, 1, 1), // 元旦
    DateTime(2026, 2, 17), // 春节附近
    DateTime(2026, 4, 5), // 清明附近
    DateTime(2026, 5, 1), // 劳动节
    DateTime(2026, 9, 25), // 中秋前后
    DateTime(2026, 9, 29), // 今天
    DateTime(2026, 10, 1), // 国庆
    DateTime(2027, 2, 6), // 明年春节附近
  ];

  for (final d in samples) {
    final solar = Solar.fromYmd(d.year, d.month, d.day);
    final lunar = solar.getLunar();
    final holiday = HolidayUtil.getHoliday(
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    print('${d.year}-${d.month}-${d.day}'
        ' | 农历 ${lunar.getYearInChinese()}年${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}'
        ' | 节气[${lunar.getJieQi()}]'
        ' | 农历节日${lunar.getFestivals()}'
        ' | 公历节日${solar.getFestivals()}${solar.getOtherFestivals()}'
        ' | 法定${holiday == null ? "无" : "${holiday.getName()}(工作日=${holiday.isWork()})"}');
  }

  // 农历十五（中秋）能不能算出来
  print('\n2026 年农历八月十五落在：');
  for (var off = 0; off < 60; off++) {
    final d = DateTime(2026, 9, 1).add(Duration(days: off));
    final l = Solar.fromYmd(d.year, d.month, d.day).getLunar();
    if (l.getMonthInChinese() == '八' && l.getDayInChinese() == '十五') {
      print('  ${d.year}-${d.month}-${d.day}');
    }
  }

  print('\n宜忌示例（今天）：${Solar.fromYmd(2026, 9, 29).getLunar().getDayYi().take(4).toList()}');
}
