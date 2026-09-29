/// 应用信息（版本号只在这一个地方写，关于页和后续更新检查都读它）
library;

const String kAppName = '人生任务管理器';
const String kAppVersion = '1.1.3';
const String kAppRepoUrl = 'https://github.com/alexhuangblankad/life-task-manager';
const String kAppTagline = '人生倒计时 · 日历 · 待办 · 杂记';
const String kAppLicense = 'MIT 开源许可';

/// 这一版改了什么（关于页直接列出来，省得用户去翻仓库）
const List<String> kAppChangelog = [
  '日历：日期数字对齐到同一水平线（不再被农历小字顶得高低不一）',
  '日历：表格底部给小圆点留出位置，不再压住农历/节日小字',
  '日历：长节日名（如全民国防教育日）截断显示，日期数字不再被挤小',
  '日历：PC 上每格加高一点，看着不那么挤',
  '设置：数据位置可以用系统文件夹选择框挑（不用手打路径）',
  '（v1.1.2）日历手机端改上下布局、整页一起滚；页头月份与箭头严格居中',
  '（v1.1.1）修安卓启动卡死/配置存不下来；适配刘海屏；通知走系统闹钟',
];
