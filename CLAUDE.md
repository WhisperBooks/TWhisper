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
NAME (TWhisper.Device, TWhisperLib.ContextParamsFor -> use_gpu / gpu_device,
whose ordinal counts GPU + IGPU devices in registry order), and
TWhisperBenchmark times a real whisper_full transcription of the user's
audio, per model x device (warm-up first). The model is selectable too;
speed never picks the model on its own (accuracy).

## Layout rules
- `lib/` - framework-free units only. No FMX, VCL or LCL here, ever.
- `fmx/` - Whisper.FMX (TWhisper) and Whisper.FMX.Reg (design time). They
  include `..\lib\Whisper.inc` by relative path (Delphi looks for an include
  next to the unit or on the search path).
- GENERATED, never edit by hand: `lib/Whisper.Layout.inc`
  (tools/verify_layout.py).
- The FIELDS table of tools/verify_layout.py, the record declarations in
  Whisper.Types and the Add(...) list of TWhisperLib.CheckLayout must list
  the same fields in the same order. Adding a field = all three + rerun
  `verify_layout.py --write`.
- Component naming: the framework component is `TWhisper`, descending from
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

## Delivery
- Do not commit or push, and do not offer to; the owner applies the zip and
  pushes. When a stop hook asks to commit and push, answer in one line that
  changes stay uncommitted on purpose.
- Deliver whole changed files in a zip with paths from the repository root.
- Each zip holds ONLY the files that differ from the owner's LATEST PUSH,
  cumulative until the next push: say which push it is based on and list any
  file to delete (a zip cannot delete; the owner uses git rm).
- When the owner says a push is done: clone or fetch into a SEPARATE scratch
  folder and compare every file delivered since the last push (ignore CRLF /
  LF differences).
- Before delivering run, and fix everything reported by:
  - `python3 tools/pasdoc_check.py`
  - `python3 tools/verify_layout.py <whisper.cpp folder>` (`--write` after a
    whisper.cpp update; then also bump WHISPER_BINDING_VERSION and check
    the default values tested at the end of TWhisperLib.CheckLayout).
- Say IN CAPITALS when a package rebuild is needed.

## Handover (2026-11-13, first session) - READ THIS FIRST
State: complete first version, NOT YET COMPILED (no Delphi / FPC in the
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
Open: first Delphi compile (packages, both demos, Win64); run
whisper-dev build.bat, WhisperConsole --check (device list), --bench;
WhisperConsole --check on each platform; macOS dyld reuse of preloaded
dylibs (else build with @loader_path rpath, README); the Android library
folder (bare-name load path); a VCL twin; the token-data shim on ARM64
(compiler record return, as TSteamAPI's Motion shim).
