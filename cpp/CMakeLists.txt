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

# ---------------------------------------------------------------------------
# FluidSynth (General MIDI soft synthesizer)
#
# Since FluidSynth provides its own CMake project that uses a bunch of cache
# variables (options), we populate the source and drop it in as a subdirectory.
# We override the caches so that:
#   * it does NOT need GLib (osal=cpp11, added in 2.5.x)
#   * it does NOT pull in libinstpatch / libsndfile / any OS audio driver
#   * it builds as a STATIC library (libfluidsynth.a) so it is linked straight
#     into libsridaw_juce.so for Dart FFI.
# ---------------------------------------------------------------------------
set(osal "cpp11" CACHE STRING "OS abstraction layer to use (no GLib)" FORCE)

foreach(opt IN ITEMS
    enable-alsa
    enable-aufile
    enable-coreaudio
    enable-coremidi
    enable-dbus
    enable-dsound
    enable-examples
    enable-framework
    enable-jack
    enable-ladspa
    enable-libinstpatch
    enable-libsndfile
    enable-midishare
    enable-network
    enable-oss
    enable-pipewire
    enable-portaudio
    enable-pulseaudio
    enable-readline
    enable-sdl3
    enable-systemd
    enable-tests
    enable-waveout
    enable-winmidi
    enable-wasapi
    )
    set(${opt} OFF CACHE BOOL "" FORCE)
endforeach()

# We only want libfluidsynth; skip FluidSynth's own example/test subprojects.
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

# float DSP output (matches JUCE's float32 buffers directly)
set(enable-floats ON CACHE BOOL "" FORCE)
# we do not want OpenMP on Android (FluidSynth ships Android binaries without it)
set(enable-openmp OFF CACHE BOOL "" FORCE)
# static library so everything lands inside libsridaw_juce.so
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)

FetchContent_Declare(
    fluidsynth
    GIT_REPOSITORY https://github.com/FluidSynth/fluidsynth.git
    GIT_TAG        v2.5.7
)
# Populate only (do NOT call FetchContent_MakeAvailable, which would add the
# whole FluidSynth project to the default build). We add it EXCLUDE_FROM_ALL so
# its CLI executable, example programs and test suite are NOT built by default
# (several fail to compile under the NDK and are not needed). Only libfluidsynth
# is pulled in, as a dependency of our sridaw_juce target.
FetchContent_Populate(fluidsynth)
add_subdirectory(${fluidsynth_SOURCE_DIR} ${fluidsynth_BINARY_DIR} EXCLUDE_FROM_ALL)

# Add our bridge library
add_library(sridaw_juce SHARED
    src/audio_engine.cpp
    src/gm_synth_processor.cpp
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
    libfluidsynth
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
