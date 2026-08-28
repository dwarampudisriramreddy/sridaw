#include "gain_pan_processor.h"

GainPanProcessor::GainPanProcessor() 
    : AudioProcessor (BusesProperties()
                      .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                      .withOutput ("Output", juce::AudioChannelSet::stereo(), true)) 
{
}

void GainPanProcessor::prepareToPlay (double sampleRate, int samplesPerBlock) {
    lastPeak = 0.0f;
}

void GainPanProcessor::releaseResources() {
}

void GainPanProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages) {
    if (mute || volume <= 0.0001f) {
        buffer.clear();
        lastPeak = 0.0f;
        return;
    }

    int numSamples = buffer.getNumSamples();
    float currentPeak = 0.0f;

    // Standard equal-power panning (-1.0 left to 1.0 right)
    float panPi = (pan + 1.0f) * 0.25f * juce::MathConstants<float>::pi;
    float leftGain = std::cos(panPi) * volume;
    float rightGain = std::sin(panPi) * volume;

    if (buffer.getNumChannels() >= 2) {
        float* leftChannel = buffer.getWritePointer(0);
        float* rightChannel = buffer.getWritePointer(1);

        for (int i = 0; i < numSamples; ++i) {
            leftChannel[i] *= leftGain;
            rightChannel[i] *= rightGain;
            
            float absL = std::abs(leftChannel[i]);
            float absR = std::abs(rightChannel[i]);
            if (absL > currentPeak) currentPeak = absL;
            if (absR > currentPeak) currentPeak = absR;
        }
    } else if (buffer.getNumChannels() == 1) {
        float* channel = buffer.getWritePointer(0);
        for (int i = 0; i < numSamples; ++i) {
            channel[i] *= volume;
            float absVal = std::abs(channel[i]);
            if (absVal > currentPeak) currentPeak = absVal;
        }
    }

    lastPeak = currentPeak;
}
