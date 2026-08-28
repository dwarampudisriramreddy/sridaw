#include "audio_engine.h"
#include <juce_core/juce_core.h>

#if JUCE_ANDROID
#include <jni.h>
extern "C" JNIEXPORT void JNICALL
Java_com_ram_sridaw_MainActivity_initJuceJNI(JNIEnv* env, jobject thiz, jobject context) {
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
