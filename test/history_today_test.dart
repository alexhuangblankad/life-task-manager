import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/core/history_today.dart';

/// 「历史上的今天」的数据是打包在 assets 里的（来源：百度百科，见 tool/fetch_history.py）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('数据完整性：365 天都有内容，且洗掉了 HTML 标签', () async {
    final h = await HistoryToday.load();
    expect(h.days.length, 365, reason: '一年 365 天都应收录');
    expect(h.source, isNotEmpty, reason: '要能显示数据来源');

    // 闰日不在数据里也不能崩
    expect(h.of(DateTime(2024, 2, 29)), isEmpty);

    var htmlLeft = 0;
    for (final list in h.days.values) {
      for (final e in list) {
        if (e.title.contains('<') || e.desc.contains('<')) htmlLeft++;
      }
    }
    expect(htmlLeft, 0, reason: '打包时就该把 <a> 之类的标签洗掉');
  });

  test('取某一天能拿到条目', () async {
    final h = await HistoryToday.load();
    final events = h.of(DateTime(2026, 9, 29));
    expect(events, isNotEmpty);
    for (final e in events) {
      expect(e.year, isNotEmpty);
      expect(e.title, isNotEmpty);
    }
  });

  test('keyOf 用 MM-DD，个位数月份要补零', () {
    expect(HistoryToday.keyOf(DateTime(2026, 1, 5)), '01-05');
    expect(HistoryToday.keyOf(DateTime(2026, 12, 31)), '12-31');
  });

  test('越界日期不能崩（DateTime 会自己归一化）', () async {
    final h = await HistoryToday.load();
    expect(() => h.of(DateTime(2026, 13, 40)), returnsNormally);
    expect(() => h.has(DateTime(1999, 1, 1)), returnsNormally);
  });
}
