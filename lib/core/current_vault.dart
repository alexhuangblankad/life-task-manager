/// 当前 vault 的绝对路径（进程内全局，只有一份）。
///
/// 为什么要它：杂记里插的图存成**相对 vault 的路径**（`附件/202609/xxx.png`），
/// 渲染时得知道 vault 在哪才能拼出绝对路径。渲染 Markdown 的地方很多
/// （杂记、日记、编辑器的实时预览、报告……），一路把路径当参数传下去既啰嗦
/// 又容易漏，所以这里存一份「当前是哪个 vault」。
///
/// 由 AppState 在 bootstrap / 切换数据位置时写入。
library;

import 'dart:convert';

class CurrentVault {
  static String root = '';

  /// 把 vault 相对路径（也可以是绝对路径、file:// URI）换成磁盘绝对路径。
  /// [raw] 不是本地路径（http、data: 之类）时返回 null。
  static String? resolve(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('file:')) {
      final u = Uri.tryParse(s);
      if (u == null) return null;
      s = u.toFilePath();
    }
    if (s.startsWith('http://') || s.startsWith('https://') || s.startsWith('data:')) return null;

    // Markdown 里的中文/空格路径常常是百分号编码过的（flutter_markdown 交给
    // imageBuilder 的就是编码后的 Uri），先解回来。
    s = _percentDecode(s);

    final normalized = s.replaceAll('\\', '/');
    // Windows 盘符（C:/…）或 Unix 绝对路径：本来就是绝对路径，直接用
    if (RegExp(r'^[A-Za-z]:/').hasMatch(normalized) || normalized.startsWith('//')) {
      return normalized;
    }
    if (root.isEmpty) return null;
    final base = root.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    final rel = normalized.replaceAll(RegExp(r'^\.?/+'), '');
    if (rel.startsWith('/')) return rel;
    return '$base/$rel';
  }

  /// 宽容的百分号解码：解得出多少解多少，坏序列原样留着（不要抛异常）。
  ///
  /// 不用 `Uri.decodeComponent`：它碰到字符串里混着中文就直接抛
  /// `Illegal percent encoding in URI`，整条路径就废了。
  static String _percentDecode(String s) {
    if (!s.contains('%')) return s;
    final bytes = <int>[];
    var i = 0;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x25 && i + 2 < s.length) {
        final v = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
        if (v != null) {
          bytes.add(v);
          i += 3;
          continue;
        }
      }
      bytes.addAll(utf8.encode(String.fromCharCode(c)));
      i++;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
