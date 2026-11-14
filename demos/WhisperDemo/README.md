# WhisperDemo - running and deploying (Windows)

FireMonkey demo of TWhisperAPI: choose a model and a compute device, benchmark
the devices, transcribe an audio file (a WAV directly; MP3, M4A / M4B, FLAC,
Ogg, ... through the TFFmpegAPI component of the FFmpegAPI submodule, which
decodes it to 16 kHz mono on a worker thread), save SubRip / WebVTT / text, and with
"Word timings" save the words as an Audacity label track or JSON.

## Before the first build

The demo uses the library like any user project: build the runtime packages
**FFmpegAPI**, **WhisperAPI**, **WhisperAPIFMX** and **FFmpegAPIFMX** for the
same platform first (open `WhisperAPI.groupproj` at the repository root and
build all - it builds the packages before the demos). Opening the form in the
designer needs **dclWhisperAPIFMX** and **dclFFmpegAPIFMX** installed.

## Next to WhisperDemo.exe

Everything from **whisper-dev's `dlls\` folder** (github.com/WhisperBooks/whisper-dev,
`build.bat`), copied next to the executable, e.g. `Win64\Debug\`:

| Files | |
|---|---|
| `whisper.dll`, `ggml.dll`, `ggml-base.dll` | the libraries |
| `ggml-cpu-*.dll` | CPU variants (the best one is picked at run time) |
| `ggml-cuda.dll`, `cudart64_*.dll`, `cublas64_*.dll`, `cublasLt64_*.dll` | CUDA backend and its runtime |
| `ggml-vulkan.dll` | Vulkan backend (`vulkan-1.dll` comes with the GPU driver) |
| `ggml-hip.dll`, `hipblas.dll`, `rocblas.dll`, `rocblas\library\` | AMD HIP backend, if built |
| `msvcp140.dll`, `vcruntime140*.dll`, `vcomp140.dll` | MSVC + OpenMP runtime |
| `avutil-60.dll`, `swresample-6.dll`, `avcodec-62.dll`, `avformat-62.dll` | FFmpeg 8 (a "shared" build) - only for audio other than WAV |

Instead of copying, the folder can be on PATH (TWhisperAPI locates the library
and loads the backends from its folder) - copying is what a release ships.

Not shipped next to the program: the models (`ggml-*.bin`, chosen in the demo
with Browse; whisper.cpp's `models\download-ggml-model.cmd base.en`) and the
audio.

## Testing

1. Browse to a model, pick the audio (`samples\jfk.wav` of whisper.cpp).
2. The device list shows what the loaded backends offer (`CPU`, `CUDA0`,
   `Vulkan0`, ...). Benchmark times every device (and every model of the
   folder with "Benchmark all models") and selects the fastest device.
3. Load model, Transcribe. The log shows the device the model runs on.
4. Word timings: tick "Word timings" BEFORE Load model (DTW is set up when
   the model loads; the log says which alignment heads). After the run,
   Save as... "Words: Audacity labels" and import that file in Audacity
   (Audacity 3: File > Import > Labels; Audacity 4: File > Import) over the audio to check the timings by ear.

Settings (model folder, model, audio, device, language, word timings) are kept per user in
`%APPDATA%\G3DGames\WhisperDemo\WhisperDemo.ini`.
