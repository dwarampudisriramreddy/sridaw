#include "audio_engine.h"
#include "gm_synth_processor.h"
#include <iostream>

AudioEngine::AudioEngine() {
    deviceManager = std::make_unique<juce::AudioDeviceManager>();
    mainGraph = std::make_unique<juce::AudioProcessorGraph>();
    tracks.resize(16); // Up to 16 tracks for GM
}

AudioEngine::~AudioEngine() {
    shutdown();
}

bool AudioEngine::initialize() {
    juce::String error = deviceManager->initialiseWithDefaultDevices(0, 2);
    if (error.isNotEmpty()) {
        std::cerr << "JUCE AudioEngine failed to initialize: " << error.toStdString() << std::endl;
        return false;
    }
    
    mainGraph->clear();
    
    audioOutputNode = mainGraph->addNode(std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(juce::AudioProcessorGraph::AudioGraphIOProcessor::audioOutputNode));
    midiInputNode = mainGraph->addNode(std::make_unique<juce::AudioProcessorGraph::AudioGraphIOProcessor>(juce::AudioProcessorGraph::AudioGraphIOProcessor::midiInputNode));
    
    // Create the single GM Synth node
    auto gmSynth = std::make_unique<GMSynthProcessor>();
    gmSynthProcessor = gmSynth.get();
    gmSynthNode = mainGraph->addNode(std::move(gmSynth));
    
    // Connect MIDI Input -> GM Synth MIDI Input
    mainGraph->addConnection({ { midiInputNode->nodeID, juce::AudioProcessorGraph::midiChannelIndex },
                               { gmSynthNode->nodeID, juce::AudioProcessorGraph::midiChannelIndex } });
                               
    // Connect GM Synth Audio Output -> Master Output
    for (int ch = 0; ch < 2; ++ch) {
        mainGraph->addConnection({ { gmSynthNode->nodeID, ch },
                                   { audioOutputNode->nodeID, ch } });
    }
    
    deviceManager->addAudioCallback(this);
    return true;
}

void AudioEngine::shutdown() {
    if (deviceManager) {
        deviceManager->removeAudioCallback(this);
        deviceManager->closeAudioDevice();
    }
    mainGraph->clear();
}

void AudioEngine::setMasterVolume(float volume) {
    masterVolume = juce::jlimit(0.0f, 1.0f, volume);
    if (gmSynthProcessor) {
        gmSynthProcessor->setMasterGain(masterVolume);
    }
}

float AudioEngine::getMasterVolume() const { return masterVolume; }

void AudioEngine::setTrackVolume(int index, float volume) {
    if (index >= 0 && index < tracks.size()) {
        tracks[index].volume = volume;
        if (gmSynthProcessor) {
            gmSynthProcessor->setChannelVolume(index, volume);
        }
    }
}

void AudioEngine::setTrackMute(int index, bool mute) {
    if (index >= 0 && index < tracks.size()) {
        tracks[index].mute = mute;
        if (gmSynthProcessor) {
            gmSynthProcessor->setChannelMute(index, mute);
        }
    }
}

void AudioEngine::setTrackSolo(int index, bool solo) {
    if (index >= 0 && index < tracks.size()) {
        tracks[index].solo = solo;
        
        bool anySolo = false;
        for (const auto& t : tracks) {
            if (t.solo) {
                anySolo = true;
                break;
            }
        }
        
        if (gmSynthProcessor) {
            gmSynthProcessor->setChannelSolo(index, solo, anySolo);
        }
    }
}

void AudioEngine::setTrackPan(int index, float pan) {
    if (index >= 0 && index < tracks.size()) {
        tracks[index].pan = pan;
        if (gmSynthProcessor) {
            gmSynthProcessor->setChannelPan(index, pan);
        }
    }
}

void AudioEngine::setTrackInstrument(int index, int program) {
    if (index >= 0 && index < tracks.size()) {
        if (gmSynthProcessor) {
            gmSynthProcessor->setChannelProgram(index, program);
        }
    }
}

float AudioEngine::getTrackPeakLevel(int index) {
    // In the shared GM model, we don't have individual audio nodes per track,
    // so we return the master peak level for Track 0, or just 0.
    if (index == 0 && gmSynthProcessor) {
        return gmSynthProcessor->getLastPeakLevel();
    }
    return 0.0f;
}

void AudioEngine::playDemo(bool play) {
    isPlaying = play;
    
    if (play) {
        currentPlayheadTime = 0.0;
        
        if (!currentMidiSequence) {
            currentMidiSequence = std::make_unique<juce::MidiMessageSequence>();
            currentMidiSequence->addEvent(juce::MidiMessage::noteOn(1, 60, 0.8f), 0.0);
            currentMidiSequence->addEvent(juce::MidiMessage::noteOn(1, 64, 0.8f), 0.0);
            currentMidiSequence->addEvent(juce::MidiMessage::noteOn(1, 67, 0.8f), 0.0);
            currentMidiSequence->addEvent(juce::MidiMessage::noteOff(1, 60), 1.0);
            currentMidiSequence->addEvent(juce::MidiMessage::noteOff(1, 64), 1.0);
            currentMidiSequence->addEvent(juce::MidiMessage::noteOff(1, 67), 1.0);
            currentMidiSequence->updateMatchedPairs();
        }
    }
}

bool AudioEngine::loadMidiFile(const juce::String& filePath) {
    juce::File file(filePath);
    if (!file.existsAsFile()) return false;
    
    juce::FileInputStream stream(file);
    juce::MidiFile midiFile;
    if (midiFile.readFrom(stream)) {
        if (midiFile.getNumTracks() > 0) {
            currentMidiSequence = std::make_unique<juce::MidiMessageSequence>(*midiFile.getTrack(0));
            midiFile.convertTimestampTicksToSeconds();
            return true;
        }
    }
    return false;
}

bool AudioEngine::loadSoundFont(const juce::String& filePath) {
    if (gmSynthProcessor) {
        return gmSynthProcessor->loadSoundFont(filePath);
    }
    return false;
}

bool AudioEngine::loadVstPlugin(int trackIndex, const juce::String& pluginPath) {
    return false;
}

void AudioEngine::clearMidiSequence() {
    if (!currentMidiSequence) {
        currentMidiSequence = std::make_unique<juce::MidiMessageSequence>();
    }
    currentMidiSequence->clear();
}

void AudioEngine::addMidiNote(int noteNumber, double startSeconds, double durationSeconds, float velocity, int channel) {
    if (!currentMidiSequence) {
        currentMidiSequence = std::make_unique<juce::MidiMessageSequence>();
    }
    
    currentMidiSequence->addEvent(juce::MidiMessage::noteOn(channel + 1, noteNumber, velocity), startSeconds);
    currentMidiSequence->addEvent(juce::MidiMessage::noteOff(channel + 1, noteNumber), startSeconds + durationSeconds);
    currentMidiSequence->updateMatchedPairs();
}

void AudioEngine::playPreviewNote(int channel, int noteNumber, float velocity) {
    if (gmSynthProcessor) {
        if (velocity > 0.0f) {
            gmSynthProcessor->playNote(channel, noteNumber, static_cast<int>(velocity * 127.0f));
        } else {
            gmSynthProcessor->stopNote(channel, noteNumber);
        }
    }
}

void AudioEngine::setLoopDuration(double loopSeconds) {
    if (loopSeconds > 0.0) {
        loopDuration = loopSeconds;
    }
}

void AudioEngine::audioDeviceAboutToStart(juce::AudioIODevice* device) {
    sampleRate = device->getCurrentSampleRate();
    mainGraph->setPlayConfigDetails(0, 2, sampleRate, device->getCurrentBufferSizeSamples());
    mainGraph->prepareToPlay(sampleRate, device->getCurrentBufferSizeSamples());
}

void AudioEngine::audioDeviceStopped() {
    mainGraph->releaseResources();
}

void AudioEngine::audioDeviceIOCallbackWithContext(const float* const* inputChannelData, int numInputChannels, float* const* outputChannelData, int numOutputChannels, int numSamples, const juce::AudioIODeviceCallbackContext& context) {
    
    juce::AudioBuffer<float> outputBuffer(const_cast<float**>(outputChannelData), numOutputChannels, numSamples);
    outputBuffer.clear();
    
    juce::MidiBuffer midiBuffer;
    
    if (isPlaying && currentMidiSequence) {
        double blockStartTime = currentPlayheadTime;
        double blockEndTime = blockStartTime + (numSamples / sampleRate);
        
        for (int i = 0; i < currentMidiSequence->getNumEvents(); ++i) {
            auto* evt = currentMidiSequence->getEventPointer(i);
            if (evt->message.getTimeStamp() >= blockStartTime && evt->message.getTimeStamp() < blockEndTime) {
                int samplePos = static_cast<int>((evt->message.getTimeStamp() - blockStartTime) * sampleRate);
                midiBuffer.addEvent(evt->message, samplePos);
            }
        }
        
        currentPlayheadTime = blockEndTime;
        
        if (currentPlayheadTime > loopDuration) {
            currentPlayheadTime = 0.0;
        }
    }
    
    mainGraph->processBlock(outputBuffer, midiBuffer);
}
