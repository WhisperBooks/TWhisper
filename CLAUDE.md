# CLAUDE.md - working rules for this repository

Read README.md first, then this file. Keep both up to date with every change.
The rules follow TSteamAPI's CLAUDE.md (same owner, same conventions); where
this file is silent, TSteamAPI's rules apply.

## Project
Pascal binding of whisper.cpp (checked against whisper.h 1.9.5), loaded
DYNAMICALLY at run time (owner, 2026-11-13: "must use dynamic loading of
dlls, also in TSteamAPI"): no `external` declarations, no static linking.
Target order: FMX, then VCL, then Free Pascal. Delphi 13 is the reference
compiler; lib/ must also compile with FPC 3.2.2.

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
- Deliver whole changed files in a zip with paths from the repository root.
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
Open: first Delphi compile (packages, both demos, Win64 then Win32);
WhisperConsole --check on each platform; macOS dyld reuse of preloaded
dylibs (else build with @loader_path rpath, README); the Android library
folder (bare-name load path); a VCL twin; the token-data shim on ARM64
(compiler record return, as TSteamAPI's Motion shim).
