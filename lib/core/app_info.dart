/// 应用信息（版本号只在这一个地方写，关于页和后续更新检查都读它）
library;

const String kAppName = '人生任务管理器';
const String kAppVersion = '1.1.1';
const String kAppRepoUrl = 'https://github.com/alexhuangblankad/life-task-manager';
const String kAppTagline = '人生倒计时 · 日历 · 待办 · 杂记';
const String kAppLicense = 'MIT 开源许可';

/// 这一版改了什么（关于页直接列出来，省得用户去翻仓库）
const List<String> kAppChangelog = [
  '安卓：修好通知（提前交给系统闹钟，重启后自动重挂）',
  '安卓：修了配置存不下来、启动卡在加载页、界面过慢的问题',
  '安卓：窄屏改成上下布局 + 底部标签栏，适配刘海/挖孔屏',
  '安卓：安装包按 CPU 架构分成三个，体积减半',
  '新增：倒计时页显示最近一期 AI 复盘评分',
  '新增：自定义背景图 + 模糊程度',
  '新增：关窗口可选「缩到托盘 / 直接退出 / 每次问我」',
  '新增：自绘标题栏（去掉系统那条黑杠）',
];
