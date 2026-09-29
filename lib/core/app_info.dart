/// 应用信息（版本号只在这一个地方写，关于页和后续更新检查都读它）
library;

const String kAppName = '人生任务管理器';
const String kAppVersion = '1.1.4';
const String kAppRepoUrl = 'https://github.com/alexhuangblankad/life-task-manager';
const String kAppTagline = '人生倒计时 · 日历 · 待办 · 杂记';
const String kAppLicense = 'MIT 开源许可';

/// 这一版改了什么（关于页直接列出来，省得用户去翻仓库）
const List<String> kAppChangelog = [
  '修：关窗口缩到托盘后，再点桌面图标会开新进程 —— 现在会把已有窗口叫回来',
  '修：手机上新建大任务/小任务时「创建」按钮被挤出屏幕外点不到',
  '修：新建任务失败时界面毫无反应 —— 现在会弹出具体错误',
  '（1.1.3）日历：日期数字对齐、小圆点不再压农历、长节日名不再挤小数字',
  '（1.1.3）数据位置可以用系统文件夹选择框挑',
  '（1.1.2）日历手机端改上下布局、整页一起滚；月份与箭头严格居中',
  '（1.1.1）修安卓启动卡死/配置存不下来；适配刘海屏；通知走系统闹钟',
];
