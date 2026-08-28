#include "synth_processor.h"

BuiltInSynthProcessor::BuiltInSynthProcessor() 
    : AudioProcessor (BusesProperties().withOutput ("Output", juce::AudioChannelSet::stereo(), true)) 
{
    // Register basic audio formats (WAV, AIFF, FLAC, etc.)
    formatManager.registerBasicFormats();

    // Add 8 polyphonic sampler voices
    for (int i = 0; i < 8; ++i) {
        synth.addVoice (new juce::SamplerVoice());
    }
}

bool BuiltInSynthProcessor::loadSample(const juce::String& filePath, double rootNote) {
    juce::File file(filePath);
    if (!file.existsAsFile()) return false;
    
    std::unique_ptr<juce::AudioFormatReader> reader (formatManager.createReaderFor(file));
    if (reader != nullptr) {
        synth.clearSounds();
        
        // Map this sample across all 128 MIDI notes
        juce::BigInteger allNotes;
        allNotes.setRange (0, 128, true);
        
        // Create the sampler sound
        synth.addSound (new juce::SamplerSound (
            "Sample",
            *reader,
            allNotes,
            rootNote, // Default MIDI Note C4
            0.1,      // Attack time
            0.1,      // Release time
            10.0      // Maximum sample length
        ));
        
        return true;
    }
    return false;
}

void BuiltInSynthProcessor::prepareToPlay (double sampleRate, int samplesPerBlock) {
    synth.setCurrentPlaybackSampleRate (sampleRate);
}

void BuiltInSynthProcessor::releaseResources() {
}

void BuiltInSynthProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages) {
    buffer.clear();
    // The sampler reads the incoming MIDI messages and renders the mapped audio sample
    synth.renderNextBlock (buffer, midiMessages, 0, buffer.getNumSamples());
}
