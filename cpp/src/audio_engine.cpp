#include "audio_engine.h"
#include "synth_processor.h"
#include "gain_pan_processor.h"
#include <iostream>

AudioEngine::AudioEngine() {
    deviceManager = std::make_unique<juce::AudioDeviceManager>();
    mainGraph = std::make_unique<juce::AudioProcessorGraph>();
    tracks.resize(6);
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
    
    for (int i = 0; i < tracks.size(); ++i) {
        // Synth Node
        auto synth = std::make_unique<BuiltInSynthProcessor>();
        tracks[i].synthNode = mainGraph->addNode(std::move(synth));
        
        // Gain/Pan Node
        auto gainPan = std::make_unique<GainPanProcessor>();
        gainPan->setVolume(tracks[i].volume);
        gainPan->setPan(tracks[i].pan);
        gainPan->setMute(tracks[i].mute);
        tracks[i].gainNode = mainGraph->addNode(std::move(gainPan));
        
        // Connect MIDI Input -> Synth MIDI Input
        mainGraph->addConnection({ { midiInputNode->nodeID, juce::AudioProcessorGraph::midiChannelIndex },
                                   { tracks[i].synthNode->nodeID, juce::AudioProcessorGraph::midiChannelIndex } });
                                   
        // Connect Synth Audio Output -> Gain/Pan Audio Input
        for (int ch = 0; ch < 2; ++ch) {
            mainGraph->addConnection({ { tracks[i].synthNode->nodeID, ch },
                                       { tracks[i].gainNode->nodeID, ch } });
        }
        
        // Connect Gain/Pan Audio Output -> Master Output
        for (int ch = 0; ch < 2; ++ch) {
            mainGraph->addConnection({ { tracks[i].gainNode->nodeID, ch },
                                       { audioOutputNode->nodeID, ch } });
        }
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
}

float AudioEngine::getMasterVolume() const { return masterVolume; }

void AudioEngine::setTrackVolume(int index, float volume) {
    if (index >= 0 && index < tracks.size()) {
        tracks[index].volume = volume;
        if (tracks[index].gainNode) {
            if (auto* gp = dynamic_cast<GainPanProcessor*>(tracks[index].gainNode->getProcessor())) {
                gp->setVolume(volume);
            }
        }
    }
}

void AudioEngine::setTrackMute(int index, bool mute) {
    if (index >= 0 && index < tracks.size()) {
        tracks[index].mute = mute;
        if (tracks[index].gainNode) {
            if (auto* gp = dynamic_cast<GainPanProcessor*>(tracks[index].gainNode->getProcessor())) {
                gp->setMute(mute);
            }
        }
    }
}

void AudioEngine::setTrackSolo(int index, bool solo) {
    if (index >= 0 && index < tracks.size()) tracks[index].solo = solo;
}

void AudioEngine::setTrackPan(int index, float pan) {
    if (index >= 0 && index < tracks.size()) {
        tracks[index].pan = pan;
        if (tracks[index].gainNode) {
            if (auto* gp = dynamic_cast<GainPanProcessor*>(tracks[index].gainNode->getProcessor())) {
                gp->setPan(pan);
            }
        }
    }
}

float AudioEngine::getTrackPeakLevel(int index) {
    if (index >= 0 && index < tracks.size()) {
        if (tracks[index].gainNode) {
            if (auto* gp = dynamic_cast<GainPanProcessor*>(tracks[index].gainNode->getProcessor())) {
                return gp->getLastPeakLevel();
            }
        }
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

bool AudioEngine::loadTrackSample(int trackIndex, const juce::String& filePath) {
    if (trackIndex >= 0 && trackIndex < tracks.size() && tracks[trackIndex].synthNode) {
        if (auto* sampler = dynamic_cast<BuiltInSynthProcessor*>(tracks[trackIndex].synthNode->getProcessor())) {
            return sampler->loadSample(filePath);
        }
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

void AudioEngine::addMidiNote(int noteNumber, double startSeconds, double durationSeconds, float velocity) {
    if (!currentMidiSequence) {
        currentMidiSequence = std::make_unique<juce::MidiMessageSequence>();
    }
    
    currentMidiSequence->addEvent(juce::MidiMessage::noteOn(1, noteNumber, velocity), startSeconds);
    currentMidiSequence->addEvent(juce::MidiMessage::noteOff(1, noteNumber), startSeconds + durationSeconds);
    currentMidiSequence->updateMatchedPairs();
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
        
        // Find events in this time window and add to MidiBuffer
        for (int i = 0; i < currentMidiSequence->getNumEvents(); ++i) {
            auto* evt = currentMidiSequence->getEventPointer(i);
            if (evt->message.getTimeStamp() >= blockStartTime && evt->message.getTimeStamp() < blockEndTime) {
                int samplePos = static_cast<int>((evt->message.getTimeStamp() - blockStartTime) * sampleRate);
                midiBuffer.addEvent(evt->message, samplePos);
            }
        }
        
        currentPlayheadTime = blockEndTime;
        
        // Loop based on dynamic loopDuration
        if (currentPlayheadTime > loopDuration) {
            currentPlayheadTime = 0.0;
        }
    }
    
    // Process the graph (MIDI goes into synths -> Audio comes out to outputBuffer)
    mainGraph->processBlock(outputBuffer, midiBuffer);
    
    // Apply Mixer Levels and compute Peaks
    for (int ch = 0; ch < outputBuffer.getNumChannels(); ++ch) {
        float* channelData = outputBuffer.getWritePointer(ch);
        float peak = 0.0f;
        
        for (int s = 0; s < numSamples; ++s) {
            // Very simple master mix since all synths output straight to outputBuffer right now
            channelData[s] *= masterVolume; 
            
            float absSample = std::abs(channelData[s]);
            if (absSample > peak) peak = absSample;
        }
        
        // In a real mixer, we'd process each track's output buffer individually.
        // For the demo, we'll assign the master peak to Track 0 so the UI reacts.
        if (ch == 0) {
            tracks[0].lastPeakLevel = peak;
        }
    }
}
