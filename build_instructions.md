# Building SriDAW Android APK

## Prerequisites
You need a Linux system (Ubuntu/Debian recommended) or WSL on Windows with:

```bash
# Install system dependencies
sudo apt update
sudo apt install -y git zip unzip openjdk-17-jdk python3-pip autoconf libtool pkg-config zlib1g-dev libncurses-dev cmake libffi-dev libssl-dev

# Install buildozer (use --break-system-packages on newer Ubuntu versions)
pip3 install --user buildozer
# OR
pip3 install --user --break-system-packages buildozer
```

## Build Steps

1. Clone or download this project
2. Navigate to the project directory
3. Clean any previous builds:
   ```bash
   rm -rf .buildozer
   ```
4. Build the APK using Docker (recommended):
   ```bash
   docker build -t sridaw-build -f Dockerfile.build .
   docker run --rm -v $(pwd):/app sridaw-build
   ```
   Or build directly:
   ```bash
   buildozer android debug
   ```

## First Build
The first build will take a long time (30-60 minutes) as it downloads:
- Android SDK
- Android NDK  
- Python-for-android
- All dependencies

## Output
The APK will be created in: `bin/sridaw-1.0-arm64-v8a-debug.apk`

## Troubleshooting

### If build fails:
1. Check buildozer logs in `.buildozer/`
2. Try cleaning: `buildozer android clean`
3. Update buildozer: `pip3 install --upgrade buildozer`

### Common issues:
- Java version conflicts: Use OpenJDK 17
- Missing system packages: Install build-essential
- PPA errors: Avoid using external PPAs like openjdk-r/ppa on newer Ubuntu versions as they may not be supported. Use official repositories instead.

### Android permissions:
The app requests:
- WRITE_EXTERNAL_STORAGE (for saving files)
- READ_EXTERNAL_STORAGE (for loading files)
- INTERNET (for potential future features)

## Testing
Install the APK on Android device:
```bash
adb install bin/sridaw-1.0-arm64-v8a-debug.apk
```

Or transfer the APK file to your device and install manually.