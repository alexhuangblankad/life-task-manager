/// AI 周报/月报的配置：发行商预设 + 用户自己的 key + 周期。
///
/// 存在**设备本地配置**里（%APPDATA%\LifeTaskManager\device.json），
/// 不进 vault —— 因为 vault 会跟着 WebDAV 同步，API Key 上传到云上就是明文泄露。
/// 代价是换一台机器要重新填一次 key，这是故意的。
library;

import 'report_cycle.dart';

/// 一个发行商预设（类似 cc-switch 那种一键切换）
class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    this.needsKey = true,
    this.hint = '',
  });

  final String id;
  final String name;

  /// OpenAI 兼容的根地址（Anthropic 是特例，走 /v1/messages）
  final String baseUrl;
  final String defaultModel;

  /// 本地模型不需要 key
  final bool needsKey;

  /// 申请 key 的地方 / 备注
  final String hint;

  bool get isAnthropic => id == 'anthropic';
}

/// 内置的发行商。都是 OpenAI 兼容接口（智谱 v4 / 百炼 compatible-mode 都兼容）。
const List<AiProvider> kAiProviders = [
  AiProvider(
    id: 'deepseek',
    name: 'DeepSeek 深度求索',
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    hint: '便宜好用，中文好。platform.deepseek.com 申请 key',
  ),
  AiProvider(
    id: 'qwen',
    name: '阿里云百炼（通义千问）',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-plus',
    hint: 'bailian.console.aliyun.com 申请 key，有免费额度',
  ),
  AiProvider(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-4-flash',
    hint: 'glm-4-flash 有免费额度，open.bigmodel.cn',
  ),
  AiProvider(
    id: 'moonshot',
    name: '月之暗面 Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: 'moonshot-v1-8k',
    hint: 'platform.moonshot.cn 申请 key',
  ),
  AiProvider(
    id: 'siliconflow',
    name: '硅基流动 SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    defaultModel: 'Qwen/Qwen2.5-7B-Instruct',
    hint: '模型多，有免费小模型。siliconflow.cn',
  ),
  AiProvider(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
    hint: '国内需要能直连的网络环境',
  ),
  AiProvider(
    id: 'anthropic',
    name: 'Anthropic Claude',
    baseUrl: 'https://api.anthropic.com',
    defaultModel: 'claude-3-5-haiku-20241022',
    hint: '接口格式和别人不一样，程序里单独适配了',
  ),
  AiProvider(
    id: 'ollama',
    name: '本机 Ollama（不花钱、不联网）',
    baseUrl: 'http://127.0.0.1:11434/v1',
    defaultModel: 'qwen2.5:7b',
    needsKey: false,
    hint: '先在本机跑起 ollama serve，再 ollama pull 一个模型',
  ),
  AiProvider(
    id: 'custom',
    name: '自定义（OpenAI 兼容）',
    baseUrl: '',
    defaultModel: '',
    hint: '自己填地址和模型名，只要接口是 /chat/completions 就能用',
  ),
];

AiProvider providerById(String id) =>
    kAiProviders.firstWhere((p) => p.id == id, orElse: () => kAiProviders.first);

class AiConfig {
  const AiConfig({
    this.enabled = false,
    this.cycle = const ReportCycle(),
    this.providerId = 'deepseek',
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
    this.autoReport = true,
    this.extraPrompt = '',
  });

  /// 报告总开关
  final bool enabled;

  /// 周期：周报 / 双周报 / 月报 / 季报 / 自定义天数，以及「哪天生成」
  final ReportCycle cycle;

  final String providerId;

  /// 用户的 API Key（只存本机）
  final String apiKey;

  /// 空 = 用发行商默认模型
  final String model;

  /// 空 = 用发行商默认地址
  final String baseUrl;

  /// 每月几号自动生成上一期（月报/季报用，1-28）—— 见 cycle.monthDay

  final bool autoReport;

  /// 附加给模型的额外要求（可空）
  final String extraPrompt;

  AiProvider get provider => providerById(providerId);

  String get effectiveModel => model.trim().isEmpty ? provider.defaultModel : model.trim();

  String get effectiveBaseUrl {
    final b = baseUrl.trim().isEmpty ? provider.baseUrl : baseUrl.trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  /// 配好了没（能不能真的调用）
  bool get ready =>
      enabled &&
      effectiveBaseUrl.isNotEmpty &&
      effectiveModel.isNotEmpty &&
      (!provider.needsKey || apiKey.trim().isNotEmpty);

  AiConfig copyWith({
    bool? enabled,
    ReportCycle? cycle,
    String? providerId,
    String? apiKey,
    String? model,
    String? baseUrl,
    bool? autoReport,
    String? extraPrompt,
  }) =>
      AiConfig(
        enabled: enabled ?? this.enabled,
        cycle: cycle ?? this.cycle,
        providerId: providerId ?? this.providerId,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        autoReport: autoReport ?? this.autoReport,
        extraPrompt: extraPrompt ?? this.extraPrompt,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'unit': cycle.unit.name,
        'custom_days': cycle.customDays,
        'weekday': cycle.weekday,
        'month_day': cycle.monthDay,
        'provider': providerId,
        'api_key': apiKey,
        'model': model,
        'base_url': baseUrl,
        'auto_report': autoReport,
        'extra_prompt': extraPrompt,
      };

  static AiConfig fromJson(Map<String, dynamic> j) => AiConfig(
        enabled: j['enabled'] == true,
        cycle: ReportCycle(
          unit: ReportUnit.fromName(j['unit']?.toString()),
          customDays: int.tryParse((j['custom_days'] ?? '30').toString())?.clamp(1, 365) ?? 30,
          weekday: int.tryParse((j['weekday'] ?? '1').toString())?.clamp(1, 7) ?? 1,
          monthDay: int.tryParse((j['month_day'] ?? j['summary_day'] ?? '1').toString())?.clamp(1, 28) ?? 1,
        ),
        providerId: (j['provider'] ?? 'deepseek').toString(),
        apiKey: (j['api_key'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        baseUrl: (j['base_url'] ?? '').toString(),
        autoReport: j['auto_report'] is bool ? j['auto_report'] as bool : true,
        extraPrompt: (j['extra_prompt'] ?? '').toString(),
      );

  /// 总开关开着没
  bool get anyReportOn => enabled;
}

/// key 打码显示（界面上别把 key 露出来）
String maskKey(String key) {
  final k = key.trim();
  if (k.isEmpty) return '未填';
  if (k.length <= 8) return '${k.substring(0, 2)}****';
  return '${k.substring(0, 4)}****${k.substring(k.length - 4)}';
}
