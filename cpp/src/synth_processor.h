#pragma once
#include <juce_core/juce_core.h>
#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_audio_formats/juce_audio_formats.h>

// Built-in instrument identifiers (use these from the UI via FFI)
enum BuiltInInstrument {
    INSTRUMENT_SINE = 0,
    INSTRUMENT_TRIANGLE = 1,
    INSTRUMENT_SQUARE = 2,
    INSTRUMENT_SAW = 3,
    INSTRUMENT_LEAD = 4,
    INSTRUMENT_BASS = 5,
    INSTRUMENT_PLUCK = 6,
    INSTRUMENT_PAD = 7,
    INSTRUMENT_KEYS = 8,
    INSTRUMENT_STRINGS = 9,
};

// A SynthesiserSound that matches any note. Only used to allow built-in voices
// to trigger on any MIDI note (SamplerSound is only used for sample playback).
class BuiltInSound : public juce::SynthesiserSound {
public:
    bool appliesToNote(int) override { return true; }
    bool appliesToChannel(int) override { return true; }
};

// A synthesiser voice that renders simple waveforms + an ADSR envelope.
// This is what makes the "native instruments" produce sound without any
// external sample files.
enum BuiltInWave { waveSine, waveTriangle, waveSquare, waveSaw };

class BuiltInVoice : public juce::SynthesiserVoice {
public:
    BuiltInVoice();
    ~BuiltInVoice() override = default;

    bool canPlaySound(juce::SynthesiserSound* sound) override;
    void startNote(int midiNoteNumber, float velocity, juce::SynthesiserSound*, int) override;
    void stopNote(float velocity, bool allowTailOff) override;
    void pitchWheelMoved(int) override {}
    void controllerMoved(int, int) override {}
    void renderNextBlock(juce::AudioBuffer<float>& outputBuffer, int startSample, int numSamples) override;

    void setInstrument(int instrumentType);
    void setSampleRate(double newSampleRate) { sampleRate = newSampleRate; }

private:
    BuiltInWave wave = waveSine;

    double sampleRate = 44100.0;
    double phase = 0.0;
    double phaseIncrement = 0.0;
    float frequency = 0.0f;
    float midiNote = 60.0f;
    float velocity = 0.0f;
    float level = 0.0f;
    float releaseLevel = 0.0f;
    bool isPlaying = false;
    bool tailOff = false;

    // ADSR parameters (attack, decay, sustain, release in seconds)
    float attack = 0.01f, decay = 0.2f, sustain = 0.8f, release = 0.2f;
    double envelopeTime = 0.0;
    int sustainPhase = 0;  // envelope phase counter
};

class BuiltInSynthProcessor : public juce::AudioProcessor {
public:
    BuiltInSynthProcessor();
    ~BuiltInSynthProcessor() override = default;

    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    // Set one of the built-in native instruments for this track.
    void setInstrument(int instrumentType);

    // Load a .wav or .aiff file to act as the sample for this instrument
    bool loadSample(const juce::String& filePath, double rootNotesBase = 60.0);

    const juce::String getName() const override { return "BuiltInSynthProcessor"; }
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
    void clearVoices();

    juce::Synthesiser synth;
    juce::AudioFormatManager formatManager;
    int currentInstrument = INSTRUMENT_SINE;
};
