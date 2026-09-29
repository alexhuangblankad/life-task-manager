/// 应用信息（版本号只在这一个地方写，关于页和后续更新检查都读它）
library;

const String kAppName = '人生任务管理器';
const String kAppVersion = '1.1.2';
const String kAppRepoUrl = 'https://github.com/alexhuangblankad/life-task-manager';
const String kAppTagline = '人生倒计时 · 日历 · 待办 · 杂记';
const String kAppLicense = 'MIT 开源许可';

/// 这一版改了什么（关于页直接列出来，省得用户去翻仓库）
const List<String> kAppChangelog = [
  '日历（手机）：改成上下布局，整页一起滚，当天日程不再被挤没',
  '日历（手机）：月份和左右箭头严格居中；格子加高，日期不再和农历打架',
  '页头（手机）：按钮自动换行不裁切；窄屏导航收成底部标签栏',
  '安卓：修好通知（提前交给系统闹钟，重启后自动重挂）',
  '安卓：修好配置存不下来、启动卡在加载页、界面过慢',
  '安卓：适配刘海/挖孔屏（状态栏与页面同色，不是一条黑条）',
  '跨端：关窗口可选「缩到托盘 / 直接退出 / 每次问我」',
];
