// IMPORTANT: Must be defined BEFORE any JUCE header is included. On Android,
// this makes juce_core.h pull in juce_JNIHelpers_android.h so that
// JNIClassBase is visible to this translation unit.
#if JUCE_ANDROID
#ifndef JUCE_CORE_INCLUDE_JNI_HELPERS
#define JUCE_CORE_INCLUDE_JNI_HELPERS 1
#endif
#endif

#include "audio_engine.h"

#if JUCE_ANDROID
#include <jni.h>
extern "C" JNIEXPORT void JNICALL
Java_com_ram_sridaw_MainActivity_initJuceJNI(JNIEnv* env, jobject thiz, jobject context) {
    // This host app is a Flutter app, NOT a Projucer-generated app, so the JUCE
    // Java class (com/rmsl/juce/Java) that normally triggers JNI class
    // initialisation is absent from the APK. Without initialiseAllClasses(), all
    // JNIClassBase method IDs (e.g. JuceMidiSupport.getAndroidMidiDeviceManager)
    // stay null, which makes JUCE's Android MIDI manager abort with
    // "JNI DETECTED ERROR: mid == null". Replicate what juce_JavainitialiseJUCE
    // does so the embedded JUCE Java bytecode classes are resolved.
    JNIClassBase::initialiseAllClasses(env, context);
    juce::Thread::initialiseJUCE(env, context);
}
#endif

#ifdef _WIN32
#define FFI_EXPORT __declspec(dllexport)
#else
#define FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

static std::unique_ptr<AudioEngine> gAudioEngine = nullptr;

extern "C" {

FFI_EXPORT bool initJuceEngine() {
    if (!gAudioEngine) {
        gAudioEngine = std::make_unique<AudioEngine>();
    }
    return gAudioEngine->initialize();
}

FFI_EXPORT void shutdownJuceEngine() {
    if (gAudioEngine) {
        gAudioEngine->shutdown();
        gAudioEngine.reset();
    }
}

FFI_EXPORT void setEngineVolume(float volume) {
    if (gAudioEngine) gAudioEngine->setMasterVolume(volume);
}

FFI_EXPORT float getEngineVolume() {
    if (gAudioEngine) return gAudioEngine->getMasterVolume();
    return 0.0f;
}

FFI_EXPORT void setTrackVolume(int index, float volume) {
    if (gAudioEngine) gAudioEngine->setTrackVolume(index, volume);
}

FFI_EXPORT void setTrackMute(int index, bool mute) {
    if (gAudioEngine) gAudioEngine->setTrackMute(index, mute);
}

FFI_EXPORT void setTrackSolo(int index, bool solo) {
    if (gAudioEngine) gAudioEngine->setTrackSolo(index, solo);
}

FFI_EXPORT void setTrackPan(int index, float pan) {
    if (gAudioEngine) gAudioEngine->setTrackPan(index, pan);
}

FFI_EXPORT float getTrackPeakLevel(int index) {
    if (gAudioEngine) return gAudioEngine->getTrackPeakLevel(index);
    return 0.0f;
}

FFI_EXPORT void playDemo(bool play) {
    if (gAudioEngine) gAudioEngine->playDemo(play);
}

FFI_EXPORT bool loadMidiFile(const char* path) {
    if (gAudioEngine && path) {
        return gAudioEngine->loadMidiFile(juce::String(path));
    }
    return false;
}

FFI_EXPORT bool loadTrackSample(int trackIndex, const char* path) {
    if (gAudioEngine && path) {
        return gAudioEngine->loadTrackSample(trackIndex, juce::String(path));
    }
    return false;
}

FFI_EXPORT void clearMidiSequence() {
    if (gAudioEngine) gAudioEngine->clearMidiSequence();
}

FFI_EXPORT void addMidiNote(int noteNumber, double startSeconds, double durationSeconds, float velocity) {
    if (gAudioEngine) gAudioEngine->addMidiNote(noteNumber, startSeconds, durationSeconds, velocity);
}

FFI_EXPORT void setLoopDuration(double loopSeconds) {
    if (gAudioEngine) gAudioEngine->setLoopDuration(loopSeconds);
}

FFI_EXPORT double getPlayheadTime() {
    if (gAudioEngine) return gAudioEngine->getPlayheadTime();
    return 0.0;
}

} // extern "C"
