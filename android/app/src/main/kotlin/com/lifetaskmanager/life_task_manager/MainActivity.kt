package com.lifetaskmanager.life_task_manager

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 必须在 super.onCreate **之后**调：
        // 之前放在前面，被 Flutter 自己的初始化覆盖了，状态栏那块仍然是
        // 安卓主题的窗口底色（系统浅色 + App 暗色时就是一条白带）。
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // 状态栏/导航栏都透明，让应用自己画到刘海/挖孔区域下面
        @Suppress("DEPRECATION")
        run {
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }
}
