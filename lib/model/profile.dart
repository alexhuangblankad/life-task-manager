/// 「人生期限」配置 —— 倒计时的数据源，存在 vault 里所以能跟着同步。
library;

import '../model/task.dart' show parseDate, formatDate;

class Profile {
  const Profile({
    this.name = '',
    this.birthDate,
    this.lifeExpectancyYears = 80,
    this.targetDate,
    this.showSeconds = true,
    this.lifeCountdownEnabled = true,
  });

  final String name;

  /// 出生日期
  final DateTime? birthDate;

  /// 预期寿命（年）
  final int lifeExpectancyYears;

  /// 直接指定终点日期；填了就以它为准（优先级高于「出生日期+寿命」）
  final DateTime? targetDate;

  /// 是否显示到「秒」
  final bool showSeconds;

  /// 人生倒计时总开关（不想每天被吓可以让它闭嘴，只留大任务 deadline）
  final bool lifeCountdownEnabled;

  /// 实际使用的终点时刻：终点当天 23:59:59
  DateTime? get lifeTarget {
    final base = targetDate ?? _fromExpectancy();
    if (base == null) return null;
    return DateTime(base.year, base.month, base.day, 23, 59, 59);
  }

  /// 起点（用来算进度百分比）
  DateTime? get lifeStart =>
      targetDate != null ? null : (birthDate == null ? null : DateTime(birthDate!.year, birthDate!.month, birthDate!.day));

  DateTime? _fromExpectancy() {
    final b = birthDate;
    if (b == null) return null;
    return DateTime(b.year + lifeExpectancyYears, b.month, b.day, 23, 59, 59);
  }

  bool get configured => lifeTarget != null;

  Profile copyWith({
    String? name,
    DateTime? birthDate,
    bool clearBirthDate = false,
    int? lifeExpectancyYears,
    DateTime? targetDate,
    bool clearTargetDate = false,
    bool? showSeconds,
    bool? lifeCountdownEnabled,
  }) =>
      Profile(
        name: name ?? this.name,
        birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate),
        lifeExpectancyYears: lifeExpectancyYears ?? this.lifeExpectancyYears,
        targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
        showSeconds: showSeconds ?? this.showSeconds,
        lifeCountdownEnabled: lifeCountdownEnabled ?? this.lifeCountdownEnabled,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'name': name,
        'birth_date': birthDate == null ? null : formatDate(birthDate!),
        'life_expectancy_years': lifeExpectancyYears,
        'target_date': targetDate == null ? null : formatDate(targetDate!),
        'show_seconds': showSeconds,
        'life_countdown_enabled': lifeCountdownEnabled,
      };

  static Profile fromJson(Map<String, dynamic> json) => Profile(
        name: (json['name'] ?? '').toString(),
        birthDate: parseDate(json['birth_date']),
        lifeExpectancyYears: _asInt(json['life_expectancy_years'], 80),
        targetDate: parseDate(json['target_date']),
        showSeconds: json['show_seconds'] is bool ? json['show_seconds'] as bool : true,
        lifeCountdownEnabled:
            json['life_countdown_enabled'] is bool ? json['life_countdown_enabled'] as bool : true,
      );
}

int _asInt(Object? v, int fallback) {
  if (v is int) return v;
  if (v == null) return fallback;
  return int.tryParse(v.toString()) ?? fallback;
}
