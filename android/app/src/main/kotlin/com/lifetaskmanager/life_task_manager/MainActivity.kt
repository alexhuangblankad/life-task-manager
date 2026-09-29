package com.lifetaskmanager.life_task_manager

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 让 Flutter 的视图铺满整个窗口（包括状态栏/刘海那块）。
        // 不开的话，状态栏区域显示的是安卓主题的窗口底色 ——
        // 手机系统是浅色、App 内选了深色主题时，顶上就会露出一条白带（很丑）。
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }
}
