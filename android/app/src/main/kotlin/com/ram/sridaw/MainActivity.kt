package com.ram.sridaw

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.FileWriter

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ram.sridaw/assets").setMethodCallHandler { call, result ->
            if (call.method == "extractSoundFont") {
                try {
                    val sfName = "soundfonts/GeneralUser-GS.sf2"
                    val outFile = File(context.cacheDir, "GeneralUser-GS.sf2")
                    if (!outFile.exists()) {
                        val inputStream = context.assets.open(sfName)
                        val outputStream = FileOutputStream(outFile)
                        inputStream.copyTo(outputStream)
                        inputStream.close()
                        outputStream.close()
                    }
                    result.success(outFile.absolutePath)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

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
        val t0 = System.currentTimeMillis()
        try {
            super.onCreate(savedInstanceState)
            log("onCreate: loading libsridaw_juce.so")
            val tLib = System.currentTimeMillis()
            System.loadLibrary("sridaw_juce")
            juceLibraryLoaded = true
            log("onCreate: libsridaw_juce.so loaded OK (${System.currentTimeMillis() - tLib} ms)")

            // Required: resolves JUCE's JNI class/field/method IDs (and the
            // embedded Android MIDI support) before the audio engine uses them.
            val tJni = System.currentTimeMillis()
            initJuceJNI(this)
            juceInitialised = true
            log("onCreate: initJuceJNI OK (${System.currentTimeMillis() - tJni} ms)")
            log("onCreate: total (${System.currentTimeMillis() - t0} ms)")
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
