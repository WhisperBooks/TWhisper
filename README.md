# TWhisper - whisper.cpp for Delphi (FMX)

A Pascal binding of [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
(local speech-to-text with OpenAI's Whisper models) for Delphi FireMonkey.
It follows the structure and source rules of
[TSteamAPI](https://github.com/G3DGames/TSteamAPI):

- a framework-free core in `lib/` that also compiles with FPC 3.2.2
- one non-visual component, `TWhisper`, for FMX in `fmx/`
- runtime and design-time packages
- a GUI demo and a console demo

Binding checked against whisper.h **1.9.5** (`WHISPER_BINDING_VERSION`).

## Dynamic loading

Nothing is linked statically and there are no `external` declarations. At run
time `TWhisperLib.Load` loads the library with `TWhisperDynLib` (adapted from
TSteamAPI's `TSteamDynLib`) and binds every export by name.

Where the library is looked for, in order:

1. `LibraryPath`, which can be a file or a folder.
2. The executable's folder; on macOS, also the bundle's `Contents/Frameworks`.
3. The operating system's search path.

| Platform | Library | Loaded first, from the same folder |
|---|---|---|
| Windows | `whisper.dll` (MinGW: `libwhisper.dll`) | `ggml-base.dll`, `ggml.dll` |
| Linux / Android | `libwhisper.so`, `libwhisper.so.1` | `libggml-base.so`, `libggml.so` (or `.so.0`) |
| macOS | `libwhisper.dylib`, `libwhisper.1.dylib` | the same, `.dylib` |

`ggml-base` and `ggml` are preloaded by full path, so whisper's
dependencies are already in the process wherever its folder is. Linux dlopen
does not look next to a library, and Windows looks next to the executable,
not next to a whisper.dll loaded from somewhere else. (A build that links its
backends into ggml also works: if ggml does not load, the backend libraries
present are preloaded first.)

**Backends are DLLs too.** The intended build uses `GGML_BACKEND_DL`: every
backend is its own library, and ggml loads them at run time.
- **What gets loaded:** the best of the CPU variants (`ggml-cpu-haswell`,
  `-skylakex`, `-zen4`, ...) plus every GPU backend present (`ggml-cuda`,
  `ggml-vulkan`, `ggml-hip`).
- **Missing runtimes:** a backend whose runtime is missing (no NVIDIA driver,
  no CUDA DLLs) is simply skipped.
- **Who loads them:** whisper.cpp never loads backends itself. Right after
  loading the libraries, `TWhisperLib.Load` calls
  `ggml_backend_load_all_from_path(<library folder>)`.
- **Windows DLL search:** while that runs, the library folder is on the DLL
  search path, so `cudart64_*.dll`, `hipblas.dll` and the like are found next
  to the backends.
- **No backend:** if no backend loads at all, loading a model raises a clear
  `EWhisperError`. Without that check, whisper.cpp would throw a C++
  exception and end the process.

Required exports raise `EWhisperError` on load when missing. All other
exports are optional: check them with `Assigned(Lib.Flat.xxx)`.
`Lib.MissingSymbols` lists the ones the library lacks.

## Getting the libraries and a model

64-bit only: ggml 1.9.5 does not link for 32-bit MSVC (`_pdep_u64` is an
x64-only intrinsic), and the components are not offered for Win32.

Build them with **[whisper-dev](https://github.com/WhisperBooks/whisper-dev)**.
It is a CMake superproject with whisper.cpp as a submodule, and it
collects every library in its `dlls/` folder:

```
git clone --recurse-submodules https://github.com/WhisperBooks/whisper-dev
cd whisper-dev
build.bat            (Windows, any prompt; ./build.sh on Linux / macOS)
```

What it builds:
- **Libraries:** whisper, ggml, ggml-base and every CPU variant.
- **GPU backends:** CUDA and Vulkan (required on Windows); AMD HIP when the
  HIP SDK is installed (`HIP_PATH`).
- **Runtimes:** the CUDA runtime DLLs and the MSVC / OpenMP runtime.

The build uses whisper.cpp's own release options: `BUILD_SHARED_LIBS`,
`GGML_BACKEND_DL`, `GGML_CPU_ALL_VARIANTS` and `GGML_NATIVE=OFF`. Its README
lists the options and the files.

On Windows, HIP is built in a second tree with the HIP SDK's own clang (it
cannot share a tree with MSVC, which CUDA needs), and only `ggml-hip.dll` is
taken from it. Vulkan also runs on AMD cards, so HIP is optional; the
benchmark shows which of the two is faster.

**Runtime notes:**
- `vulkan-1.dll` comes with the GPU driver, and `amdhip64_*.dll` with the
  AMD driver.
- A machine without a given GPU simply doesn't list its device.

Models (ggml format):

```
sh ./models/download-ggml-model.sh base.en      # or tiny, small, medium, large-v3-turbo, ...
sh ./models/download-vad-model.sh silero-v6.2.0 # optional, for Vad = True
```

`*.en` models are English only; the others are multilingual and can
translate to English. Audio must be 16 kHz mono float. `Whisper.Audio` reads
WAV files in any rate, bit depth and channel count and converts them. Convert
compressed audio first, for example:
`ffmpeg -i in.mp3 -ar 16000 -ac 1 -c:a pcm_s16le out.wav`.

## Choosing the device (and model)

whisper.cpp can be told which device to use, but only by position: its
`gpu_device` counts the GPU and integrated-GPU devices in ggml's list. ggml
loads backends in a fixed order (CUDA, HIP, Vulkan), so on an NVIDIA machine
`CUDA0` always comes before `Vulkan0`, and whisper.cpp left alone always
takes CUDA. On some systems Vulkan is faster for real transcription, and only
timing real transcription tells. The binding therefore:

- lists the devices: `TWhisperLib.Devices` / `TWhisper.Devices` give name
  (`CPU`, `CUDA0`, `Vulkan0`, `ROCm0`, ...), description, backend, type and
  memory;
- selects one by name: `TWhisper.Device := 'Vulkan0'`, or
  `TWhisperLib.ContextParamsFor` for the classes. `'CPU'` means no GPU. An
  unknown name falls back to the default with a warning, so a program keeps
  working when a GPU disappears;
- times them: `TWhisperBenchmark` / `TWhisper.BenchmarkFileAsync`.

**What the benchmark measures.** It doesn't use whisper.cpp's own bench,
which times only the encoder. For each model and device it:
1. loads the model onto the device,
2. runs a warm-up transcription (shader / kernel compilation),
3. runs a timed `whisper_full` transcription of your audio with your
   settings.

**What it reports:** load, warm-up and run times, speed (audio seconds per
second) and the text, for every model x device pair. `Best` gives the
fastest pair, or the fastest device for one model. Store the winner in
`Device` (the demo saves it in its settings).

Speed alone doesn't pick a *model*, because bigger models are more accurate.
With several models timed, the demo keeps the selected model, uses its
fastest device, and shows the fastest pair overall.

## Using the component

1. Build and install the packages (see below), drop a `TWhisper`
   (palette page "Whisper") on a form and set `ModelFile`.
2. Set `Active := True` (in code, or in the form file). This loads the
   library, checks the record layout and loads the model. A failure fires
   `OnLoadFailed`, or is shown if that event is not assigned. It never
   raises.
3. Call `TranscribeFileAsync('speech.wav')` or `TranscribeAsync(Samples)`.
   `OnSegment`, `OnProgress`, `OnLog` and finally `OnComplete` arrive on the
   main thread. `Cancel` stops a run and keeps the segments so far.

```pascal
procedure TfrmMain.Whisper1Segment(Sender: TObject; const ASegment: TWhisperSegment);
begin
  memText.Lines.Add(Format('[%s --> %s] %s', [WhisperTimeToStr(ASegment.T0),
    WhisperTimeToStr(ASegment.T1), ASegment.Text]));
end;
```

`Transcribe` / `TranscribeFile` run on the calling thread instead. Set
`Device` before `Active` to choose the compute device (see above). Published
properties cover the common settings (Language, Translate, Threads,
Strategy, BeamSize, TokenTimestamps, MaxSegmentLength, InitialPrompt, Vad,
...). `Params` and `OnBeforeRun` give access to every field of
`whisper_full_params`. `WhisperSegmentsToSrt`, `WhisperSegmentsToVtt` and
`WhisperSegmentsToText` export a result.

Without the component (a console program, a service) use the classes in
`Whisper.Core` directly: `TWhisperModel`, `TWhisperParams` and `TWhisperRun`.
See `demos/WhisperConsole`. The flat API is in `TWhisperLib.Instance.Flat`.

## Layout

```
lib/       framework-free units (Delphi + FPC 3.2.2)
  Whisper.inc           compiler / platform / C ABI settings ({$I} in every unit)
  Whisper.Layout.inc    GENERATED by tools/verify_layout.py - C sizes and offsets
  Whisper.Types         constants, enums, C records, result records
  Whisper.DynLib        dynamic library loading (from TSteamAPI)
  Whisper.API           TWhisperLib: loading, backends, devices, every export, ABI shims, layout check, log
  Whisper.Audio         WAV reader, 16-bit PCM conversion, windowed-sinc resampler
  Whisper.Core          TWhisperModel, TWhisperParams, TWhisperRun, TWhisperBenchmark, text export
  Whisper.Components    TCustomWhisper (lifecycle, worker thread, main-thread events)
fmx/       Whisper.FMX (TWhisper), Whisper.FMX.Reg (design time)
packages/  Whisper (runtime, rtl), WhisperFMX (runtime), dclWhisperFMX (design)
demos/     WhisperDemo (FMX), WhisperConsole (console, smoke test)
tools/     verify_layout.py, pasdoc_check.py
```

## Packages and demos

Only the `.dpk` / `.dpr` sources are included. Delphi creates the matching
`.dproj` (and the `.res`) when you open them.

1. Open and build `packages/Whisper.dpk`, then `WhisperFMX.dpk`, for every
   64-bit target platform you use.
2. Install `dclWhisperFMX.dpk` for the IDE you run. With the 32-bit IDE that
   means compiling `Whisper` and `WhisperFMX` for Win32 too: the IDE loads
   them, but never loads whisper.dll, so no 32-bit DLL is needed. With the
   64-bit IDE (Delphi 12.2+) build all three for Win64 and Win32 drops out.
3. The demos name the library units with paths (`in '..\..\lib\...'`), so
   they compile without any search-path setup. Opening the demo's form in
   the designer needs `dclWhisperFMX` installed.
4. Copy the whisper.cpp libraries next to the built executable (for example
   `demos/WhisperDemo/Win64/Debug`), or set `LibraryPath`.

Run **WhisperConsole first** on every new platform:

```
WhisperConsole --check                                       library, layout check, device list
WhisperConsole --bench ggml-base.en.bin jfk.wav              time every device
WhisperConsole --bench ggml-base.bin talk.wav en --also ggml-small.bin --seconds 60
WhisperConsole ggml-base.en.bin jfk.wav --device Vulkan0     transcribe on a chosen device
WhisperConsole ggml-base.bin speech.wav auto --tokens        detect language, token data
```

## C ABI details (why the binding is safe)

- **Records.** Layout is natural C layout (`{$ALIGN 8}`, 4-byte enums;
  FPC `{$packrecords C}`). Nested anonymous structs are flattened
  (`greedy_best_of`, `vad_params_threshold`) because the compilers disagree
  on aligning a record inside a record. `tools/verify_layout.py` asks clang
  for the size and every field offset on 9 targets and writes
  `Whisper.Layout.inc`. `TWhisperLib.CheckLayout` compares that table with
  what the Pascal compiler produced, at run time, on the actual platform.
  It also compares the library's default params with whisper.h's documented
  values, which catches a DLL built from a different header.
  `TWhisper.CheckLayout` (default on) refuses a library that fails.
- **Structs passed by value.** `whisper_full` and
  `whisper_init_from_file_with_params` take their params struct by value.
  clang shows the lowering:
  - **Win64 and every ARM64 target:** a pointer to a caller-made copy. The
    binding passes `@Copy` explicitly (`WHISPER_PARAMS_BY_POINTER`), with a
    fresh copy per call, because the callee owns it.
  - **x86-64 Unix (and Win32, not shipped):** the copy goes on the stack. The binding
    passes a value record and relies on the compiler, as Delphi's own
    `WindowFromPoint(TPoint)` and macOS `CGRect` imports do.
- **Struct returned by value.** `whisper_full_get_token_data` returns its
  struct through a hidden result pointer (sret).
  - **x86-64 (and Win32 MSVC, not shipped):** the hidden pointer is an ordinary first
    argument, so it is declared explicitly (`WHISPER_SRET_AS_PARAM`).
  - **ARM64:** the pointer travels in X8, so the compiler's record return is
    used.
  `verify_layout.py` re-checks all of these choices on every whisper.cpp
  update.
- **Floating point.** ggml computes with NaN and infinity on purpose, and
  Delphi unmasks FPU exceptions. Every computing call masks them on the
  calling thread (`WhisperMaskFPU`).
- **Strings.** All strings are UTF-8, including paths: whisper.cpp
  converts them to wide characters on Windows.
- **Callbacks.** Callbacks never let an exception escape into C. A failing
  event handler cancels the run, and the exception is re-raised afterwards.

## Not covered (yet)

- **iOS:** marked unsupported. whisper.cpp ships an XCFramework, but this
  binding loads plain shared libraries.
- **Stand-alone VAD API** (`whisper_vad_*`): it passes small structs by
  value, a different ABI case on every platform. VAD is available through
  `Vad` / `VadModelFile` on a normal run.
- **Model-loader callbacks, deprecated init functions, grammar helpers:**
  the raw `grammar_rules` field is there.
- **Microphone capture:** feed captured 16-bit PCM through
  `WhisperPcm16ToMono` + `WhisperResample`.
- **VCL and LCL components:** `TCustomWhisper` is framework-free; a
  `Whisper.VCL` / `Whisper.LCL` unit only needs to publish the properties
  and override `ShowHandlerException`, as in TSteamAPI.

## Checks before delivery

```
python3 tools/pasdoc_check.py                       PasDoc on everything, ASCII only
python3 tools/verify_layout.py <whisper.cpp> --write  after updating whisper.cpp
```
