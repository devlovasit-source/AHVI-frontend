package com.example.myapp

import android.graphics.Color
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode

class MainActivity : FlutterActivity() {
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.opaque

    override fun onCreate(savedInstanceState: Bundle?) {
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(Color.BLACK))
        super.onCreate(savedInstanceState)

        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.setDimAmount(0f)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
    }
}
