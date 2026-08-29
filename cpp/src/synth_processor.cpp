#include "synth_processor.h"
#include <cmath>

//==============================================================================
BuiltInVoice::BuiltInVoice()
{
    synth.setCurrentPlaybackSampleRate (44100.0);
}

bool BuiltInVoice::canPlaySound (juce::SynthesiserSound* sound)
{
    return dynamic_cast<BuiltInSound*> (sound) != nullptr;
}

void BuiltInVoice::setInstrument (int instrumentType)
{
    switch (instrumentType)
    {
        case INSTRUMENT_TRIANGLE: wave = Wave::triangle; attack = 0.01f; decay = 0.25f; sustain = 0.8f; release = 0.25f; break;
        case INSTRUMENT_SQUARE:   wave = Wave::square;   attack = 0.005f; decay = 0.2f; sustain = 0.85f; release = 0.2f; break;
        case INSTRUMENT_SAW:      wave = Wave::saw;      attack = 0.005f; decay = 0.2f; sustain = 0.85f; release = 0.2f; break;
        case INSTRUMENT_LEAD:     wave = Wave::saw;      attack = 0.01f; decay = 0.4f; sustain = 0.9f; release = 0.3f; break;
        case INSTRUMENT_BASS:     wave = Wave::saw;      attack = 0.005f; decay = 0.1f; sustain = 0.55f; release = 0.12f; break;
        case INSTRUMENT_PLUCK:    wave = Wave::square;   attack = 0.002f; decay = 0.15f; sustain = 0.0f; release = 0.2f; break;
        case INSTRUMENT_PAD:      wave = Wave::triangle; attack = 0.4f; decay = 0.6f; sustain = 0.9f; release = 0.8f; break;
        case INSTRUMENT_KEYS:     wave = Wave::triangle; attack = 0.008f; decay = 0.3f; sustain = 0.75f; release = 0.3f; break;
        case INSTRUMENT_STRINGS:  wave = Wave::saw;      attack = 0.2f; decay = 0.4f; sustain = 0.8f; release = 0.5f; break;
        case INSTRUMENT_SINE:
        default:                  wave = Wave::sine; attack = 0.01f; decay = 0.25f; sustain = 0.8f; release = 0.25f; break;
    }
}

void BuiltInVoice::startNote (int midiNoteNumber, float noteVelocity, juce::SynthesiserSound* sound, int)
{
    if (auto* theSound = dynamic_cast<BuiltInSound*> (sound))
    {
        currentPlayingSound = theSound;
        isPlaying = true;
        tailOff = false;

        midiNote = (float) midiNoteNumber;
        velocity = noteVelocity;
        frequency = (float) juce::MidiMessage::getMidiNoteInHertz (midiNoteNumber);
        phaseIncrement = (frequency / sampleRate) * 2.0 * juce::MathConstants<double>::pi;
        phase = 0.0;

        envelopeTime = 0.0;
        level = 0.0f;
        releaseLevel = 0.0f;
    }
}

void BuiltInVoice::stopNote (float, bool allowTailOff)
{
    if (allowTailOff)
    {
        // enter the release portion of the envelope
        tailOff = true;
        sustainPhase = 1;
        envelopeTime = 0.0;
    }
    else
    {
        clearCurrentNote();
        isPlaying = false;
        level = 0.0f;
    }
}

static inline float waveSample (BuiltInVoiceWave wave, double phase)
{
    switch (wave)
    {
        case sine: return (float) std::sin (phase);
        case triangle: return (float) (2.0 * std::abs (2.0 * (phase / (2.0 * juce::MathConstants<double>::pi)) - 1.0) - 1.0);
        case square: return phase < juce::MathConstants<double>::pi ? 1.0f : -1.0f;
        case saw: return (float) (1.0 - 2.0 * (phase / (2.0 * juce::MathConstants<double>::pi)));
    }
    return 0.0f;
}

void BuiltInVoice::renderNextBlock (juce::AudioBuffer<float>& outputBuffer, int startSample, int numSamples)
{
    if (isPlaying)
    {
        const int numChannels = outputBuffer.getNumChannels();
        auto waveForInstrument = wave;

        for (int sample = 0; sample < numSamples; ++sample)
        {
            const int outputIndex = startSample + sample;

            const float sampleValue = velocity * waveSample (waveForInstrument, phase);

            // Simple ADSR envelope
            const double envDuration = (tailOff ? release : (level >= sustain ? decay : attack));
            const float target = tailOff ? 0.0f : sustain;
            float newLevel = level;

            if (!tailOff)
            {
                if (level < sustain)
                {
                    newLevel = level + (1.0f / (attack * (float) sampleRate));
                }
                else
                {
                    newLevel = level - (1.0f / (decay * (float) sampleRate));
                    if (newLevel < sustain) newLevel = sustain;
                }
                if (newLevel > 1.0f) newLevel = 1.0f;
            }
            else
            {
                newLevel = level - (1.0f / (release * (float) sampleRate));
            }

            level = newLevel > 0.0f ? newLevel : 0.0f;
            const float rendered = sampleValue * level;

            // Simple velocity-based low-pass per instrument (one-pole)
            for (int ch = 0; ch < numChannels; ++ch)
                outputBuffer.addSample (ch, outputIndex, rendered);

            phase += phaseIncrement;
            if (phase >= 2.0 * juce::MathConstants<double>::pi)
                phase -= 2.0 * juce::MathConstants<double>::pi;

            if (tailOff && level <= 0.001f)
            {
                clearCurrentNote();
                isPlaying = false;
                level = 0.0f;
                break;
            }
        }
    }
}

//==============================================================================
BuiltInSynthProcessor::BuiltInSynthProcessor()
    : AudioProcessor (BusesProperties().withOutput ("Output", juce::AudioChannelSet::stereo(), true))
{
    formatManager.registerBasicFormats();
    clearVoices();
    synth.addSound (new BuiltInSound());
}

void BuiltInSynthProcessor::clearVoices()
{
    synth.clearVoices();
    for (int i = 0; i < 16; ++i)
    {
        auto* voice = new BuiltInVoice();
        voice->setInstrument (currentInstrument);
        synth.addVoice (voice);
    }
}

void BuiltInSynthProcessor::setInstrument (int instrumentType)
{
    currentInstrument = instrumentType;
    // Reconfigure existing voices
    for (int i = 0; i < synth.getNumVoices(); ++i)
    {
        if (auto* v = dynamic_cast<BuiltInVoice*> (synth.getVoice (i)))
            v->setInstrument (instrumentType);
    }
}

bool BuiltInSynthProcessor::loadSample (const juce::String& filePath, double rootNote)
{
    juce::File file(filePath);
    if (!file.existsAsFile()) return false;

    std::unique_ptr<juce::AudioFormatReader> reader (formatManager.createReaderFor (file));
    if (reader != nullptr)
    {
        // Switch to a sampler voice layout for sample playback
        synth.clearVoices();
        for (int i = 0; i < 8; ++i)
            synth.addVoice (new juce::SamplerVoice());

        synth.clearSounds();
        juce::BigInteger allNotes;
        allNotes.setRange (0, 128, true);

        synth.addSound (new juce::SamplerSound (
            "Sample", *reader, allNotes, rootNote, 0.1, 0.1, 10.0));

        return true;
    }

    // Failed to load sample, restore built-in voices
    synth.clearSounds();
    synth.addSound (new BuiltInSound());
    clearVoices();
    return false;
}

void BuiltInSynthProcessor::prepareToPlay (double newSampleRate, int samplesPerBlock)
{
    synth.setCurrentPlaybackSampleRate (newSampleRate);
    for (int i = 0; i < synth.getNumVoices(); ++i)
        if (auto* v = dynamic_cast<BuiltInVoice*> (synth.getVoice (i)))
            v->setSampleRate (newSampleRate);
}

void BuiltInSynthProcessor::releaseResources()
{
}

void BuiltInSynthProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    buffer.clear();
    synth.renderNextBlock (buffer, midiMessages, 0, buffer.getNumSamples());
}
