[app]
title = SriDAW
package.name = sridaw
package.domain = org.example
source.include_exts = py,png,jpg,kv,atlas,ttf,txt,md
version = 1.0
orientation = portrait
source.dir = .
requirements = python3,kivy,pyjnius,android,pygments,six
source.exclude_patterns = license,*.pyc,*.pyo,*.pyd,.git,.gitignore,.github/,build.sh,debug_tools.py,build_instructions.md,troubleshoot.py,simple_build.py,test_minimal.py,Dockerfile.build,docker_build.sh

[buildozer]
log_level = 2
warn_on_root = 0

[app.android]
android.api = 33
android.minapi = 24
# android.ndk = 25b
android.sdk = 33
android.permissions = WRITE_EXTERNAL_STORAGE,READ_EXTERNAL_STORAGE,INTERNET,READ_MEDIA_AUDIO,READ_MEDIA_VIDEO,READ_MEDIA_IMAGES
android.arch = arm64-v8a
android.add_src = 
android.gradle_dependencies = 
android.java_options = -Xms512m -Xmx2048m
p4a.branch = master
android.accept_sdk_license = True