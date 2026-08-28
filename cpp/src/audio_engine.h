#pragma once

#include <JuceHeader.h>
#include <memory>
#include <vector>

struct TrackData {
    float volume = 1.0f;
    float pan = 0.0f;
    bool mute = false;
    bool solo = false;
    float lastPeakLevel = 0.0f;
    
    // For VST / Instrument Hosting
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
    float getTrackPeakLevel(int index);
    
    double getPlayheadTime() const { return currentPlayheadTime; }
    
    void playDemo(bool play);

    bool loadMidiFile(const juce::String& filePath);
    bool loadTrackSample(int trackIndex, const juce::String& filePath);
    bool loadVstPlugin(int trackIndex, const juce::String& pluginPath);

    void clearMidiSequence();
    void addMidiNote(int noteNumber, double startSeconds, double durationSeconds, float velocity);
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
    
    float masterVolume = 1.0f;
    bool isPlaying = false;
    double sampleRate = 44100.0;
    
    // Playback state
    double currentPlayheadTime = 0.0;
    double loopDuration = 2.0;
    
    std::vector<TrackData> tracks;
    std::unique_ptr<juce::MidiMessageSequence> currentMidiSequence;
};
