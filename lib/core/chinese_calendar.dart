/// 中文日历信息：农历、节气、传统节日、法定节假日、宜忌。
///
/// 数据来自 `lunar` 包（6tail 的 lunar-javascript 的 Dart 版），纯本地计算，不联网。
///
/// ⚠️ **法定节假日的数据表是按年硬编码在包里的**，每年国务院公布次年安排后才更新。
/// 实测包内覆盖到 2026 年；2027 年及以后 `HolidayUtil` 会返回 null，
/// 这时界面只显示农历/节日，不显示"休/班"，不会报错也不会瞎猜。
library;

import 'package:lunar/lunar.dart';

class ChineseDay {
  ChineseDay._({
    required this.lunarShort,
    required this.lunarFull,
    required this.ganzhiDay,
    required this.jieQi,
    required this.festivals,
    required this.statutory,
    required this.isAdjustedWorkday,
    required this.isWeekend,
    Lunar? lunar,
  }) : _lunar = lunar;

  final Lunar? _lunar;

  // 宜忌是这批计算里最贵的（要算二十八宿那一套），所以做成按需 + 只算一次
  List<String>? _yi;
  List<String>? _ji;

  List<String> get yi => _yi ??= _lunar?.getDayYi() ?? const [];
  List<String> get ji => _ji ??= _lunar?.getDayJi() ?? const [];

  // ─────────────── 缓存：日历一个月有 42 个格子，每次都重算会卡 ───────────────

  static final Map<String, ChineseDay> _cache = {};

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// 八月十九 / 八月（初一）
  final String lunarShort;

  /// 二〇二六年八月十九
  final String lunarFull;

  /// 丙午年 日干支
  final String ganzhiDay;

  /// 节气（当天不是节气则为空串）
  final String jieQi;

  /// 当天节日（农历 + 公历的主要节日）
  final List<String> festivals;
  /// 法定节假日名称（这天放假）；数据表没有这一年时为 null
  final String? statutory;

  /// 调休上班（周末但是工作日）
  final bool isAdjustedWorkday;

  final bool isWeekend;

  bool get isFestival => festivals.isNotEmpty;

  /// 法定休：有节假日记录且不是"调休上班"
  bool get isStatutoryRest => statutory != null && !isAdjustedWorkday;

  /// 实际休息日：法定休，或者周末且不是调休上班
  bool get isRestDay => isStatutoryRest || (isWeekend && !isAdjustedWorkday);

  /// 日历格子里显示的那行小字：节日 > 节气 > 农历日
  String get cellLabel {
    if (festivals.isNotEmpty) return festivals.first;
    if (statutory != null && isAdjustedWorkday) return '班';
    if (jieQi.isNotEmpty) return jieQi;
    return lunarShort;
  }

  /// 详情页那行：二〇二六年八月十九 · 丙午年 · 宜祭祀
  String get detailLine {
    final parts = <String>[lunarFull];
    if (jieQi.isNotEmpty) parts.add(jieQi);
    if (statutory != null) parts.add(isAdjustedWorkday ? '$statutory·调休上班' : '$statutory·放假');
    return parts.join(' · ');
  }

  /// 节日祝福（只对几个大节日给一句，没有就 null）
  String? get greeting {
    for (final f in festivals) {
      final g = kFestivalGreetings[f];
      if (g != null) return g;
    }
    for (final f in festivals) {
      for (final entry in kFestivalGreetings.entries) {
        if (f.contains(entry.key) || entry.key.contains(f)) return entry.value;
      }
    }
    if (statutory != null && !isAdjustedWorkday) {
      return kFestivalGreetings[statutory!];
    }
    return null;
  }

  /// 取某天的农历信息（带缓存：同一个日期只算一次，日历翻页不再卡）
  static ChineseDay of(DateTime day) {
    final key = _key(day);
    final hit = _cache[key];
    if (hit != null) return hit;

    final solar = Solar.fromYmd(day.year, day.month, day.day);
    final lunar = solar.getLunar();

    final festivals = <String>[
      ...lunar.getFestivals(),
      ...solar.getFestivals(),
    ];

    Holiday? holiday;
    try {
      holiday = HolidayUtil.getHoliday(
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      );
    } catch (_) {
      holiday = null;
    }

    final dayCn = lunar.getDayInChinese();
    final result = ChineseDay._(
      lunarShort: dayCn == '初一' ? '${lunar.getMonthInChinese()}月' : dayCn,
      lunarFull: '${lunar.getYearInChinese()}年${lunar.getMonthInChinese()}月$dayCn',
      ganzhiDay: '${lunar.getYearInGanZhi()}年 ${lunar.getMonthInGanZhi()}月 ${lunar.getDayInGanZhi()}日',
      jieQi: lunar.getJieQi(),
      festivals: festivals,
      statutory: holiday?.getName(),
      isAdjustedWorkday: holiday?.isWork() ?? false,
      isWeekend: day.weekday >= 6,
      lunar: lunar,
    );

    // 缓存别无限涨（翻个几年也就几百天）
    if (_cache.length > 1200) _cache.clear();
    _cache[key] = result;
    return result;
  }
}

/// 节日祝福文案（自己写的白话，不是抄的模板）
const Map<String, String> kFestivalGreetings = {
  '春节': '一年里最热闹的几天，愿你被家人围着，饭菜是热的。',
  '除夕': '旧的一年到这儿了。明年见。',
  '元宵节': '今晚月亮最圆，汤圆记得吃两颗。',
  '元宵': '今晚月亮最圆，汤圆记得吃两颗。',
  '清明节': '清明时节，去看看该看的人。',
  '端午': '粽子里包的是想念，艾草挂着的是平安。',
  '端午节': '粽子里包的是想念，艾草挂着的是平安。',
  '七夕': '今天适合想一个人。',
  '七夕节': '今天适合想一个人。',
  '中秋节': '月亮圆了，人也该聚了。',
  '重阳节': '登高望远，顺便给家里打个电话。',
  '腊八节': '一碗腊八粥，年味就开始了。',
  '小年': '该扫房子了。',
  '中元节': '今天早点回家。',
  '冬至': '冬至大如年，饺子汤圆别落下。',
  '元旦': '新的一年，第一天。',
  '元旦节': '新的一年，第一天。',
  '劳动节': '歇一天，你值得。',
  '国庆节': '出去走走，或者在家躺着，都挺好。',
  '儿童节': '心里那个小孩，今天可以出来玩。',
  '教师节': '记得跟教过你的人说声谢谢。',
  '母亲节': '给妈妈打个电话。',
  '父亲节': '给爸爸打个电话。',
  '情人节': '有人的话，说点好听的。',
  '圣诞节': '不需要理由，今天开心就行。',
  '感恩节': '想想要谢谢谁。',
  '妇女节': '今天属于她们。',
  '植树节': '种点什么，哪怕只是一盆绿萝。',
};
