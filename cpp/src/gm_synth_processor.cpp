#include "gm_synth_processor.h"

GMSynthProcessor::GMSynthProcessor()
    : AudioProcessor (BusesProperties().withOutput ("Output", juce::AudioChannelSet::stereo(), true))
{
    settings = new_fluid_settings();
    fluid_settings_setnum(settings, "synth.sample-rate", 44100.0);
    // Disable chorus and reverb by default to save CPU, user can enable later if needed
    fluid_settings_setint(settings, "synth.chorus.active", 0);
    fluid_settings_setint(settings, "synth.reverb.active", 0);
    
    synth = new_fluid_synth(settings);
    
    for (int i = 0; i < kMaxChannels; ++i) {
        channels[i] = ChannelState();
    }
}

GMSynthProcessor::~GMSynthProcessor()
{
    if (synth) delete_fluid_synth(synth);
    if (settings) delete_fluid_settings(settings);
}

bool GMSynthProcessor::loadSoundFont(const juce::String& filePath)
{
    if (synth == nullptr) return false;
    
    if (soundFontLoaded && soundFontId != -1) {
        fluid_synth_sfunload(synth, soundFontId, 1);
        soundFontLoaded = false;
        soundFontId = -1;
    }
    
    soundFontId = fluid_synth_sfload(synth, filePath.toRawUTF8(), 1);
    if (soundFontId != -1) {
        soundFontLoaded = true;
        soundFontPath = filePath;
        
        for (int i = 0; i < kMaxChannels; ++i) {
            fluid_synth_program_change(synth, i, channels[i].program);
        }
        applyChannelMix();
        return true;
    }
    return false;
}

void GMSynthProcessor::setChannelVolume (int channel, float volume)
{
    if (channel >= 0 && channel < kMaxChannels) {
        channels[channel].volume = volume;
        applyChannelMix();
    }
}

void GMSynthProcessor::setChannelPan (int channel, float pan)
{
    if (channel >= 0 && channel < kMaxChannels) {
        channels[channel].pan = pan;
        applyChannelMix();
    }
}

void GMSynthProcessor::setChannelMute (int channel, bool mute)
{
    if (channel >= 0 && channel < kMaxChannels) {
        channels[channel].muted = mute;
        applyChannelMix();
    }
}

void GMSynthProcessor::setChannelSolo (int channel, bool solo, bool anySoloActive)
{
    if (channel >= 0 && channel < kMaxChannels) {
        channels[channel].solo = solo;
    }
    
    // We need to re-evaluate all channels if any solo state changes
    for (int i = 0; i < kMaxChannels; ++i) {
        bool shouldMute = channels[i].muted;
        if (anySoloActive && !channels[i].solo) {
            shouldMute = true;
        }
        
        float effectiveVolume = shouldMute ? 0.0f : channels[i].volume;
        channels[i].cc7 = static_cast<int>(effectiveVolume * 127.0f);
        
        if (synth) {
            fluid_synth_cc(synth, i, 7, channels[i].cc7);
        }
    }
}

void GMSynthProcessor::setChannelProgram (int channel, int program)
{
    if (channel >= 0 && channel < kMaxChannels) {
        channels[channel].program = program;
        if (synth) {
            fluid_synth_program_change(synth, channel, program);
        }
    }
}

int GMSynthProcessor::getChannelProgram (int channel) const
{
    if (channel >= 0 && channel < kMaxChannels) {
        return channels[channel].program;
    }
    return 0;
}

void GMSynthProcessor::playNote (int channel, int note, int velocity)
{
    if (synth && channel >= 0 && channel < kMaxChannels) {
        fluid_synth_noteon(synth, channel, note, velocity);
    }
}

void GMSynthProcessor::stopNote (int channel, int note)
{
    if (synth && channel >= 0 && channel < kMaxChannels) {
        fluid_synth_noteoff(synth, channel, note);
    }
}

void GMSynthProcessor::setMasterGain (float gain)
{
    masterGain = gain;
    if (synth) {
        fluid_settings_setnum(settings, "synth.gain", masterGain);
    }
}

void GMSynthProcessor::allSoundsOff()
{
    if (synth) {
        for (int i = 0; i < kMaxChannels; ++i) {
            fluid_synth_cc(synth, i, 120, 0); // All Sound Off
            fluid_synth_cc(synth, i, 123, 0); // All Notes Off
        }
    }
}

void GMSynthProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    if (synth) {
        fluid_synth_set_sample_rate(synth, static_cast<float>(sampleRate));
    }
}

void GMSynthProcessor::releaseResources()
{
    allSoundsOff();
}

void GMSynthProcessor::sendMidiToSynth(const juce::MidiBuffer& midi)
{
    if (!synth) return;
    
    for (const auto meta : midi)
    {
        const auto msg = meta.getMessage();
        int ch = msg.getChannel() - 1; // 0-based
        if (ch < 0 || ch >= kMaxChannels) continue;

        if (msg.isNoteOn())
            fluid_synth_noteon(synth, ch, msg.getNoteNumber(), msg.getVelocity());
        else if (msg.isNoteOff())
            fluid_synth_noteoff(synth, ch, msg.getNoteNumber());
        else if (msg.isPitchWheel())
            fluid_synth_pitch_bend(synth, ch, msg.getPitchWheelValue());
        else if (msg.isController())
            fluid_synth_cc(synth, ch, msg.getControllerNumber(), msg.getControllerValue());
        else if (msg.isProgramChange())
            fluid_synth_program_change(synth, ch, msg.getProgramChangeNumber());
        else if (msg.isAftertouch())
            fluid_synth_channel_pressure(synth, ch, msg.getAfterTouchValue());
    }
}

void GMSynthProcessor::applyChannelMix()
{
    if (!synth) return;
    
    bool anySolo = false;
    for (int i = 0; i < kMaxChannels; ++i) {
        if (channels[i].solo) {
            anySolo = true;
            break;
        }
    }
    
    for (int i = 0; i < kMaxChannels; ++i) {
        bool shouldMute = channels[i].muted;
        if (anySolo && !channels[i].solo) {
            shouldMute = true;
        }
        
        float effectiveVolume = shouldMute ? 0.0f : channels[i].volume;
        channels[i].cc7 = static_cast<int>(effectiveVolume * 127.0f);
        
        // Pan is -1 to 1, map to 0 to 127
        channels[i].cc10 = static_cast<int>((channels[i].pan + 1.0f) * 63.5f);
        if (channels[i].cc10 < 0) channels[i].cc10 = 0;
        if (channels[i].cc10 > 127) channels[i].cc10 = 127;
        
        fluid_synth_cc(synth, i, 7, channels[i].cc7);
        fluid_synth_cc(synth, i, 10, channels[i].cc10);
    }
}

void GMSynthProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    buffer.clear();
    if (!synth) return;

    sendMidiToSynth(midiMessages);

    int numSamples = buffer.getNumSamples();
    int numChannels = buffer.getNumChannels();

    if (numChannels >= 2) {
        float* left = buffer.getWritePointer(0);
        float* right = buffer.getWritePointer(1);
        fluid_synth_write_float(synth, numSamples, left, 0, 1, right, 0, 1);
    } else if (numChannels == 1) {
        juce::AudioBuffer<float> tempBuf(2, numSamples);
        float* left = tempBuf.getWritePointer(0);
        float* right = tempBuf.getWritePointer(1);
        fluid_synth_write_float(synth, numSamples, left, 0, 1, right, 0, 1);
        buffer.copyFrom(0, 0, left, numSamples);
    }
    
    float peak = 0.0f;
    for (int ch = 0; ch < numChannels; ++ch) {
        const float* readPtr = buffer.getReadPointer(ch);
        for (int i = 0; i < numSamples; ++i) {
            float absVal = std::abs(readPtr[i]);
            if (absVal > peak) peak = absVal;
        }
    }
    lastPeakLevel = peak;
}
