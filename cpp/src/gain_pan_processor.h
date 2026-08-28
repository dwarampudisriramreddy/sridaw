#pragma once
#include <juce_core/juce_core.h>
#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_processors/juce_audio_processors.h>

class GainPanProcessor : public juce::AudioProcessor {
public:
    GainPanProcessor();
    ~GainPanProcessor() override = default;

    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    void setVolume(float newVolume) { volume = newVolume; }
    void setPan(float newPan) { pan = newPan; }
    void setMute(bool isMuted) { mute = isMuted; }
    
    // Read the peak level calculated during the last processBlock
    float getLastPeakLevel() const { return lastPeak; }

    const juce::String getName() const override { return "GainPan"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram (int index) override {}
    const juce::String getProgramName (int index) override { return {}; }
    void changeProgramName (int index, const juce::String& newName) override {}
    
    bool isBusesLayoutSupported (const BusesLayout& layouts) const override { return true; }
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor* createEditor() override { return nullptr; }
    void getStateInformation (juce::MemoryBlock& destData) override {}
    void setStateInformation (const void* data, int sizeInBytes) override {}

private:
    float volume = 1.0f;
    float pan = 0.0f; // -1.0 to 1.0
    bool mute = false;
    float lastPeak = 0.0f;
};
