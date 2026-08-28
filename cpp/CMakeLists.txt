cmake_minimum_required(VERSION 3.15)
project(sridaw_juce_bridge VERSION 1.0.0)

# Make sure we build a shared library so Dart FFI can load it
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Fetch JUCE from GitHub
include(FetchContent)
FetchContent_Declare(
    juce
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG        8.0.0 # Use latest stable JUCE 8
)
FetchContent_MakeAvailable(juce)

# Add our bridge library
add_library(sridaw_juce SHARED
    src/audio_engine.cpp
    src/synth_processor.cpp
    src/gain_pan_processor.cpp
    src/ffi_bridge.cpp
)

# Link JUCE modules we need
target_link_libraries(sridaw_juce PRIVATE
    juce::juce_audio_devices
    juce::juce_audio_formats
    juce::juce_audio_processors
    juce::juce_audio_utils
    juce::juce_core
    juce::juce_data_structures
    juce::juce_events
)

# For JUCE, we need to add the module headers to include directories
target_include_directories(sridaw_juce PRIVATE src)

# Enable VST3 and AU Hosting
target_compile_definitions(sridaw_juce PRIVATE 
    JUCE_PLUGINHOST_VST3=1 
    JUCE_PLUGINHOST_AU=1
)

# Ensure C++17 or C++20 for modern JUCE
target_compile_features(sridaw_juce PRIVATE cxx_std_20)
