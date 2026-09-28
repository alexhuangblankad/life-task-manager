/// 极简 front-matter 读写。
///
/// 文件格式（Markdown + YAML 头部，Obsidian 兼容）：
///
///     ---
///     id: n-8f2k1
///     type: 日记
///     date: 2026-09-28
///     ---
///
///     正文……
///
/// 只负责「我们自己字段」的读写，用户手写的内容原样保留。
library;

import 'package:yaml/yaml.dart';

const String _fence = '---';

class FrontMatterDoc {
  const FrontMatterDoc(this.data, this.body);

  /// 头部字段（没有头部时为空 Map）
  final Map<String, dynamic> data;

  /// 去掉头部之后的正文（不含前导空行）
  final String body;
}

/// 解析文件开头的 front-matter 区块。
FrontMatterDoc parseFrontMatter(String content) {
  final text = content.startsWith('\ufeff') ? content.substring(1) : content;
  if (!text.startsWith('$_fence\n') && text.trimRight() != _fence) {
    // 也允许开头是 "---\r\n"（Windows 换行）
    if (!text.startsWith('$_fence\r\n')) {
      return FrontMatterDoc(const {}, _stripLeadingNewlines(text));
    }
  }

  final lines = text.split('\n');
  var end = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trimRight() == _fence || lines[i].trimRight() == '$_fence\r') {
      end = i;
      break;
    }
  }
  if (end < 0) {
    return FrontMatterDoc(const {}, _stripLeadingNewlines(text));
  }

  final yamlText = lines.sublist(1, end).join('\n');
  Map<String, dynamic> data = const {};
  final loaded = loadYaml(yamlText);
  if (loaded is YamlMap) {
    data = _toPlainMap(loaded);
  } else if (loaded is Map) {
    data = _toPlainMap(loaded);
  }
  return FrontMatterDoc(data, _stripLeadingNewlines(lines.sublist(end + 1).join('\n')));
}

/// 把 front-matter + 正文拼回文件内容。
String buildFrontMatter(Map<String, dynamic> data, String body) {
  final buf = StringBuffer();
  if (data.isNotEmpty) {
    buf.writeln(_fence);
    for (final key in _sortedKeys(data.keys)) {
      final value = data[key];
      if (value == null) continue;
      buf.writeln('$key: ${_encodeScalar(value)}');
    }
    buf.writeln(_fence);
    buf.writeln();
  }
  buf.write(body);
  return buf.toString();
}

/// 保留用户原有字段的前提下，覆盖/追加我们管理的字段。
String upsertFrontMatter(String content, Map<String, dynamic> patch) {
  final doc = parseFrontMatter(content);
  final merged = <String, dynamic>{...doc.data, ...patch};
  for (final entry in patch.entries) {
    if (entry.value == null) merged.remove(entry.key);
  }
  return buildFrontMatter(merged, doc.body);
}

String _encodeScalar(dynamic value) {
  if (value is List) {
    return '[${value.map(_encodeScalar).join(', ')}]';
  }
  final s = value.toString();
  if (s.isEmpty) return "''";
  final needsQuote = RegExp(r'^[\s\[{&*#?|<>=!%@`"' + "'" + r']').hasMatch(s) ||
      s.contains(': ') ||
      s.endsWith(':') ||
      s.contains('#') ||
      s != s.trim();
  if (!needsQuote) return s;
  return '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

Iterable<String> _sortedKeys(Iterable<String> keys) {
  // 固定顺序，保证同一次修改产生的 diff 最小
  const order = ['id', 'type', 'title', 'date', 'task', 'task_title', 'subtask', 'mood', 'tags', 'deadline', 'created'];
  final list = keys.toList();
  list.sort((a, b) {
    final ia = order.indexOf(a);
    final ib = order.indexOf(b);
    if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
    if (ia >= 0) return -1;
    if (ib >= 0) return 1;
    return a.compareTo(b);
  });
  return list;
}

Map<String, dynamic> _toPlainMap(Map<dynamic, dynamic> map) {
  final out = <String, dynamic>{};
  map.forEach((k, v) {
    if (v == null) return;
    if (v is List) {
      out[k.toString()] = v.map((e) => e?.toString() ?? '').toList();
    } else if (v is Map) {
      out[k.toString()] = _toPlainMap(v);
    } else {
      out[k.toString()] = v;
    }
  });
  return out;
}

String _stripLeadingNewlines(String s) {
  var i = 0;
  while (i < s.length && (s[i] == '\n' || s[i] == '\r')) {
    i++;
  }
  return s.substring(i);
}
