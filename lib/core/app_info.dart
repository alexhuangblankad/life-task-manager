/// 应用信息（版本号只在这一个地方写，关于页和后续更新检查都读它）
library;

const String kAppName = '人生任务管理器';
const String kAppVersion = '1.1.6';
const String kAppRepoUrl = 'https://github.com/alexhuangblankad/life-task-manager';
const String kAppTagline = '人生倒计时 · 日历 · 待办 · 杂记';
const String kAppLicense = 'MIT 开源许可';

/// 这一版改了什么（关于页直接列出来，省得用户去翻仓库）
const List<String> kAppChangelog = [
  '修：点桌面图标真的不会再开新进程了（换掉了失效的文件锁方案，实测通过）',
  '（1.1.5）界面铺满窗口，修好安卓顶部那条白带；刘海/挖孔屏适配',
  '修：刘海/挖孔屏适配（shortEdges + 状态栏导航栏透明）',
  '单实例加了诊断日志，方便确认点图标时到底有没有拦住新进程',
  '（1.1.4）点桌面图标不再开新进程；手机新建任务按钮够得着',
  '（1.1.3）日历：数字对齐、圆点不压农历、长节日名不挤数字',
  '（1.1.2）日历手机端上下布局、整页滚动；月份与箭头居中',
  '（1.1.1）修安卓启动卡死/配置存不下来；通知走系统闹钟',
];
