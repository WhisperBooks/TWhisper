# redistributable_bin

Put the whisper.cpp shared libraries you built here, one folder per platform
(for example `Win64/`, `Win32/`, `Linux64/`, `macOS/`), and copy the right
set next to each executable. Nothing in this folder except this file is
tracked (see .gitignore).

- Windows: whisper.dll, ggml.dll, ggml-base.dll, ggml-cpu.dll (+ any GPU
  backend DLLs and their runtimes).
- Linux: libwhisper.so*, libggml.so*, libggml-base.so*, libggml-cpu.so*.
- macOS: libwhisper*.dylib, libggml*.dylib (build with an @loader_path rpath).

Models (ggml-*.bin) are not kept here either: download them with whisper.cpp's
models/download-ggml-model.sh (or .cmd) and point TWhisperAPI.ModelFile at them.
