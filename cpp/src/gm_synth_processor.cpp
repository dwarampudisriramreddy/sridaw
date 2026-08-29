#include "gm_synth_processor.h"
#include <cmath>
#include <iostream>

namespace
{
    // Route FluidSynth log messages to stderr so they show up in logcat on
    // Android (useful to diagnose SoundFont load failures).
    void fluidsynthLogCallback(int level, const char* message, void*)
    {
        if (level <= FLUID_ERR)
            std::cerr << "[fluidsynth] " << message << std::endl;
    }
}

GMSynthProcessor::GMSynthProcessor()
    : AudioProcessor (BusesProperties().withOutput ("Output", juce::AudioChannelSet::stereo(), true))
{
    fluid_set_log_function(FLUID_PANIC, fluidsynthLogCallback, nullptr);
    fluid_set_log_function(FLUID_ERR,   fluidsynthLogCallback, nullptr);
    fluid_set_log_function(FLUID_WARN,  fluidsynthLogCallback, nullptr);

    for (int i = 0; i < kMaxChannels; ++i)
        channels[i] = ChannelState();

    createSynth(44100.0);
}

void GMSynthProcessor::createSynth(double sampleRate)
{
    if (synth != nullptr)
    {
        delete_fluid_synth(synth);
        synth = nullptr;
    }
    if (settings != nullptr)
    {
        delete_fluid_settings(settings);
        settings = nullptr;
    }

    settings = new_fluid_settings();
    fluid_settings_setnum(settings, "synth.sample-rate", sampleRate);
    fluid_settings_setint(settings, "synth.chorus.active", 0);
    fluid_settings_setint(settings, "synth.reverb.active", 0);
    fluid_settings_setnum(settings, "synth.gain", masterGain);

    synth = new_fluid_synth(settings);

    if (soundFontLoaded && soundFontPath.isNotEmpty())
    {
        soundFontId = fluid_synth_sfload(synth, soundFontPath.toRawUTF8(), 1);
        soundFontLoaded = (soundFontId != -1);
        if (soundFontLoaded)
        {
            for (int i = 0; i < kMaxChannels; ++i)
                fluid_synth_program_change(synth, i, channels[i].program);
            applyChannelMix();
        }
        else
        {
            std::cerr << "[SriDAW] GMSynth: failed to re-load SoundFont after synth recreate: "
                      << soundFontPath.toStdString() << std::endl;
        }
    }
}

GMSynthProcessor::~GMSynthProcessor()
{
    if (synth != nullptr)
    {
        delete_fluid_synth(synth);
        synth = nullptr;
    }
    if (settings != nullptr)
    {
        delete_fluid_settings(settings);
        settings = nullptr;
    }
}

bool GMSynthProcessor::loadSoundFont (const juce::String& filePath)
{
    if (synth == nullptr)
    {
        std::cerr << "[SriDAW] GMSynth: loadSoundFont called but synth is null" << std::endl;
        return false;
    }

    juce::File file (filePath);
    if (!file.existsAsFile())
    {
        std::cerr << "[SriDAW] GMSynth: SoundFont file does not exist: "
                  << filePath.toStdString() << std::endl;
        return false;
    }

    if (soundFontLoaded)
    {
        fluid_synth_sfunload (synth, soundFontId, 1);
        soundFontLoaded = false;
        soundFontId = -1;
    }

    soundFontId = fluid_synth_sfload (synth, filePath.toRawUTF8(), 1);
    if (soundFontId == -1 || soundFontId == FLUID_FAILED)
    {
        std::cerr << "[SriDAW] GMSynth: fluid_synth_sfload FAILED for: "
                  << filePath.toStdString() << std::endl;
        return false;
    }

    soundFontLoaded = true;
    soundFontPath = filePath;

    for (int i = 0; i < kMaxChannels; ++i)
        fluid_synth_program_change (synth, i, channels[i].program);
    applyChannelMix();

    std::cerr << "[SriDAW] GMSynth: SoundFont loaded OK: "
              << filePath.toStdString() << std::endl;
    return true;
}

void GMSynthProcessor::setChannelVolume (int channel, float volume)
{
    if (channel >= 0 && channel < kMaxChannels)
    {
        channels[channel].volume = volume;
        applyChannelMix();
    }
}

void GMSynthProcessor::setChannelPan (int channel, float pan)
{
    if (channel >= 0 && channel < kMaxChannels)
    {
        channels[channel].pan = pan;
        applyChannelMix();
    }
}

void GMSynthProcessor::setChannelMute (int channel, bool mute)
{
    if (channel >= 0 && channel < kMaxChannels)
    {
        channels[channel].muted = mute;
        applyChannelMix();
    }
}

void GMSynthProcessor::setChannelSolo (int channel, bool solo, bool anySoloActive)
{
    if (channel >= 0 && channel < kMaxChannels)
        channels[channel].solo = solo;

    bool anySolo = anySoloActive;
    if (!anySolo)
        for (int i = 0; i < kMaxChannels; ++i)
            if (channels[i].solo) { anySolo = true; break; }

    for (int i = 0; i < kMaxChannels; ++i)
    {
        bool shouldMute = channels[i].muted;
        if (anySolo && !channels[i].solo)
            shouldMute = true;

        const float effectiveVolume = shouldMute ? 0.0f : channels[i].volume;
        channels[i].cc7 = static_cast<int> (effectiveVolume * 127.0f);
        if (synth != nullptr)
            fluid_synth_cc (synth, i, 7, channels[i].cc7);
    }
}

void GMSynthProcessor::setChannelProgram (int channel, int program)
{
    if (channel >= 0 && channel < kMaxChannels)
    {
        channels[channel].program = program;
        if (synth != nullptr)
            fluid_synth_program_change (synth, channel, program);
    }
}

int GMSynthProcessor::getChannelProgram (int channel) const
{
    if (channel >= 0 && channel < kMaxChannels)
        return channels[channel].program;
    return 0;
}

void GMSynthProcessor::playNote (int channel, int note, int velocity)
{
    if (synth && channel >= 0 && channel < kMaxChannels)
    {
        if (velocity <= 0)
            fluid_synth_noteoff (synth, channel, note);
        else
            fluid_synth_noteon (synth, channel, note, velocity);
    }
}

void GMSynthProcessor::stopNote (int channel, int note)
{
    if (synth && channel >= 0 && channel < kMaxChannels)
        fluid_synth_noteoff (synth, channel, note);
}

void GMSynthProcessor::setMasterGain (float gain)
{
    masterGain = gain;
    if (synth != nullptr)
        fluid_synth_set_gain (synth, masterGain);
}

void GMSynthProcessor::allSoundsOff()
{
    if (synth != nullptr)
        for (int i = 0; i < kMaxChannels; ++i)
            fluid_synth_all_notes_off (synth, i);
}

void GMSynthProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    if (synth == nullptr || settings == nullptr)
        return;

    double currentRate = 0.0;
    fluid_settings_getnum (settings, "synth.sample-rate", &currentRate);
    if (currentRate != sampleRate)
    {
        std::cerr << "[SriDAW] GMSynth: recreating synth at device sample rate "
                  << sampleRate << " (was " << currentRate << ")" << std::endl;
        createSynth (sampleRate);
    }
}

void GMSynthProcessor::releaseResources()
{
    allSoundsOff();
}

void GMSynthProcessor::sendMidiToSynth (const juce::MidiBuffer& midiMessages)
{
    if (synth == nullptr || !soundFontLoaded)
        return;

    for (const auto metadata : midiMessages)
    {
        const auto message = metadata.getMessage();
        const int ch = message.getChannel() - 1; // JUCE channels are 1-based
        if (ch < 0 || ch >= kMaxChannels)
            continue;

        if (message.isNoteOn())
            fluid_synth_noteon (synth, ch, message.getNoteNumber(),
                                juce::roundToInt (message.getFloatVelocity() * 127.0f));
        else if (message.isNoteOff())
            fluid_synth_noteoff (synth, ch, message.getNoteNumber());
        else if (message.isPitchWheel())
            fluid_synth_pitch_bend (synth, ch, message.getPitchWheelValue());
        else if (message.isController())
            fluid_synth_cc (synth, ch, message.getControllerNumber(), message.getControllerValue());
        else if (message.isProgramChange())
            fluid_synth_program_change (synth, ch, message.getProgramChangeNumber());
        else if (message.isChannelPressure())
            fluid_synth_channel_pressure (synth, ch, message.getChannelPressureValue());
    }
}

void GMSynthProcessor::applyChannelMix()
{
    if (synth == nullptr)
        return;

    bool anySolo = false;
    for (int i = 0; i < kMaxChannels; ++i)
        if (channels[i].solo) { anySolo = true; break; }

    for (int i = 0; i < kMaxChannels; ++i)
    {
        bool shouldMute = channels[i].muted;
        if (anySolo && !channels[i].solo)
            shouldMute = true;

        const float effectiveVolume = shouldMute ? 0.0f : channels[i].volume;
        channels[i].cc7 = static_cast<int> (effectiveVolume * 127.0f);

        int pan = juce::roundToInt ((channels[i].pan + 1.0f) * 63.5f);
        pan = juce::jlimit (0, 127, pan);
        channels[i].cc10 = pan;

        fluid_synth_cc (synth, i, 7, channels[i].cc7);
        fluid_synth_cc (synth, i, 10, channels[i].cc10);
    }
}

void GMSynthProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    buffer.clear();
    if (synth == nullptr || !soundFontLoaded)
        return;

    sendMidiToSynth (midiMessages);

    const int numSamples = buffer.getNumSamples();
    const int numChannels = buffer.getNumChannels();

    if (numChannels >= 2)
    {
        float* l = buffer.getWritePointer (0);
        float* r = buffer.getWritePointer (1);
        fluid_synth_write_float (synth, numSamples, l, 0, 1, r, 0, 1);
    }
    else if (numChannels == 1)
    {
        juce::AudioBuffer<float> temp (2, numSamples);
        float* l = temp.getWritePointer (0);
        float* r = temp.getWritePointer (1);
        fluid_synth_write_float (synth, numSamples, l, 0, 1, r, 0, 1);
        buffer.copyFrom (0, 0, temp, 0, 0, numSamples);
    }

    float peak = 0.0f;
    for (int ch = 0; ch < numChannels; ++ch)
    {
        const float* readPtr = buffer.getReadPointer (ch);
        for (int i = 0; i < numSamples; ++i)
        {
            const float absVal = std::abs (readPtr[i]);
            if (absVal > peak) peak = absVal;
        }
    }
    lastPeakLevel = peak;
}
