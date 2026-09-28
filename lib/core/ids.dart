/// 短 ID 生成：给任务和杂记一个稳定、可读、不会撞的标识。
///
/// 不用自增数字（多设备各自新增会撞），不用 UUID（太长，写在 md 行尾难看）。
/// 32 进制 8 位 + 时间前缀，实际撞车概率可以忽略。
library;

import 'dart:math';

const String _alphabet = '0123456789abcdefghjkmnpqrstvwxyz'; // 去掉易混的 i l o u

final Random _random = Random.secure();

/// 生成 8 位随机串。
String randomToken([int length = 8]) {
  final buf = StringBuffer();
  for (var i = 0; i < length; i++) {
    buf.write(_alphabet[_random.nextInt(_alphabet.length)]);
  }
  return buf.toString();
}

/// 大任务 ID：`t-xxxxxxxx`
String newTaskId() => 't-${randomToken()}';

/// 小任务 ID：`s-xxxxxxxx`
String newSubtaskId() => 's-${randomToken(6)}';

/// 杂记 ID：`n-xxxxxxxx`
String newNoteId() => 'n-${randomToken()}';

/// 日程 ID：`e-xxxxxxxx`
String newEventId() => 'e-${randomToken(6)}';
