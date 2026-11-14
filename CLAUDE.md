# CLAUDE.md - working rules for this repository

Read README.md first, then this file. Keep both up to date with every change.
The rules follow TSteamAPI's CLAUDE.md (same owner, same conventions); where
this file is silent, TSteamAPI's rules apply.

## Project
Pascal binding of whisper.cpp (checked against whisper.h 1.9.5), loaded
DYNAMICALLY at run time (owner, 2026-11-13: "must use dynamic loading of
dlls, also in TSteamAPI"): no `external` declarations, no static linking.
Target order: FMX, then VCL, then Free Pascal. 64-bit only (owner,
2026-11-13: no 32-bit build; ggml 1.9.5 does not link for 32-bit MSVC
anyway): no pidWin32 in WHISPER_COMPONENT_PLATFORMS. lib/ keeps compiling
for Win32 because a 32-bit IDE loads the design-time package; the Win32 ABI
branches in Whisper.inc stay (FPC, verify_layout.py). Delphi 13 is the reference
compiler; lib/ must also compile with FPC 3.2.2.

Backends (owner, 2026-11-13): "as flexible as possible, this is why it MUST
use DLLs"; CPU, Vulkan and CUDA at a minimum, AMD (HIP) if available. So the
whisper.cpp build is GGML_BACKEND_DL + GGML_CPU_ALL_VARIANTS +
GGML_NATIVE=OFF + CUDA + Vulkan (+ HIP from a second clang tree), done by
the owner's whisper-dev repo (CMake superproject, whisper.cpp submodule,
output in its dlls/ folder; its CMakeLists.txt was written in session 2). whisper.cpp does not load backends itself:
TWhisperLib.Load calls ggml_backend_load_all_from_path(library folder) - with
the folder on the Windows DLL search path - and refuses to load a model when
no device is listed (whisper.cpp would throw a C++ exception and end the
process).

Device choice (owner): whisper.cpp left alone takes the first GPU in ggml's
list (CUDA before HIP before Vulkan), but Vulkan can be faster in real
transcription; whisper's own bench times only the encoder. So: device by
NAME (TWhisperAPI.Device, TWhisperLib.ContextParamsFor -> use_gpu / gpu_device,
whose ordinal counts GPU + IGPU devices in registry order), and
TWhisperBenchmark times a real whisper_full transcription of the user's
audio, per model x device (warm-up first). The model is selectable too;
speed never picks the model on its own (accuracy).

## Layout rules
- `lib/` - framework-free units only. No FMX, VCL or LCL here, ever.
- `fmx/` - Whisper.FMX (TWhisperAPI) and Whisper.FMX.Reg (design time). They
  include `..\lib\Whisper.inc` by relative path (Delphi looks for an include
  next to the unit or on the search path).
- GENERATED, never edit by hand: `lib/Whisper.Layout.inc`
  (tools/verify_layout.py).
- The FIELDS table of tools/verify_layout.py, the record declarations in
  Whisper.Types and the Add(...) list of TWhisperLib.CheckLayout must list
  the same fields in the same order. Adding a field = all three + rerun
  `verify_layout.py --write`.
- `demos/<Name>/` - `<Name>.dpr` + `<Name>.dproj` + `README.md` (the
  project page: what goes next to the executable) in the folder, other
  sources in `demos/<Name>/src/`. Demos list and search ONLY their own
  sources: the library comes from the runtime packages' DCUs in Delphi's
  Dcp folder, exactly as for a user's project (as TSteamAPI). No demo source
  includes Whisper.inc.
- `packages/` - WhisperAPI (runtime, rtl only), WhisperAPIFMX (runtime),
  dclWhisperAPIFMX (design). Runtime packages write their DCUs to
  $(BDSCOMMONDIR)\Dcp\$(Platform) (Win32: \Dcp). Runtime packages also
  build for Win32 (32-bit IDE); programs are 64-bit only.
- `WhisperAPI.groupproj` at the root lists every project: applications first,
  then runtime packages, then design; build order from Dependencies and the
  Build / Clean / Make targets (runtime, design, apps).
- Component naming: the framework component is `TWhisperAPI`, descending from
  the framework-free `TCustomWhisper` (lib/Whisper.Components). A framework
  unit only publishes properties and overrides ShowHandlerException.

## Source rules (from TSteamAPI)
- Never write a stored value as a literal in text: format the constant or
  property into the string. Form-file captions hold no numbers.
- ASCII only in sources; use `#$xxxx` codes for other characters.
- `{$I Whisper.inc}` right after the `unit` line of every library unit.
- RTL units unscoped in `lib/` (`SysUtils`, `Classes`, ...).
- Portable callbacks use method pointers (`of object`). Anonymous methods
  only inside `{$ifdef WHISPER_ANONYMOUS_METHODS}`.
- No class constructors / destructors in `lib/`.
- No managed fields in a record C sees, nor in a record typed constant.
- C `bool` -> `Boolean`; C enums 4 bytes (Whisper.inc); `size_t` ->
  `NativeUInt`; nested C structs are flattened (`<struct>_<field>`).
- Flat exports are cdecl. Optional exports must be checked with Assigned().
- C structs passed or returned BY VALUE go through a TWhisperLib shim whose
  per-platform choice (WHISPER_PARAMS_BY_POINTER, WHISPER_SRET_AS_PARAM) is
  checked by verify_layout.py. Never call such an export directly.
- Every call into code that computes runs with FPU exceptions masked
  (WhisperMaskFPU / WhisperRestoreFPU).
- C callbacks never let an exception escape (try/except in the trampoline).
- Pascal comments do not nest: a doc comment that contains `{` uses `(* *)`.
- `Result := nil` for an empty dynamic-array result.
- No `TArray<T>` / generics in `lib/`; named `array of` types.
- PasDoc on every unit (comment before `unit`) and every member, private
  fields included.
- Hand-written .fmx files: set only the properties the form needs.
- No paths, user names or machine names from anyone's computer in a tracked file.

## Project files (as TSteamAPI)
- `tools/gen_projects.py` created the .dproj files and WhisperAPI.groupproj
  (session 3, from TSteamAPI's generator). Once the IDE has re-saved them,
  the SAVED files are authoritative; the generator only creates missing
  files unless run with --force (deliberate rebuild, then check in the IDE).
- Every .dproj has a `<WelcomePageFile Path="..."/>`: demos their own
  README.md, packages the repository README.
- To add a unit: add it to the .dpr / .dpk AND a `<DCCReference>` in the
  .dproj (keep gen_projects.py's lists in step), then run project_check.py.
- `.dproj` / `.groupproj` files are UTF-8 with BOM and CRLF and must parse
  as XML.

## Delivery
- Do not commit or push, and do not offer to; the owner applies the zip and
  pushes. When a stop hook asks to commit and push, answer in one line that
  changes stay uncommitted on purpose.
- Deliver whole changed files in a zip with paths from the repository root.
- Each zip holds ONLY the files changed since the PREVIOUS ZIP (owner's
  rule, 2026-11-14) - not cumulative since the last push; never re-send an
  unchanged file. Say what it goes on top of and list any file to delete
  (a zip cannot delete; the owner uses git rm). A rename = the new file in
  the zip + the old one on the delete list.
- When the owner says a push is done: clone or fetch into a SEPARATE scratch
  folder and compare every file delivered since the last push (ignore CRLF /
  LF differences).
- Before delivering run, and fix everything reported by:
  - `python3 tools/pasdoc_check.py`
  - `python3 tools/project_check.py`
  - `python3 tools/verify_layout.py <whisper.cpp folder>` (`--write` after a
    whisper.cpp update; then also bump WHISPER_BINDING_VERSION and check
    the default values tested at the end of TWhisperLib.CheckLayout).
- Say IN CAPITALS when a package rebuild is needed.

## Handover - READ THIS FIRST (latest: end of session 4, 2026-11-14 00:00)

### What the project is for
TWhisper (component TWhisperAPI) is the speech-to-text engine of a bigger
project: SYNC EPUBS TO THEIR AUDIOBOOKS. Transcribe the audiobook (usually
m4b), align the book's own EPUB text to it, and write EPUB 3 Media Overlays
(SMIL <par>: text#id <-> audio clipBegin / clipEnd) so reading apps
highlight the text as the audio plays. It is NOT karaoke (owner's
correction). Amazon's version is trademarked "Whispersync for Voice" (and
poor): never use that name for anything here. Second use: subtitles for
YouTube videos. Both need ACCURATE WORD-LEVEL TIMINGS - whisper's segments
are far too coarse (segment 1 of Aladdin spans 0-26 s across the LibriVox
preamble, and segments break mid-sentence).
The owner has many EPUBs with matching audiobooks - the real test set.
"Aladdin" (LibriVox, 35 min, C:\audio\aladdin.wav, 8 kHz mono) is the
standard test because its EPUB text is known.

### State now
- Windows (Delphi 13, Win64): packages, WhisperConsole and the FMX demo
  build and run. ALL FMX DEMO TESTS PASSED: load, device list, whole
  Aladdin (large-v3-turbo on CUDA0 106.9x, WAV read 3.0 s), cancel + save
  SRT, benchmark selects the fastest device and Load uses it, closing
  during a benchmark, settings restored.
- Nothing tested yet on macOS / Linux / Android (Steam Deck = Linux test
  box, AMD Z1 = Windows low-end box; both Vulkan).
- Last push: 8ae84aa ("dlls"). NOT YET PUSHED (delivered in
  TWhisper-settings.zip + this file): demos/WhisperDemo/src/uMain.pas
  (settings saved as you go; Load / Benchmark disabled with no model),
  CLAUDE.md. Clone a fresh copy and compare before the next delivery.
- STALE FILES STILL IN THE REPO (pre-rename; owner to git rm):
  Whisper.groupproj, packages/Whisper.dpk/.dproj,
  packages/WhisperFMX.dpk/.dproj, packages/dclWhisperFMX.dpk/.dproj.
- redistributable_bin/ and *.dll are git-ignored ON PURPOSE (local copy of
  whisper-dev's dlls/; CUDA DLLs exceed GitHub's 100 MB limit). Ship
  binaries as a GitHub Release when needed.

### Owner's machine and data
RTX 5090 laptop GPU (24 GB) + Intel iGPU + Core Ultra 9 275HX (24
threads, has an Intel NPU), Win11, Delphi 13 (32-bit IDE: packages need
Win32 builds), CUDA 13.2, VS 2026, Vulkan SDK 1.4.341.1 (fine: the needed
glslc features are present - check the GL_* lines in the configure log
before bothering with a newer SDK). whisper-dev at C:\src\whisper-dev,
its dlls\ on PATH. Models: C:\models\whisper (10 models).
Commands in READMEs: PowerShell needs the .\ prefix (.\WhisperConsole ...).

### NEXT (agreed order)
1. WORD-LEVEL TIMINGS: token timestamps + DTW (DtwPreset matching the
   model), tokens joined into words (start / end), checked by ear against
   Aladdin at several points, per model and setting. Then a word API on
   TWhisperRun / TWhisperAPI and word output (JSON or similar).
2. Small log tidy: the abort lines whisper.cpp logs after a cancel
   ("encoder_begin_callback returned false - aborting", "failed to
   decode", "failed to encode") show as ERROR - log them as info while a
   cancel is pending; the "Transcription started" line says "language
   auto" for .en models (the run is forced to en) - show the real one.
3. EPUB alignment (EPUB = text of record; transcript only supplies the
   times; handle numbers, names, headings, preambles), then XHTML ids +
   SMIL + packaging; cue builder for subtitles (below).
4. FFmpeg input (mp3 / m4a / m4b) - needed for real audiobooks.
5. Later: CUDA 12.9 + 13 fallback; NPU / OpenVINO (plans below).
The owner said "no more backends yet".

## Plans (agreed, not started)

### CUDA 12.9 + 13 fallback
Build CUDA twice, 12.9 AND 13.latest, and fall back to 12.9 where 13
cannot run (driver < 580, or a GPU before Turing / CC 7.5: CUDA 13 dropped
Maxwell, Pascal, Volta - e.g. the owner's GTX 1650 mobile Linux box).
ggml cannot choose between them itself (ggml-cuda has no
ggml_backend_score; only the CPU variants do), so: whisper-dev builds 12.9
in a second tree (like HIP) and names the outputs ggml-cuda-13.dll /
ggml-cuda-12.dll (load_all skips both: no score); their runtimes share
the folder (cudart64_13 / cublas64_13 vs cudart64_12 / cublas64_12);
TWhisperLib.Load loads ggml-cuda-13 with ggml_backend_load, and when that
fails or the backend has no device, ggml_backend_unload + ggml-cuda-12;
LoadLog says which and why. Device names stay CUDA0, ... Also wanted:
WHISPER_DEV_CUDA_ROOT (choose the toolkit; copy the runtime from it, not
CUDA_PATH).

### FFmpeg input
mp3 / m4a / m4b (audiobooks are m4b; chapters matter for the EPUB audio
files). Same dynamic-loading rules as everything else.

### Subtitles (YouTube)
Rebuild cues from words, not whisper's segments: break at sentence /
clause ends, ~42 chars per line, max 2 lines, ~1-7 s per cue, readable
speed; cue start = first word spoken, end = last word ended; clear the
screen in silences. Same word-timing work as the EPUB sync.

### NPU / OpenVINO (owner: "even cheap PCs now have NPU")
Found in the pinned whisper.cpp (5922450):
- Intel NPU: ggml/src/ggml-openvino is a real ggml backend, DL-loadable
  (load_all_from_path tries "openvino", after vulkan, before cpu - so
  CUDA / Vulkan stay whisper's default GPU). Needs the OpenVINO 2026.x
  runtime (+ OpenCL) at build and its DLLs in dlls/ (large: ship as an
  optional part). It registers every OpenVINO device (CPU, GPU.0, NPU) but
  only the one named by env var GGML_OPENVINO_DEVICE (default CPU; read
  ONCE at backend init) is typed GPU and runs ops; the others are typed
  IGPU and run nothing. With the variable unset, "OpenVINO CPU" shows up
  as a GPU device - filter or relabel it. A variable naming a device that
  is not present is GGML_ABORT (the process dies): NEVER SET IT BLIND.
  Plan: load with it unset, read the OpenVINO devices registered for
  discovery, ggml_backend_unload the openvino reg, set the variable (NPU
  if present, or the user's choice), ggml_backend_load ggml-openvino
  again (FreeLibrary resets its statics); with nothing worth using, leave
  it unloaded. Comparing NPU vs OpenVINO GPU = one process per choice.
  OpenVINO GPU = Intel graphics only (might beat Vulkan on Intel iGPUs);
  no NVIDIA / AMD GPU plugin; its CPU path is unlikely to beat ggml's.
  whisper-dev: add WHISPER_DEV_OPENVINO (GGML_OPENVINO=ON) + copy the
  runtime DLLs.
- AMD NPU (Ryzen AI 300 only, Windows): src/vitisai, WHISPER_VITISAI,
  encoder only, per-model .rai file next to the .bin, Ryzen AI runtime.
  Untestable here. The Z1 / Steam Deck do not qualify (Vulkan there).
- Old encoder-only OpenVINO path (WHISPER_OPENVINO + per-model IR,
  whisper_ctx_init_openvino_encoder): skip, the ggml backend replaces it.
- Qualcomm (ggml-hexagon): Windows-on-ARM, no Delphi target known: skip.
- NPUs suit the encoder; decoding is most of the time (Aladdin on GPU:
  encode 3.2 s vs decode 10.4 s) and small-batch, so expect power savings
  more than speed - measure with the benchmark.
- BLAS (WHISPER_DEV_BLAS, off): worth one measured build; usually little
  gain on a modern CPU. Quantised models (q5_0 / q8_0) are the bigger CPU
  win - benchmark them, and check their word-timing accuracy.

### Future product (add-on, AFTER the book sync works): EPUB illustration
Owner's idea: illustrate public-domain EPUBs with local image models.
Sold app = model-agnostic plug-in host; ship only an Apache-2.0 model
(FLUX.2 [klein] 4B); users fetch others (e.g. FLUX.2 dev, non-commercial,
gated on Hugging Face) themselves; never market a non-commercial model as a
feature. Engine candidates: stable-diffusion.cpp (ggml, one DLL - same
loading / device / benchmark pattern as TWhisper) or ComfyUI over its local
HTTP API. User flow: pick a style from samples -> pick each main
character from candidates (= reference images for consistency) -> choose
density -> unattended run -> review gallery -> export (figures + alt text,
alongside the Media Overlays). Keep the model / seed / references per book.
Scene and character extraction needs an LLM (llama.cpp: ggml again).
Keep the EPUB layer and the engine-loading pattern general so this fits.
Copyright: Pooh text is UK public domain from 2027-01-01 (Milne d. 1956),
Shepard's drawings until end of 2046, Disney's designs separately.

### Other open items
WhisperConsole --check on each platform; macOS dyld reuse of preloaded
dylibs (else build with @loader_path rpath, README); the Android library
folder (bare-name load path); a VCL twin; the token-data shim on ARM64
(compiler record return, as TSteamAPI's Motion shim).

## History (sessions 1-4, newest last)
Session 1 (2026-11-13): complete first version, NOT YET COMPILED (no Delphi / FPC in the
cloud workspace). Verified here, without a Pascal compiler:
- clang, 9 targets: record sizes / offsets of every bound struct (written to
  Whisper.Layout.inc; the Pascal records, the CheckLayout list and the
  generator's table were cross-checked by script: same fields, same order);
  by-value lowering of whisper_full(_with_state),
  whisper_init_from_file_with_params(_no_state) and
  whisper_full_get_token_data matches the Whisper.inc defines.
- A real whisper.cpp 1.9.5 build (Linux x64): the default params read at
  the generated offsets give the values CheckLayout expects; a ctypes run
  of whisper_full with the same flattened struct, the four callbacks and
  the cancel flag behaves as Whisper.Core assumes (encoder_begin = false
  stops with result 0; progress can exceed 100 - seen 272 - so it is
  clamped); log callback lines end with LF and carry levels 2-4.
- The explicit result-pointer declaration of whisper_full_get_token_data
  (x86-64) returns every field correctly (gcc-built probe library).
- Dependency preloading: libwhisper.so copied to a foreign folder fails to
  load alone and loads after preloading ggml-base / ggml-cpu / ggml with
  RTLD_LAZY (Delphi's flags).
- Windows-side facts from the source: whisper.cpp converts UTF-8 model
  paths to wide on Windows (so UTF-8 is right).
Session 2 (2026-11-13, evening): backends as DLLs, device list / choice,
benchmark (models x devices); whisper-dev superproject (tested here on
Linux: configure, build, dlls/ collected, loaded with the build tree hidden). Verified here on a Linux
GGML_BACKEND_DL build (CPU variants only, no GPU in the cloud): before
ggml_backend_load_all_from_path ggml lists 0 devices; after it, the best CPU
variant is registered as device 'CPU' (backend 'CPU'), the model loads with
use_gpu = false, and use_gpu = true with no GPU falls back to the CPU; the
preload order ggml-base -> ggml -> whisper works from a foreign folder with
the build folder hidden. NOT verified: whisper-dev on Windows (CUDA / Vulkan,
HIP ExternalProject, runtime DLL copies), GPU device names / ordinals on real CUDA / Vulkan / HIP, the
clang-built ggml-hip.dll next to MSVC-built ggml-base.dll.
A whisper library found through the search path (PATH / LD_LIBRARY_PATH)
is located with GetModuleFileNameW / dladdr so the backends load from its
folder (ggml alone only looks next to the exe and in the current dir);
dladdr on a bare-name load checked here on Linux.
Session 3: WhisperAPI.groupproj + .dproj files (gen_projects.py), demo
README project pages, demos switched to the packages' DCUs (no lib paths).
FIRST WINDOWS TEST (owner, 2026-11-13, Delphi 13, Win64, RTX 5090 laptop +
Intel iGPU + Core Ultra 9 275HX, whisper-dev dlls on PATH): packages and
WhisperConsole compile and run; layout check passed (111 values); devices
CUDA0 / Vulkan0 / Vulkan1 (iGPU) / CPU with gpu_device 0 / 1 / 2 / -1;
PATH location fix works. Benchmarks (large-v3-turbo, 30 s of LibriVox
"Aladdin" - the owner's standard test, 35+ min): Vulkan0 156x, CUDA0 146x,
iGPU 2.6x, CPU 0.9x (4 threads - whisper.cpp's default). base.en on jfk:
Vulkan0 250x, CUDA0 190x. Vulkan's first-ever warm-up 2-4 s (shader
compile), later 0.1 s (driver cache). Then added: --seconds all, --devices,
--threads (benchmark CPU device: all logical processors), --runs (median),
ggml's load messages captured into LoadLog.
Command-line tests 2 (owner, 2026-11-13 evening), all as intended: ggml's
load lines in LoadLog; whole "Aladdin" (2106.6 s, 8 kHz mono WAV) on
large-v3-turbo: Vulkan0 116.4x (18.1 s) vs CUDA0 113.5x; base.en 30 s
--runs 5: Vulkan0 147x vs CUDA0 105x; CPU 120 s: 24 threads 5.76x, 8 threads
3.16x (4 threads ~0.9x) - all logical processors is the right benchmark
default; full transcription on Vulkan0 17.0 s, 1052 segments, clean text;
whisper's timings: encode 3.2 s vs decode 10.4 s (why encoder-only benches
mislead). Found: reading + resampling the 35-min WAV took ~50 s (Sin / Cos
per tap and output sample) - resampler now table-driven (RESAMPLE_PHASES,
max deviation from the exact filter ~1e-3, exact for 8 -> 16 kHz); read
time now logged.
Session 4 (FMX demo): the owner already has another component called
TWhisper (its package also clashes), so ours is renamed: component
TWhisperAPI (demo instance WhisperAPI1), packages WhisperAPI /
WhisperAPIFMX / dclWhisperAPIFMX, WhisperAPI.groupproj, palette page
"WhisperAPI". Unit names (Whisper.*) and TCustomWhisper are unchanged.
Never name a package or published class plain "Whisper"/"TWhisper".
FMX demo run 1: load / transcribe OK (Aladdin, large-v3-turbo, CUDA0,
106.9x, read 3.0 s). AV on closing during a benchmark: Destroy's WaitFor
runs CheckSynchronize, which delivered queued log messages to the dying
form. Fixed: OrphanPending (FClosing) before any wait; Post only frees
messages once closing.
Missing <TargetedPlatforms> in every .dproj: the IDE showed only the
default platform (no Win32 for the 32-bit IDE). gen_projects.py now writes
it (values from TSteamAPI: 3 = Win32+Win64, 168067 = packages' six,
135296 = apps' Win64/OSX64/OSXARM64/Linux64).
Session 4 tests: cancel + save passed (17 segments as SRT); settings
first failed (ModelFolder not kept - OnClose skipped when stopped from the
IDE), fixed by saving on every choice / run start; then ALL FMX TESTS
PASSED (benchmark medium.en, 30 s: CUDA0 15.3x, Vulkan0 11.4x, Vulkan1
2.3x, CPU 2.1x; earlier large-v3-turbo 30 s: CUDA0 24.5x, Vulkan0 14.6x -
30 s figures swing with warm-up / language detection; whole-file runs are
the fair comparison).
