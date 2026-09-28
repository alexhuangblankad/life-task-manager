/// 调大模型的客户端。只做一件事：给一段提示词，拿回一段文字。
///
/// 支持两种接口：
///   1. OpenAI 兼容（/chat/completions）—— DeepSeek、通义、智谱、Kimi、硅基流动、OpenAI、Ollama、自定义
///   2. Anthropic（/v1/messages）—— 格式不一样，单独适配
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../model/ai_config.dart';

class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LlmClient {
  LlmClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// 超时给宽一点：月报要它写一段有内容的东西，慢的模型要一两分钟
  static const Duration _timeout = Duration(seconds: 150);

  Future<String> chat({
    required AiConfig cfg,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    if (!cfg.ready) {
      throw LlmException('AI 没配置好：检查开关、发行商、API Key');
    }
    return cfg.provider.isAnthropic
        ? _anthropic(cfg, systemPrompt, userPrompt)
        : _openAiCompatible(cfg, systemPrompt, userPrompt);
  }

  Future<String> _openAiCompatible(AiConfig cfg, String system, String user) async {
    final uri = Uri.parse('${cfg.effectiveBaseUrl}/chat/completions');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (cfg.apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${cfg.apiKey.trim()}',
    };
    final body = jsonEncode({
      'model': cfg.effectiveModel,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': 0.4,
      'stream': false,
    });

    final res = await _post(uri, headers, body);
    final json = _decode(_text(res));
    final content = _pick(json, ['choices', 0, 'message', 'content']);
    if (content is! String || content.trim().isEmpty) {
      throw LlmException('模型没返回内容。原始响应：${_short(_text(res))}');
    }
    return content;
  }

  Future<String> _anthropic(AiConfig cfg, String system, String user) async {
    final uri = Uri.parse('${cfg.effectiveBaseUrl}/v1/messages');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': cfg.apiKey.trim(),
      'anthropic-version': '2023-06-01',
    };
    final body = jsonEncode({
      'model': cfg.effectiveModel,
      'max_tokens': 2048,
      'system': system,
      'messages': [
        {'role': 'user', 'content': user},
      ],
    });

    final res = await _post(uri, headers, body);
    final json = _decode(_text(res));
    final blocks = _pick(json, ['content']);
    if (blocks is List) {
      final text = blocks
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => (b['text'] ?? '').toString())
          .join('\n');
      if (text.trim().isNotEmpty) return text;
    }
    throw LlmException('模型没返回内容。原始响应：${_short(_text(res))}');
  }

  Future<http.Response> _post(Uri uri, Map<String, String> headers, String body) async {
    try {
      final res = await _http.post(uri, headers: headers, body: body).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw LlmException(_explain(res.statusCode, _text(res)));
      }
      return res;
    } on LlmException {
      rethrow;
    } on SocketException catch (e) {
      throw LlmException('连不上 ${uri.host}：${e.message}（检查网络/代{理}设置/地址是否写错）');
    } catch (e) {
      throw LlmException('请求失败：$e');
    }
  }

  /// 有些服务端不带 charset，http 包会按 latin1 解 body，中文直接乱码 —— 统一自己按 UTF-8 解。
  static String _text(http.Response res) {
    try {
      return utf8.decode(res.bodyBytes);
    } catch (_) {
      return res.body;
    }
  }

  /// 把常见错误翻译成人话
  String _explain(int code, String body) {
    final detail = _short(body);
    switch (code) {
      case 401:
        return 'API Key 不对或没权限（401）。$detail';
      case 402:
        return '账户余额不足（402）。$detail';
      case 403:
        return '被拒绝（403），可能是 key 权限或地区限制。$detail';
      case 404:
        return '接口地址或模型名不对（404）。$detail';
      case 429:
        return '请求太快或额度用完了（429）。$detail';
    }
    if (code >= 500) return '服务端出错（$code），一般是临时问题，过会儿再试。$detail';
    return 'HTTP $code：$detail';
  }

  static String _short(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= 300 ? t : '${t.substring(0, 300)}…';
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// 安全地按路径取值：['choices', 0, 'message', 'content']
  static Object? _pick(Object? root, List<Object> path) {
    Object? cur = root;
    for (final key in path) {
      if (cur == null) return null;
      if (key is int) {
        if (cur is List && cur.length > key) {
          cur = cur[key];
        } else {
          return null;
        }
      } else if (cur is Map) {
        cur = cur[key];
      } else {
        return null;
      }
    }
    return cur;
  }
}
