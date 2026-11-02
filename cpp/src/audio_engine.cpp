#include "audio_engine.h"
#include <cmath>
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
    // On Android the audio system is sometimes not ready immediately at app
    // cold-start, so the first open attempt can fail (or open a device whose
    // callback thread never starts). Retry a few times — this is exactly what
    // happens when the user later taps "Re-init", which makes audio work.
    juce::String error;
    const int maxAttempts = 4;
    for (int attempt = 0; attempt < maxAttempts; ++attempt) {
        error = deviceManager->initialiseWithDefaultDevices(0, 2);
        if (error.isEmpty()) break;
        std::cerr << "[SriDAW] AudioEngine initialise attempt " << attempt
                  << " failed: " << error.toStdString() << std::endl;
        deviceManager->closeAudioDevice();
        if (attempt + 1 < maxAttempts) juce::Thread::sleep(250);
    }
    if (error.isNotEmpty()) {
        std::cerr << "[SriDAW] AudioEngine failed to initialize: " << error.toStdString() << std::endl;
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

    // Android loads its bundled GeneralUser SoundFont through the Flutter
    // asset channel (a few ms after init); on desktop nothing does that, so
    // pick up a repo/system copy here or every dev build renders silence.
    if (!isSoundFontLoaded()) {
        const juce::String candidates[] = {
            juce::String("GeneralUser-GS.sf2"),
            juce::String("android/app/src/main/assets/soundfonts/GeneralUser-GS.sf2"),
            juce::String("/usr/share/soundfonts/GeneralUser-GS.sf2"),
            juce::String("/usr/share/soundfonts/FluidR3_GM.sf2"),
            juce::String("/usr/share/sounds/sf2/FluidR3_GM.sf2"),
        };
        const juce::File cwd = juce::File::getCurrentWorkingDirectory();
        for (const auto& candidate : candidates) {
            const juce::File f = juce::File::isAbsolutePath(candidate)
                ? juce::File(candidate)
                : cwd.getChildFile(candidate);
            if (f.existsAsFile()) {
                loadSoundFont(f.getFullPathName());
                break;
            }
        }
    }
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
        // The Dart transport owns the playhead position (it calls
        // setPlayheadTime so a resume continues where the visual playhead
        // stopped), so do not rewind here.
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
    } else {
        // Notes still scheduled past the stop point would never be dispatched
        // again, so release everything that is currently ringing.
        allSoundsOff();
    }
}

void AudioEngine::setPlayheadTime(double seconds) {
    currentPlayheadTime = juce::jmax(0.0, seconds);
}

void AudioEngine::allSoundsOff() {
    if (gmSynthProcessor) gmSynthProcessor->allSoundsOff();
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

bool AudioEngine::isSoundFontLoaded() const {
    return gmSynthProcessor && gmSynthProcessor->isSoundFontLoaded();
}

juce::String AudioEngine::getSoundFontPath() const {
    if (gmSynthProcessor) return gmSynthProcessor->getSoundFontPath();
    return {};
}

bool AudioEngine::loadVstPlugin(int trackIndex, const juce::String& pluginPath) {
    if (trackIndex < 0 || (size_t) trackIndex >= tracks.size()) return false;

    // VST3/AU hosting. The format manager is built once and kept alive for the
    // lifetime of the engine, because plugin instances reference their format.
    static juce::AudioPluginFormatManager formatManager;
    static bool formatsRegistered = false;
    if (!formatsRegistered) {
        formatManager.addDefaultFormats(); // VST3, AU, etc. (see JUCE_PLUGINHOST_*)
        formatsRegistered = true;
    }

    juce::File pluginFile(pluginPath);
    if (!pluginFile.exists()) {
        std::cerr << "[SriDAW] Plugin file not found: " << pluginPath.toStdString() << std::endl;
        return false;
    }

    // Ask every registered format whether it recognises this file, and collect
    // the plugin descriptions it reports.
    juce::OwnedArray<juce::PluginDescription> descriptions;
    for (int i = 0; i < formatManager.getNumFormats(); ++i) {
        auto* format = formatManager.getFormat(i);
        if (format != nullptr && format->fileMightContainThisPluginType(pluginPath)) {
            format->findAllTypesForFile(descriptions, pluginPath);
        }
    }

    if (descriptions.isEmpty()) {
        std::cerr << "[SriDAW] No plugin description for: " << pluginPath.toStdString() << std::endl;
        return false;
    }

    const bool isInstrument = descriptions[0]->isInstrument;
    juce::String error;
    auto instance = formatManager.createPluginInstance(*descriptions[0], sampleRate, 512, error);

    if (instance == nullptr || error.isNotEmpty()) {
        std::cerr << "[SriDAW] Failed to create plugin instance: " << error.toStdString() << std::endl;
        return false;
    }

    instance->prepareToPlay(sampleRate, 512);

    auto pluginNode = mainGraph->addNode(std::move(instance));
    if (pluginNode == nullptr) {
        std::cerr << "[SriDAW] Failed to add plugin node to graph" << std::endl;
        return false;
    }

    // Instruments need MIDI; effects also accept it. Route MIDI input in and
    // stereo audio out to the master output (mixing alongside the GM synth).
    if (isInstrument || pluginNode->getProcessor()->acceptsMidi()) {
        mainGraph->addConnection({
            { midiInputNode->nodeID, juce::AudioProcessorGraph::midiChannelIndex },
            { pluginNode->nodeID, juce::AudioProcessorGraph::midiChannelIndex }
        });
    }

    for (int ch = 0; ch < 2; ++ch) {
        mainGraph->addConnection({
            { pluginNode->nodeID, ch },
            { audioOutputNode->nodeID, ch }
        });
    }

    // Store the node in track data for later management.
    tracks[trackIndex].synthNode = pluginNode;

    std::cout << "[SriDAW] Loaded plugin on track " << trackIndex
              << ": " << pluginPath.toStdString() << std::endl;
    return true;
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
    
    if (isPlaying && currentMidiSequence && loopDuration > 0.0) {
        double blockStartTime = currentPlayheadTime;
        if (blockStartTime >= loopDuration)
            blockStartTime = std::fmod(blockStartTime, loopDuration);
        const double blockEndTime = blockStartTime + (numSamples / sampleRate);

        // Dispatch the events of [from, to) with sample offsets relative to
        // [blockBase, blockBase + numSamples/sampleRate).
        auto dispatch = [&](double from, double to, double blockBase) {
            for (int i = 0; i < currentMidiSequence->getNumEvents(); ++i) {
                auto* evt = currentMidiSequence->getEventPointer(i);
                const double t = evt->message.getTimeStamp();
                if (t >= from && t < to) {
                    const int samplePos =
                        static_cast<int>((t - blockBase) * sampleRate);
                    midiBuffer.addEvent(evt->message, samplePos);
                }
            }
        };

        if (blockEndTime <= loopDuration) {
            dispatch(blockStartTime, blockEndTime, blockStartTime);
            currentPlayheadTime = blockEndTime;
        } else {
            // The block crosses the loop point: play up to the bar end, then
            // the wrapped head of the next pass. Dropping the tail here would
            // silently swallow the last hit of every loop.
            dispatch(blockStartTime, loopDuration, blockStartTime);
            const double remainder = blockEndTime - loopDuration;
            dispatch(0.0, remainder, 0.0);
            currentPlayheadTime = remainder;
        }
    }
    
    mainGraph->processBlock(outputBuffer, midiBuffer);
}
