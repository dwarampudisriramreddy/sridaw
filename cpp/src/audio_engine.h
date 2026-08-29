#pragma once

#include <juce_core/juce_core.h>
#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <memory>
#include <vector>

class GMSynthProcessor; // Forward declaration

struct TrackData {
    float volume = 1.0f;
    float pan = 0.0f;
    bool mute = false;
    bool solo = false;
    float lastPeakLevel = 0.0f;
    
    // For VST / Instrument Hosting (if used in future)
    juce::AudioProcessorGraph::Node::Ptr synthNode;
    juce::AudioProcessorGraph::Node::Ptr gainNode;
};

class AudioEngine : public juce::AudioIODeviceCallback {
public:
    AudioEngine();
    ~AudioEngine();

    bool initialize();
    void shutdown();
    
    void setMasterVolume(float volume);
    float getMasterVolume() const;

    void setTrackVolume(int index, float volume);
    void setTrackMute(int index, bool mute);
    void setTrackSolo(int index, bool solo);
    void setTrackPan(int index, float pan);
    void setTrackInstrument(int index, int program);
    
    float getTrackPeakLevel(int index);
    
    double getPlayheadTime() const { return currentPlayheadTime; }
    
    void playDemo(bool play);

    bool loadMidiFile(const juce::String& filePath);
    bool loadSoundFont(const juce::String& filePath);
    bool loadVstPlugin(int trackIndex, const juce::String& pluginPath);

    void clearMidiSequence();
    void addMidiNote(int noteNumber, double startSeconds, double durationSeconds, float velocity, int channel = 0);
    void playPreviewNote(int channel, int noteNumber, float velocity);
    void setLoopDuration(double loopSeconds);

    // AudioIODeviceCallback overrides
    void audioDeviceIOCallbackWithContext(const float* const* inputChannelData, int numInputChannels, float* const* outputChannelData, int numOutputChannels, int numSamples, const juce::AudioIODeviceCallbackContext& context) override;
    void audioDeviceAboutToStart(juce::AudioIODevice* device) override;
    void audioDeviceStopped() override;

private:
    std::unique_ptr<juce::AudioDeviceManager> deviceManager;
    std::unique_ptr<juce::AudioProcessorGraph> mainGraph;
    
    juce::AudioProcessorGraph::Node::Ptr audioOutputNode;
    juce::AudioProcessorGraph::Node::Ptr midiInputNode;
    juce::AudioProcessorGraph::Node::Ptr gmSynthNode;
    
    GMSynthProcessor* gmSynthProcessor = nullptr; // Unowned pointer to the inner processor
    
    float masterVolume = 1.0f;
    bool isPlaying = false;
    double sampleRate = 44100.0;
    
    // Playback state
    double currentPlayheadTime = 0.0;
    double loopDuration = 2.0;
    
    std::vector<TrackData> tracks;
    std::unique_ptr<juce::MidiMessageSequence> currentMidiSequence;
};
