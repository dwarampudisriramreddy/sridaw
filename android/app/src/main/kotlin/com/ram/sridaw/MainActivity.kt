package com.ram.sridaw

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.util.Log
import java.io.File
import java.io.FileWriter

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "SriDAW"
        private const val LOG_FILE = "sridaw_crash.log"

        // Cache the native library handle so it is loaded exactly once.
        @Volatile
        var juceLibraryLoaded: Boolean = false
            private set
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            super.onCreate(savedInstanceState)
            log("onCreate: loading libsridaw_juce.so")
            System.loadLibrary("sridaw_juce")
            juceLibraryLoaded = true
            log("onCreate: libsridaw_juce.so loaded OK")
        } catch (e: Throwable) {
            // Never let a native library load failure kill the app at startup.
            // The Dart side (AudioEngineBridge) reports the real error via FFI.
            juceLibraryLoaded = false
            log("onCreate: libsridaw_juce.so load FAILED - $e")
        }
    }

    private fun log(msg: String) {
        val line = "[${System.currentTimeMillis()}] $msg\n"
        Log.e(TAG, msg)
        try {
            val f = File(getExternalFilesDir(null), LOG_FILE)
            FileWriter(f, true).use { it.write(line) }
        } catch (io: Throwable) {
            // Logging to file is best-effort only
        }
    }
}
