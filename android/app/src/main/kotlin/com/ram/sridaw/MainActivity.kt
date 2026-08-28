package com.ram.sridaw

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            System.loadLibrary("sridaw_juce")
            initJuceJNI(this)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    external fun initJuceJNI(context: Any)
}
