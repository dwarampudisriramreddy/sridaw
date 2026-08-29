#pragma once
#include <juce_core/juce_core.h>
#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <fluidsynth.h>

//==============================================================================
// A single General MIDI (FluidSynth) synth used by the whole engine.
//
// Design:
//   * ONE FluidSynth synthesizer + ONE SoundFont instance shared across all
//     tracks. Each DAW track maps onto a MIDI channel (track i -> channel i),
//     so per-track "instrument" == a program change on that channel and the
//     track mixer (volume/pan/mute/solo) is applied as per-channel CCs.
//   * FluidSynth renders all audio channels mixed together, so we render the
//     shared synth once per callback and write the result straight to the
//     output buffer (2 channels).
class GMSynthProcessor : public juce::AudioProcessor
{
public:
    GMSynthProcessor();
    ~GMSynthProcessor() override;

    // Loads a General MIDI SoundFont (.sf2). Returns true on success.
    bool loadSoundFont (const juce::String& filePath);
    bool isSoundFontLoaded() const { return soundFontLoaded; }
    const juce::String& getSoundFontPath() const { return soundFontPath; }

    // Per-track (per-channel) controls --------------------------------------
    void setChannelVolume (int channel, float volume);   // 0..1
    void setChannelPan (int channel, float pan);         // -1..1
    void setChannelMute (int channel, bool mute);
    void setChannelSolo (int channel, bool solo, bool anySoloActive);
    void setChannelProgram (int channel, int program);   // 0..127 GM program
    int  getChannelProgram (int channel) const;

    void playNote (int channel, int note, int velocity);
    void stopNote (int channel, int note);

    void setMasterGain (float gain);
    void allSoundsOff();
    float getLastPeakLevel() const { return lastPeakLevel; }

    // JUCE AudioProcessor boilerplate
    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    const juce::String getName() const override { return "GMSynthProcessor"; }
    bool acceptsMidi() const override { return true; }
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
    void createSynth (double sampleRate);
    void sendMidiToSynth (const juce::MidiBuffer& midi);
    void applyChannelMix();

    fluid_settings_t* settings = nullptr;
    fluid_synth_t*    synth = nullptr;
    int soundFontId = -1;
    bool soundFontLoaded = false;
    juce::String soundFontPath;

    float masterGain = 0.5f;
    float lastPeakLevel = 0.0f;

    struct ChannelState
    {
        float volume = 1.0f;
        float pan = 0.0f;
        bool  muted = false;
        bool  solo = false;
        int   program = 0;
        int   cc7 = 100;
        int   cc10 = 64;
    };
    static constexpr int kMaxChannels = 16;
    ChannelState channels[kMaxChannels];
};
