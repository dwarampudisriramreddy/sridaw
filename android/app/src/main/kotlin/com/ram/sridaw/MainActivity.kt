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

        // Guard so JUCE is initialised exactly once (it must not be called twice).
        @Volatile
        private var juceInitialised: Boolean = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            super.onCreate(savedInstanceState)
            log("onCreate: loading libsridaw_juce.so")
            System.loadLibrary("sridaw_juce")
            juceLibraryLoaded = true
            log("onCreate: libsridaw_juce.so loaded OK")

            // Required: resolves JUCE's JNI class/field/method IDs (and the
            // embedded Android MIDI support) before the audio engine uses them.
            initJuceJNI(this)
            juceInitialised = true
            log("onCreate: initJuceJNI OK")
        } catch (e: Throwable) {
            // Never let a native library load failure kill the app at startup.
            // The Dart side (AudioEngineBridge) reports the real error via FFI.
            log("onCreate: JUCE init FAILED - $e")
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

    external fun initJuceJNI(context: Any)
}
