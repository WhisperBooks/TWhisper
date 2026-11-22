# CLAUDE.md - working rules for this repository

Read README.md first, then this file. Keep both up to date with every change.
The rules follow TSteamAPI's CLAUDE.md (same owner, same conventions); where
this file is silent, TSteamAPI's rules apply.

## Handover - READ THIS FIRST (latest: session 6, 2026-11-15 evening)
Written at the owner's request so the next session reads it first; the
sections further down hold the detail and the history.

This is the summary and the to-do list for all four repositories (the
same text is in TWhisper's and Epubunum's CLAUDE.md).

### Repositories and where they stand

(The table below is session 6's. Current, 2026-11-16: TWhisper d669a06 =
TWhisper-30, last number used 31 - the review fixes further down;
Epubunum's CLAUDE.md has session 7's handover and table, whisper-dev has
a CLAUDE.md of its own from whisper-dev-21.)

| Repo | Pushed | = zip | Last zip number used |
|---|---|---|---|
| WhisperBooks/TWhisper | 59cc978 | TWhisper-28 | 28 |
| WhisperBooks/Epubunum | 5717238 | EpubUnum-37 | 37 |
| G3DGames/TFFMpegAPI | 105ffe7 | FFmpegAPI-11 | 11 |
| G3DGames/ffmpeg-dev | 2b0ba17 | ffmpeg-dev-06 | 06 |

All four pushes were checked file by file against the deliveries (CR LF
and BOM aside). The only difference: demos/EpubBuilder/EpubBuilder.dproj
in Epubunum was re-saved by the IDE (platform blocks, TargetedPlatforms;
harmless - keep the pushed one). TWhisper's 5e029a8 had EpubUnum-34's
files unpacked into it by mistake (EpubUnum's CLAUDE.md over TWhisper's,
demos/EpubReader/...); fixed in 59cc978 and re-checked. Nothing is
pending: every delivered zip is pushed. This handover itself came in
TWhisper-29, EpubUnum-38 and FFmpegAPI-12 (CLAUDE.md only), so the
last numbers used are now 29, 38 and 12.

### Standing rules (owner) - unchanged, repeated because they matter

- Never commit or push, and never offer to.
- Zips: only files changed since the previous zip, paths from the repo
  root, named TWhisper-NN-topic.zip / EpubUnum-NN-topic.zip /
  FFmpegAPI-NN-topic.zip / ffmpeg-dev-NN-topic.zip; numbers never
  reused (a corrected zip gets the next number and says what it
  replaces); every delivery says what it goes on top of.
- Every delivery ends with either "NO PACKAGE REBUILD" or: a blank line,
  `=====> PACKAGE REBUILD NEEDED <=====`, a blank line, then the packages
  in build order, the units changed, what to rebuild after.
  TWhisper: WhisperAPI -> WhisperAPIFMX -> dclWhisperAPIFMX.
  EpubUnum: EpubUnum -> EpubUnumFMX -> dclEpubUnumFMX.
- ASCII sources; PasDoc on every declaration; run tools/pasdoc_check.py
  and tools/project_check.py before delivering (both repos).
- .dproj files: do not change platform lines or the default platform;
  never run gen_projects.py --force on existing projects (without
  --force it only creates missing files - that is how EpubBuilder.dproj
  was made). Group projects are edited by hand.
- README code blocks paste as-is: comments on their own line, no
  <placeholders>.
- Never offer DRM removal; refuse protected files with a clear message.
- Copyrighted test books stay local - never committed, uploaded or
  quoted. Night Watch (Pratchett, English and German) is one: the owner
  sends logs only.
- No absolute paths, user names, machine names or e-mail addresses in
  tracked files.
- Answer simple questions directly and briefly first.
- When the owner's message arrives mid-task, address it in the same turn.

### What exists now

Pipeline (files): EpubConsole --words -> WhisperConsole (transcribe,
--json) / --from-json --align-words --timings -> EpubConsole --overlay.
In one program: **EpubBuilder** (Epubunum demos/EpubBuilder, links
TWhisper + EpubUnum + TFFMpegAPI): EPUB left, audio list right, model /
device / output, Create; keeps `<output>.transcript.json` so a re-align
needs no transcription; explained results with a verdict; settings in
EpubBuilder.ini (model, device by name, options, folders).

**EpubReader**: menu (File: Open, Recently Opened (10), Go to Footnote -
only with "debug": true; Edit: Find / next / previous; View: Dark mode,
Learn to read, text size), settings in EpubReader.json (dark, textSize,
speed, recent with reading positions, debug), opens the last book read
where it was left, centred smooth line following, speed slider 0.5-1.5x
(applied when the slider rests), Learn to read (green, Phrase / Sentence
/ Paragraph; Play repeats the unit; click = the unit the word is in),
punctuation not lit, footnotes shaded (marked notes, or the paragraph a
marker link points to), Open with registration (Windows HKCU, Linux
.desktop), icon.

**TWhisper** this session: edge pairs (front / back matter not timed),
Roman numerals as numbers, short words given room, word edges trimmed of
silence from the audio (the next sentence no longer lit during a pause),
benchmark times a chosen stretch of speech (not within 30 s of either
end), shared helpers for the builder (WhisperWordFileTimes etc.).

### Results to remember

- Moby-Dick (LibriVox, Stewart Wills, 24 h 38 m, 5 m4b): 81x on the 5090
  laptop; 209652 exact of 213817 book words. Against the IDPF human sync
  of ch 1-2: clip starts mean |error| 0.21 s (the human times are
  rounded to 0.25-0.5 s).
- Aladdin through EpubBuilder: 26.5 s for 34:32 (78x) once the builder
  used TWhisper's book settings (no previous-text context, punctuated
  prompt in every window); 99.8 % matched.
- Night Watch (English, professional reader, 14:41, 75 parts): 97.8 %;
  441 moved words = the footnotes, timed where they are read.
- Benchmark on the 5090 (turbo, Aladdin, 30 s): chosen stretch CUDA0
  122.0x, Vulkan0 128.8x; the old first-30-s figures were ~20 % high.

### Open - Windows (owner to test or answer)

1. Test the pause fix in the reader on a book rebuilt after TWhisper-28
   (the next sentence must not light while the narrator pauses).
2. Test German Night Watch through the builder (book language -> German
   prompt, transcribe only). Expected weak spot: chapter numbers (the
   aligner's number words are English).
3. Night Watch's contents list has no chapters: check the chapter
   buttons, which fall back to the book's 24 documents.
4. Unanswered offers: (a) Create asks before replacing an EPUB this
   book's last build did not make; (b) leave front / back matter out of
   the builder's "worth a look" list; (c) Find matches a punctuation-only
   query (`*`) literally.
5. Small: --overlay drops audio no overlay plays (moby-dick-mo.epub's
   9 MB mp4); a drawn menu bar that follows dark mode (the native one
   stays light); the Settings menu (later).

### Next - other operating systems (agreed order: Linux, then macOS)

- **Linux (incl. Steam Machine, Steam Deck):** a Linux build of TWhisper
  and its first test (whisper-dev builds the libraries); then the
  Steam Machine HIP re-run with --bench (chosen stretch, greedy) for a
  like-for-like comparison with the 5090; first runs of the reader
  (FMXLinux; TSteamAPI's platform units and EpubReader.sh already in)
  and of the builder; FFmpeg linux-x64 from ffmpeg-dev. Steam Deck:
  Steam Input through TSteamAPI (needs its source in the session) and a
  1280x800 layout.
- **macOS:** TFFMpegAPI has no macOS audio output yet (AudioQueue) - the
  reader is silent there until it does; TWhisper with Metal (untested);
  Info.plist CFBundleDocumentTypes for "Open with".
- **Android:** later.

### Plans agreed or parked (detail in the CLAUDE.md files)

- Volunteer transcribers (design only): a job server, workers poll,
  LibriVox section files as jobs, transcripts back, the server aligns;
  workers report their own benchmark (HIP / Vulkan / CUDA / Metal),
  6 GB+ GPU memory. TWhisper CLAUDE.md, plans.
- Audio outside the book: timings beside the original EPUB (+3: the
  complete EPUB), timings naming LibriVox's downloads, an edition check.
  Epubunum CLAUDE.md, "Shall we do this".
- Builder: progress per word stretch is fine; later - go to the
  suspicious stretches from the results (needs the reader inside the
  builder or the other way round); long files without chapters could be
  split into 30 min pieces (memory: 64 KB per second of audio).
- German / other-language number words in TWhisper's aligner, if the
  German run shows heading misses.
- Parked: English sentence -> German sentence and audio between two
  synced EPUBs (sentence alignment feasible, phrase level needs a
  translation model).

### Working notes for the next session

- Nothing compiles Delphi / FMX in the session: lib/ and the consoles
  were built with FPC 3.0 to test; the reader, the builder and the FMX
  view were reviewed by reading only - the owner's Delphi build is their
  first compile, so expect the occasional compile fix.
- Tests used here, worth setting up again when needed: epubcheck 5.2.1
  on every overlay EPUB; a check that every clip equals its timing and
  ClipAt finds it; a check that only markup was inserted into the
  documents; --from-json re-alignment of the owner's moby.json (fast
  regression test of the aligner: 209652 exact, 213544 timed words with
  the current word list).
- The owner's machine: Windows, RTX 5090 laptop + Intel iGPU; whisper.cpp
  and FFmpeg 8.1.3 LGPL in TWhisper's redistributable_bin\Win64 (on
  PATH); model ggml-large-v3-turbo.bin.

## Linux port (session 7, 2026-11-16) - TWhisper-30, on top of 9dfde0e
Done in the cloud (Ubuntu 24.04 x86-64, gcc 13, 2 CPUs, no GPU):
- whisper-dev at 11a38b9 (whisper.cpp 5922450 = 1.9.5-dev) built with
  ./build.sh: CPU variants only (no nvcc / glslc / ROCm here). Found and
  fixed in whisper-dev (its zip whisper-dev-01-linux-rpath): RUNPATH was
  the build tree's absolute path -> $ORIGIN (@loader_path on macOS);
  -ffile-prefix-map so no build-machine path is in the libraries;
  libgomp.so.1 copied to dlls/ on Linux with gcc (every ggml-cpu variant
  NEEDS it; Steam's runtime may lack it), found through $ORIGIN (ldd
  checked). The three copies per library (.so, soname, full version) are
  as designed.
- FPC 3.0 (fpc-lambda; on this image also: ln -s
  /lib64/ld-linux-x86-64.so.2 /lib/ld64.so.1, FPC 3.0 writes that
  interpreter) built lib/ + WhisperConsole (TStringBuilder stand-in), and
  TFFMpegAPI + EpubUnum lib/ + consoles: no errors.
- WhisperConsole --check on the Linux libraries: layout check passed (111
  values), CPU device listed, backends loaded from the program's folder.
- A random-weight tiny.en model (header, filters and vocabulary of
  whisper.cpp's for-tests-ggml-tiny.en.bin + 167 random f32 tensors)
  transcribed 10 s of Moby-Dick (LibriVox): DTW words, second pass over
  gaps, word-edge trimming, JSON - every path ran (5.1 s). With 60 s it ran
  past 10 min (random weights decode to the limit at every temperature) -
  use 10 s clips for such tests.
- Pipeline: a transcript JSON made from the IDPF Moby-Dick sample's human
  sync (3658 words, 1 in 50 dropped, 1 in 37 misspelt) -> --from-json
  --align-words --timings: 3533 exact, 52 similar, 73 interpolated = all
  3658 timed -> EpubConsole --overlay (Linux) -> epubcheck 5.2.1 0 / 0.
- FIX (WhisperConsole, all platforms): --from-json of a transcript
  without parts (one audio file: its JSON does not name the file) wrote
  "# audio 1: <the JSON's path>" into --timings, and EpubConsole
  --overlay without --audio then copied the JSON into the book AS AUDIO.
  Now that line says the audio is not known ("# audio 1 not known ...:
  give EpubConsole --audio FILE or --book-audio PATH"; EpubConsole skips
  it and asks for audio). CONSOLE_DELIVERY 30.
- glibc: libraries built on Ubuntu 24.04 need GLIBC_2.38 (ggml) /
  GLIBCXX_3.4.29. SteamOS is newer; Steam Linux Runtime 3.0 (sniper)
  uses the host's glibc when newer, so they load there. For other
  distributions, build on the oldest system to support (or in the
  sniper SDK container: registry.gitlab.steamos.cloud/steamrt/sniper/sdk).
NOT done here (needs the owner's Linux box): GPU backends (Vulkan / HIP /
CUDA), Delphi Linux64 builds (WhisperConsole, WhisperDemo, EpubBuilder,
EpubReader through PAServer), real speech with a real model, sound.

## Benchmark progress (TWhisper-32, on top of 2f98152 = TWhisper-31)
Owner 2026-11-22 15:49 (in Epubunum's session): "When calibrating three
runs are typically done. This means the progress bar goes 0, 33, 66,
100. If calibrating a very slow machine it can look like it's stuck. Can
we get some callbacks while calibrating so the calibration is more
granular?" (the three steps are EpubBuilder's devices: one pair each).
NOT COMPILED (no Delphi, no FPC here; pasdoc_check, project_check: 0
problems). Files: lib/Whisper.Core.pas,
demos/WhisperConsole/WhisperConsole.dpr (CONSOLE_DELIVERY 32), CLAUDE.md.
- TWhisperBenchmark.OnProgress (TWhisperBenchmarkProgressEvent: Sender,
  APhase: TWhisperBenchmarkPhase = wbpLoading / wbpWarmup / wbpTiming,
  APercent 0 .. 100 of the pair), from Run and RunOne, on the calling
  thread. An estimate: loading 0 - 10, warm-up 10 - 20, the timed runs
  share 20 - 100 equally, each moved by its TWhisperRun.OnProgress
  (whisper.cpp reports at the start of every 30 s window: a 120 s stretch
  gives about four steps per run). 100 when the pair is Ok. No
  duplicates (FLastPhase / FLastPercent, reset per pair).
- Private: FPhase, FPhaseFrom, FPhaseSpan, StartPhase, Report,
  RunProgress; RunOne's LOAD_SHARE / WARMUP_SHARE.
- Not forwarded by TCustomWhisper.BenchmarkDevicesAsync (not asked).

## Review fixes (TWhisper-31, on top of d669a06 = zip 30)
A code review by reading of d669a06 (owner, 2026-11-16: "Same for
TWhisper", then "y + claude"). Read closely: Whisper.DynLib, API, Core,
Components, Audio, AudioSet, the aligner's AlignGap / PairTokens, the
model header reader, the console's arguments. NOT read: the rest of
Whisper.Align, WhisperBuildWords, the clean / insert routines,
WhisperDemo, the FMX units, the tools. NOT COMPILED (no Delphi, no FPC in
that session); pasdoc_check, project_check 0 problems; verify_layout.py
against whisper.cpp 5922450: 0 errors (no record changed).
1. TWhisperLib.RequireLayout / EnforceLayout (Whisper.API), called by
   TWhisperModel.Init (Whisper.Core): CheckLayout ran only in the
   component's DoActivate and in WhisperConsole --check, so a program
   using TWhisperModel / TWhisperRun directly (EpubBuilder) passed its
   params record to whatever whisper.cpp was in the folder. Now every
   model checks once (answer kept, under the log lock) and raises with
   the report. The component sets Lib.EnforceLayout from its CheckLayout
   property when it activates (off = off for the whole library).
2. Whisper.Core, FillGaps / RunStretch: a gap segment counted as "the
   prompt given back" when its letters were ANY substring of the
   prompt's - "It was", "Sie", "eine" are inside the book prompts, and
   short utterances are what gaps hold; the retry without the prompt
   used the same test. Now only from ECHO_MIN_LETTERS (12) letters.
   TO TEST: --from-json cannot show it (the gaps are in the JSON
   already): transcribe a book again and compare "not heard" and the
   gap lines; moby.json's 209652 exact must not fall.
3. Whisper.API finalization: the library object and the library are NOT
   freed while a model is alive (it would call whisper_free through a
   freed TWhisperLib) - left to the system. ModelCreated / ModelFreed
   count atomically (EpubBuilder makes its model on a thread).
4. Whisper.Components, DoDeactivate: Active := False inside an event of
   a SYNCHRONOUS Transcribe raises EWhisperError (it freed the model
   under whisper_full; the model's lock is re-entrant on one thread).
   Not when the component is being destroyed (nobody to refuse to -
   still fatal there: do not free the component in such an event).
5. Whisper.Audio: BlockAlign is an Integer (as UInt16, bytes x channels
   wrapped for a header claiming thousands of channels and frames were
   decoded past the block buffer); more than WAV_MAX_CHANNELS (256)
   channels is refused; a file cut short raises EWhisperError with the
   file's name (was EReadError "Stream read error").
6. WhisperConsole: --seconds and --bench-start read with '.' whatever
   the system's decimal separator is (ArgFloat). CONSOLE_DELIVERY 31.
FOUND AND NOT FIXED (owner to decide):
- TWhisperBenchmark.Cancel reads FCurrentRun while RunOne frees it
  (from the zip 20 review; EpubBuilder's TBuildThread.Cancel has the
  same shape with FRun).
- LoadBackends resets the host's SetDllDirectory; with no library next
  to the program the bare name is looked for in the current directory
  too (Windows).
- AlignGap leaves a gap of more than MAX_GAP_CELLS unpaired without a
  word: check that the figures show it (no anchors at all = the whole
  book is such a gap). It joins two strings per cell for the 'on to' =
  'onto' tests: compare lengths first.
- TWhisperAudioSet.Read reads a .wav itself even when FFmpeg is loaded:
  a non-PCM WAV fails where FFmpeg would decode it.
- The JSON reader recurses without a depth limit (own files only).
- TWhisperLib.Load is not safe for two threads calling it first at once.
- A log listener can be in a call on a ggml thread while
  RemoveLogListener and the component's destructor run.
- Timing uses Now, not a stopwatch. No LICENSE file (public repository).

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
- TFFMpegAPI (github.com/G3DGames/TFFMpegAPI) is a DEPENDENCY of TWhisper
  (owner, 23:15), installed separately: NOT a submodule and NOT in the group (owner, 2026-11-14 23:14: "TWhisper
  should no longer have a FFMpeg submodule - it should rely on TFFMpegAPI
  component and the packages removed from the group"). It is built and
  installed from its own repository like any third-party component;
  package WhisperAPI REQUIRES its runtime package FFmpegAPI (FFmpegAPI.dcp
  from Delphi's Dcp folder; gen_projects.py EXTERNAL_PACKAGES,
  project_check.py EXTERNAL_REQUIRES). It has its own CLAUDE.md, checks and
  FFmpegAPI-NN zips; TWhisper never carries a copy of its files.
  TWhisper has NO FFmpeg code of its own (owner, 2026-11-14: "tidy
  TWhisper of FFMpeg"; zip 15 removed lib/Whisper.FFmpeg): Whisper.AudioSet
  and the console use FFmpeg.API (TFFmpegLibrary) and FFmpeg.Media
  (TFFmpegMediaFile, TFFmpegAudioDecoder at WHISPER_SAMPLE_RATE mono)
  directly; AudioSet turns EFFmpegError into EWhisperError.
- THE OWNER BUILDS IN THE 32-BIT IDE (2026-11-14 23:50: "I always build on
  32 bit cos 64 doesn't have Mac etc" - Delphi 13's 64-bit IDE has no
  macOS / Linux / Android targets). So the design packages must open on
  Win32: the default-platform line of dclWhisperAPIFMX.dproj (and TFFMpegAPI's
  dclFFmpegAPIFMX.dproj) is Win32; an IDE save from the 64-bit IDE flips it
  to Win64 - set it back. Runtime packages are built for Win32 as well as
  the targets.
- GROUP ORDER (owner's tiers, 2026-11-14, commit 1cac2e7 "Package Order";
  the FFmpegAPI packages removed from the group 23:14): WhisperAPI,
  WhisperAPIFMX, dclWhisperAPIFMX, WhisperDemo, WhisperConsole - plain
  runtime packages, FMX runtime packages, design packages, applications;
  Build / Clean / Make the same. gen_projects.py GROUP_ORDER writes
  exactly this; project_check.py fails on a lower tier after a higher
  one, a package before what it requires, a required package that is
  neither in the group nor in EXTERNAL_REQUIRES, or targets in another
  order.
- WhisperDemo has FFmpegAPI1 (TFFmpegAPI, 16 kHz mono) on its form (owner,
  22:57: "nice if the FFMprg component were on the FMX Form"): a WAV goes
  to WhisperAPI1 as before; other audio is opened and decoded by
  FFmpegAPI1 on its worker thread, then OnDecoded starts TranscribeAsync
  (or BenchmarkAsync on the first BENCHMARK_SECONDS). The whole file is
  decoded: for long audiobooks the console's --chapters is the way.
  FPC builds need TFFMpegAPI's lib/ on the unit path (here: a clone of
  it next to the sources).
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
- `WhisperAPI.groupproj` at the root lists every project IN BUILD ORDER
  (owner, 2026-11-14 - changing it breaks builds and Delphi's quick
  re-compilation): runtime WhisperAPI, FMX runtime WhisperAPIFMX, design
  dclWhisperAPIFMX, then the applications; the Build / Clean / Make
  targets in the same order; no <Dependencies> (the order is the
  dependency). tools/gen_projects.py writes exactly this and
  tools/project_check.py fails on any other order. TSteamAPI's group
  order builds only BY ACCIDENT (owner, 2026-11-14): do not copy its
  order from there.
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
- ZIP NAMES (owner, 2026-11-14 - same-named replacements were confusing):
  TWhisper-NN-topic.zip, NN a running number that is NEVER reused, not
  even after a push. A corrected zip gets the NEXT number, never the old
  name; say which number it replaces. Every delivery says what it goes on
  top of: a zip number, or a commit when nothing is pending. Last number
  used: 32. Bump CONSOLE_DELIVERY in WhisperConsole.dpr to the zip's
  number in every zip that changes lib/ or the console (its first log
  line says which build made a log - owner was losing track, 20:26).
- When the owner says a push is done: clone or fetch into a SEPARATE scratch
  folder and compare every file delivered since the last push (ignore CRLF /
  LF differences).
- Before delivering run, and fix everything reported by:
  - `python3 tools/pasdoc_check.py`
  - `python3 tools/project_check.py`
  - `python3 tools/verify_layout.py <whisper.cpp folder>` (`--write` after a
    whisper.cpp update; then also bump WHISPER_BINDING_VERSION and check
    the default values tested at the end of TWhisperLib.CheckLayout).
- PACKAGE REBUILDS (owner, 2026-11-15: "Add rule"). Every delivery says
  one or the other. When a package must be rebuilt, the message carries,
  exactly, a blank line, the banner, a blank line, then the details:

      =====> PACKAGE REBUILD NEEDED <=====

  Details of the package rebuilds: which packages, in build order, why
  (which unit changed), and what to rebuild after them (programs, other
  repos' packages). Otherwise say "NO PACKAGE REBUILD", in capitals.

## Handover (session 5, 2026-11-14 afternoon)

### EPUB sync pipeline (zip 21, on top of 4c4be57 "Claude review push")
Owner, 2026-11-15: "yep, off we go" - transcribe the LibriVox Moby Dick
(Stewart Wills: 5 m4b, chapter-marked: "Chapter 000: Etymology and
Extracts", "Chapter 001-002", ...), align with the IDPF Moby-Dick EPUB,
write the synced book with EpubUnum's TEpubWriter, compare with the IDPF's
human sync of chapters 1-2 (the same recording: its audio is Wills').
- KEPT SEPARATE: TWhisper (public) and Epubunum (private) do not use each
  other's units; plain files join them. EpubConsole --words (EPUB word
  numbers) -> WhisperConsole --align-words / --timings -> EpubConsole
  --overlay TIMINGS OUT.epub (takes the audio from the timings' "# audio
  N: path" lines). A GUI app linking both can come later.
- Whisper.Align: WhisperSplitBookWords (an EPUB word with dashes,
  'ago' + em dash + 'never', is two aligner words; map back) and
  WhisperJoinAligned (a word's time = its timed parts', its match = the
  first timed part's). TWhisperIndexArray.
- Whisper.AudioSet: WhisperTranscriptionFromJson - reads --json back
  (segments, words sorted by time, language, timing, "parts"); a small
  JSON reader (TJsonNode) in the implementation.
- WhisperConsole: --align-words (EpubConsole word list; role nav left
  out; reports in EPUB word numbers), --timings (exact, similar,
  interpolated, moved words; times per audio FILE via the parts: start
  in its part, end clamped to that part), --from-json (no model, no
  whisper.cpp: align again in seconds); WriteFileLabels / labels work
  from a parts array. CONSOLE_DELIVERY 21.
TESTED here (FPC 3.0 + TStringBuilder stand-in; no whisper.cpp needed for
--from-json): a synthetic transcript JSON of Moby-Dick ch 1-2 (the IDPF
human timings, 38 words dropped, Ishmael heard Ishmail, numbers kept,
a LibriVox preamble, two parts split at 860 s): 3619 exact, 98
interpolated, ishmael=ishmail learned; --timings: all 3613 words in the
right file at the right local time (1477 in file 2); EpubConsole
--overlay with the audio from the timings (the IDPF mp4 cut into two
m4b): epubcheck 0 / 0, every clip = its timing. FOUND (synthetic only):
the preamble's "All" paired with "all," at the end of the Extracts (not in
that synthetic audio) and the 58 words before Chapter 1 were interpolated
into the silence before it - in the real recording the Extracts are read
(Part 1 = "Chapter 000: Etymology and Extracts"); watch for it where a
recording lacks text the book has just before a chapter.
NOT RUN: Delphi build, a real transcription (owner).

### First real book (zip 22, on top of 88975d9 = zip 21 pushed)
Owner's run (Delphi, Windows, 2026-11-15): Moby-Dick, LibriVox, read by
Stewart Wills, 5 m4b (24 h 38 m, 44 parts), 1092675 ms (~81x real time),
215214 words with DTW; --align-words with the IDPF moby-dick-mo.epub
word list (212881 words; Delphi's list byte-identical to FPC's).
Zip 21 gave 209636 exact (98.0 %), 2394 similar, 1418 interpolated, 217
not spoken, 2 not heard, 124 moved, 46 habits. --from-json here (FPC)
reproduced those figures exactly, in 11 s. Found and fixed (zip 22, all
in Whisper.Align):
1. EDGE PAIRS: the IDPF Transcriber's Notes (EPUB words 89-110, not in
   the recording) were paired word by word with the LibriVox preamble
   ("a", "for", "the", "This" scattered over a minute). Edge gaps
   (before the first anchor, after the last) now keep only runs of
   EDGE_MIN_RUN (3) pairs, or a run touching the anchor (KeepEdgeRuns),
   and of those only pairs chained to the anchor with at most
   EDGE_MAX_SKIP (2) book tokens skipped between neighbours. The chain
   rule fixed the end: the Gutenberg licence after "The End" took "of
   Moby Dick" from the narrator's "end of Moby Dick". Now EPUB words
   1-110 and 212127-212214 are not spoken - right for this recording.
2. ROMAN NUMERALS: Whisper wrote chapter numbers both ways in one run
   ("Chapter 5." and "CHAPTER VII."), so "CHAPTER I." was not matched and
   Chapter 1's heading got the preamble's times. RomanValue: canonical,
   upper-case numerals 1-3999 become their number's words on both sides
   (a lone letter only after a word in capitals, so the pronoun I stays
   a word); AddTokens takes the previous word.
After both: 209652 exact, 2382 similar, 1386 interpolated, 244 not
spoken, 3 not heard, 124 moved; 211964 timed words.
AGAINST THE HUMAN SYNC (IDPF moby-dick-mo.epub = the same Wills reading
of chapters 1-2, 40 sentence clips): offset 1753.73 s into Part 1; clip
starts median 0.000 s, mean |error| 0.21 s, 15 within 0.1 s, 26 within
0.25 s, 37 within 0.5 s, worst 0.75 s (the human times are mostly
rounded to 0.25-0.5 s, e.g. 182.00, 225.50 - so this is near their
precision). Clip ends: TWhisper ends at the last word's end, the human
clips run into the pause - median 0.82 s of silence after the last word.
Not an error; worth knowing if highlight tails look short.

### Benchmark stretch and short words (zip 26, on top of 25 = notes, 23 = code)
1. BENCHMARK STRETCH (owner, 2026-11-15): Whisper skips a LibriVox
   recording's spoken intro (~26 s on Aladdin), so timing the FIRST 30 s
   measured mostly skipped audio and flattered every device - and the
   benchmark picks the device. Owner: the middle is no good either ("a
   section with lots of silence or the end of a section - gap - start of
   next section"), and "make sure it doesn't pick anywhere 30s from start
   or end". WhisperFindSpeech (Whisper.Core): RMS per 100 ms frame, quiet
   = below a tenth of the 90th percentile; search from 30 s to 30 s before
   the end; the first 30 s window at most 25 % quiet (ordinary reading
   measured at 10 - 20 % quiet, median 17 %, on the Wills Moby-Dick
   ch 1-2 audio; a section gap far more), else the least quiet window;
   too short for both edges: the middle; shorter than the stretch: the
   start. TWhisperBenchmark.StartSeconds (-1 = choose; read back after
   Run) and SpeechShare; TWhisperBenchmarkResult.StartSeconds /
   SpeechShare; the warm-up uses the same start. WhisperConsole
   --bench-start S; each result line prints "from H:MM:SS, NN % sound".
   --seconds all unchanged (whole audio). The console still benchmarks
   part 1 only of a multi-part input (as before).
   TESTED (no model here - the chooser only, FPC): the ch 1-2 audio
   (860 s): start 30.0 s, 83 % sound (first 30 s: 54 %); 40 s of silence
   in front: 64.5 s (the reading's start), 75 %; 70 s file: the middle.
   NOT RUN: a real benchmark (owner, any GPU).
2. SHORT WORDS: 375 words of the Moby timings had a 10 ms time on top of
   the next word - (a) a word Whisper dropped between two heard words
   that touch ('so much the more': 'the' interpolated into 0 ms), (b) DTW
   giving a heard short word ('see') no length at the next word's start.
   Whisper.Align: (a) such a run shares the two neighbours' time with
   them, by length (MIN_WORD_TICKS = 8, 80 ms); (b) GiveShortWordsRoom
   after interpolation: a word under 80 ms takes time from silence
   before it, then from the next word if that can spare it; only where
   times run in book order. Moby-Dick (owner's moby.json, EpubUnum-15
   word list): overlapping clips 375 -> 2 (both "moved" words, out of
   order on purpose), words under 75 ms 433 -> 4 (no room either side),
   1521 words' times changed, aligner figures unchanged.
   EpubConsole --overlay of the result (stand-in audio) + checkover:
   every clip = its timing, ClipAt from each clip's middle finds it -
   problems 18 -> 0.
   OWNER'S RUN (2026-11-15, 5090 laptop, large-v3-turbo, Aladdin, --runs
   3): chosen stretch from 0:04:50.4 (75 % sound - this reader pauses
   more than Wills; the first 4.5 min were all just over 25 % quiet):
   CUDA0 122.0x, Vulkan0 128.8x. --bench-start 0 (the old way): CUDA0
   148.5x, Vulkan0 155.4x, text from "Aladdin and the Magic Lamp by
   Unknown" (the intro skipped). The old 30 s figures were ~20 % high
   (session 3's 156x / 146x the same); whole-file runs ~1 % (116.4x ->
   115.0x counted on the audio transcribed). Ranking unchanged here.
   HIP: re-run on the Steam Machine later, with a Linux TWhisper build,
   --bench (chosen stretch, greedy) - like for like with the 5090.

### Word edges trimmed of silence (zip 28, on top of 27)
Owner (Aladdin, then Night Watch - a professional reader): "The speaker
would get to the end of a sentence and pause. The start of the next
sentence would already be highlighted." MEASURED on the owner's
Moby-Dick transcript: the first word after a full stop lasts 0.120 s per
letter against 0.060 for others (short words 0.56 s vs 0.20 s) - DTW
starts it in the pause; on the Wills ch 1-2 audio those words began with
0.48 s of silence (median; 101 of 107 over 0.15 s). Sometimes the whole
word sits in the pause ("It" 44.53-45.13, said from 45.13). FIX:
WhisperTrimWordSilence (Whisper.Core): 10 ms frame levels; quiet = below
8 % of the 90th percentile; a word edge with 50 ms+ of quiet moves to 20
ms before the first / after the last loud frame, keeping 80 ms; quiet to
its end -> its last 80 ms only. Never moves outwards. Called per part
after FillGaps in WhisperConsole (when words are made) and EpubBuilder.
TESTED on ch 1-2 (the transcript's words + the audio): sentence-first
words' leading silence 0.48 -> 0.03 s median, over 0.15 s: 101 -> 1 of
107; all words with 0.15 s+ leading silence 142 -> 2 of 1873; starts
moved: ~7 % of words (those after pauses). --from-json has no audio:
transcripts made before this are not trimmed (EpubBuilder trims a saved
one once from the audio). CONSOLE_DELIVERY 28.

### Shared helpers for EpubBuilder (zip 27, on top of 26)
EpubUnum's GUI builder (EpubUnum zip 23) links the library and needs
what WhisperConsole did in its own code. Moved into Whisper.AudioSet
(interface now uses Whisper.Align): WhisperPartAt and WhisperPartFiles
(were the console's PartAt / PartFiles), WhisperTranscriptionToJson (was
JsonWithParts), and WhisperWordFileTimes + TWhisperFileTime(Array): the
timed book words moved into the file each starts in (WriteTimings' loop).
The console uses them; --timings output byte-identical on Moby-Dick
(213544 lines, cmp). CONSOLE_DELIVERY 27.
Zip 23 (replaces 22, same content plus): WhisperConsole's FF, AudioIn and
AudioFiles set to nil before the outer try, next to ExtraModels (Delphi
W1036 "might not have been initialized" on the finally's Free calls).

### Review fixes (zip 20, on top of 9bb9d2a "Claude push")
From a code review by reading (owner, 2026-11-15: "code review", then "y" to
a zip with the four fixes). NOT COMPILED OR RUN in that session (no FPC, no
Delphi, no whisper.cpp there; pasdoc_check and project_check: 0 problems,
verify_layout not run - no record changed): the owner's Delphi build and an
FPC run are their test. FFmpegAPI got its own review and zip (FFmpegAPI-08).
1. Whisper.Components, DoDeactivate: the worker is taken out of FWorker
   BEFORE WaitFor. WaitFor on the main thread runs CheckSynchronize, which
   delivered the worker's wmkComplete, and DeliverMessage freed FWorker -
   the thread DoDeactivate was still waiting on (Windows: "handle is
   invalid"). Only Active := False DURING a run got there: Destroy orphans
   the messages first, and the demo disables Unload while busy. Now
   OnComplete (Cancelled) fires inside Active := False; FDeactivating makes
   TranscribeAsync / Transcribe raise while it waits, so a handler cannot
   start a run on the model about to be freed. TO TEST: Active := False
   from a button while a transcription runs.
2. A cancel before the run starts is no longer lost. TWhisperRun.Execute
   and TWhisperBenchmark.Run cleared FCancel when they STARTED, so a Cancel
   during WhisperLoadWav (TranscribeFileAsync, BenchmarkFileAsync) or while
   waiting for the model was dropped: the run went on to its end and
   closing the form waited for all of it. Now TWhisperRun clears FCancel
   when a run ENDS (FWasCancelled keeps it for Cancelled); an Execute
   cancelled before it started does not call whisper.cpp and collects
   nothing (the context still holds the run before). Consequence: Cancel on
   an idle TWhisperRun stops its NEXT Execute. TWhisperBenchmark never
   clears FCancel: a cancelled benchmark stays cancelled (make a new one).
   TO TEST: TranscribeFileAsync of a long WAV, Cancel at once.
3. Whisper.Words, WhisperBuildWords: tokens a word takes beyond its segment
   (punctuation joined across a segment boundary) are carried into the next
   segment's count (Carry). Before, every later segment of the run gave its
   first word to the segment before - OpenAI's loop, which is per 30 s
   window there and over the whole book here. How often the trigger occurs
   is NOT measured: compare Words[].Segment before / after on a long book.
4. FillGaps into the middle of a segment (a gap of 3 s or more between two
   words of ONE segment): WhisperInsertTranscription puts the words in time
   order and the segments after that segment, so the words of that segment
   are no longer next to each other in Words. Conservative fix, the
   insertion itself is unchanged: WhisperWordsToJson finds a segment's
   words by their segment number (it dropped the second run), and
   WhisperCleanTranscription checks the segment number between First and
   Last and takes the earliest start / latest end for the DTW span. STILL
   SO: that segment's Text covers the inserted stretch too, and the
   inserted segments follow it. Splitting the segment in two was not done
   (its Text and Tokens would have to be split; not without a compiler).
Found in the same review and NOT fixed: Active := False (or freeing the
component) inside a handler of a SYNCHRONOUS Transcribe frees the model
under whisper_full (the model lock is re-entrant on one thread);
TWhisperBenchmark.Cancel reads FCurrentRun without a lock while RunOne
frees it; Whisper.API's finalization frees the library without looking at
FModelCount (a component destroyed after it would call whisper_free through
a freed TWhisperLib - check the unit order once at exit of the demo);
LoadBackends with no folder lets ggml load backends from the current
directory, and SetDllDirectoryW(nil) resets a directory the host program
set; timing uses Now, not a stopwatch; no LICENSE file.

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
  box, AMD Z1 = Windows low-end box; both Vulkan). EXCEPT: session 5 ran
  lib/ + WhisperConsole compiled with FPC 3.0.0 against a Linux whisper.cpp
  1.9.5 build here (layout check passed, DTW words end to end - History).
- WORD TIMINGS (session 5) written, NOT YET TESTED BY THE OWNER on Windows /
  real speech: lib/Whisper.Words (new unit), WordTimestamps on the
  component, IncludeWords on TWhisperRun, console --words / --labels /
  --json / --no-dtw, demo "Word timings" + save as Audacity labels / JSON.
- Last push: 290e4d3 ("Whisper Component back", 2026-11-14 ~23:40: IDE
  re-save of WhisperConsole.dproj - platform blocks and DCC_UsePackage lists,
  harmless). Before it 32feb69 = zip 17 (checked: 10 files identical apart
  from line endings, .gitmodules and the FFmpegAPI submodule gone; checks
  clean; console built with FPC against a separate TFFMpegAPI clone and ran).
  TFFMpegAPI then at 05532ee (IDE re-save of its .dproj files, checked:
  units, requires, platforms and Dcp output unchanged). NOT YET PUSHED:
  TWhisper-18-win32.zip on 290e4d3 (dclWhisperAPIFMX opens on Win32 again).
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
1. WORD-LEVEL TIMINGS - code done (session 5). FIRST WINDOWS RUNS (owner,
   2026-11-14, whole Aladdin, CUDA0 - whisper.cpp's default, no --device):
   - medium.en + DTW: heads medium.en, clean transcript (as without DTW),
     5298 words, 74.3 s vs 54.2 s without DTW (encode 59 vs 24 ms per
     window, decode 7.8 vs 6.7 ms per token: the cost of flash attention
     off). Labels written - NOT YET LISTENED TO.
   - large-v3-turbo + DTW: heads large-v3-turbo detected, but the
     TRANSCRIPT BROKE DOWN at 9:28: a stray "' prefix fed back through the
     previous-text context into every later window; segments shrank to one
     word, phrases were dropped (gaps e.g. 23:44-23:51, 29:03-29:24,
     33:17-33:30), 40 s instead of 20 s. Words from 9:28 on are useless.
   - large-v3-turbo --no-dtw (flash on, token time stamps): clean, 5345
     words, 20.6 s.
   whisper.cpp clears the KV cache at every window (line 7350), so DTW
   leaves no state behind; most likely the different arithmetic of flash
   attention off steered greedy decoding into Whisper's known
   condition-on-previous-text loop. FINAL (owner, 15:33): turbo DTW with
   --no-context (fixed: n_max_text_ctx = 0) is CLEAN - 241 segments, 5300
   words, 25 s, no fallbacks. Side effect: without context many windows
   lose punctuation and capitals (lower-case run-on text). Cure to test:
   --carry-prompt --prompt "Once upon a time, there was a story. It was
   read aloud." (carry_initial_prompt repeats a fixed prompt per window).
   TRIED (owner, 16:07): NO EFFECT - whisper.cpp logged "initial prompt is
   too long (15 tokens), will use only the last 1 tokens": with
   n_max_text_ctx = 0 it uses NO prompt at all (whisper.cpp ~7114, 7298:
   prompt only when n_max_text_ctx > 0; carried prompt limited to
   n_max_text_ctx - 1). FIXED: TWhisperRun.Execute, when MaxTextContext = 0
   and CarryInitialPrompt with a prompt, passes n_max_text_ctx = prompt
   tokens + 1 (whisper_tokenize) - room for the prompt, none for the
   text before. RERUN (owner, 16:30): WORKS - no warning, punctuated
   and capitalised throughout, 198 segments, 5299 words, 25 s, no loop;
   align 5226 exact / 29 similar / 14 interpolated / 3052 not spoken (best
   so far). Side effects of a fresh prompt per window: a window may start
   with an inserted or capitalised word ("He would do nothing", "And
   when"); new mishearing "Aladdon" (twice, 24:19-24:32). RECOMMENDED for
   book runs: turbo + --no-context --carry-prompt + a punctuated prompt. Same run: medium.en --align gave 5218 / 33 / 13 /
   3057 (= the offline test); turbo 5224 / 31 / 14 / 3052, 25 s vs 75 s;
   medium.en dropped the spoken title, turbo kept it.
   Earlier: RESULT (owner, 15:00): turbo
   --no-flash --no-dtw breaks down IDENTICALLY (same 2241 segments, 4999
   words, same times) - FLASH ATTENTION OFF IS THE TRIGGER, NOT DTW.
   turbo DTW --no-context was also identical - because whisper.cpp's
   no_context only drops the text of an EARLIER whisper_full call; the
   windows of one run stay conditioned unless n_max_text_ctx = 0 (its
   "-mc 0"). Fixed: TWhisperParams.MaxTextContext, component NoContext
   now sets it to 0, console --no-context too. Rerun turbo --no-context.
   Earlier plan was: TO TELL: turbo --no-flash --words
   --no-dtw (flash off, no DTW) - loop again? - and turbo --labels ...
   --no-context (DTW without previous-text context). If flash-off alone
   loops, consider NoContext (or a temperature fallback / repetition check)
   as the default for word runs; the EPUB aligner must also cope with
   dropped and repeated text in any case.
   STILL TO DO: check BY EAR against Aladdin (Audacity 3: File > Import >
   Labels; Audacity 4 has only File > Import, which takes the .txt) at
   several points, per model (large-v3-turbo, medium.en,
   base.en, a quantised one) and DTW vs --no-dtw; Vulkan0 runs (owner:
   Vulkan is faster); the benchmark with Word timings on. Then fix what
   the ear finds. Known gap: DTW words are contiguous (a word after a
   pause starts at the previous word's end unless the segment rules catch
   it) - if highlighting / cues need real silences, trim word edges by
   audio energy (or VAD probabilities) as a later step.
2. DONE (session 5, untested): log tidy - abort lines after Cancel are
   info, "Transcription started" shows 'en (English-only model)'. Was: the abort lines whisper.cpp logs after a cancel
   ("encoder_begin_callback returned false - aborting", "failed to
   decode", "failed to encode") show as ERROR - log them as info while a
   cancel is pending; the "Transcription started" line says "language
   auto" for .en models (the run is forced to en) - show the real one.
3. EPUB alignment. ALIGNER V2 (session 5, later): content-based, no
   markup needed (owner: calibre / Kindle / retail EPUBs differ, text and
   recording may be different editions): tokens with numbers as words,
   accents folded, ligatures, soft hyphens; 2:1 / 1:2 joins; speaking-rate
   check -> wamNotSpoken; isolated small clusters dropped and the
   alignment rerun (Gutenberg header title); edge gaps limited to a
   plausible reading distance; regions report. Tested with FPC on Aladdin
   + damaged copies (extra paragraph -> exactly those words not spoken;
   recording-only paragraph -> no effect; rewordings local; preface/TOC ->
   not spoken; debris -> nothing lost). Known: the reader's "End of
   Aladdin ..." pairs with Gutenberg's "END OF THE" next to the last
   sentence (content cannot tell; a markup hint can). Console --align /
   --align-labels for the owner to try. V1 notes: lib/Whisper.Align
   (WhisperAlignText: unique-trigram anchors, longest increasing chain,
   edit-distance pairing in the gaps with a similar-spelling match,
   interpolation between paired words; ends without a paired neighbour
   get no time). Tested here with FPC on the owner's Aladdin EPUB
   (Gutenberg #57, EPUB 2, story in one XHTML of 25 <p>, NO ids) and his
   medium.en DTW JSON: 5202/5261 exact, 46 similar, 13 interpolated
   singles; the broken turbo transcript still 92 % exact. 166k words in
   1.1 s. FOUND: Gutenberg boilerplate (div.pg-boilerplate: header,
   "*** START/END OF THE PROJECT GUTENBERG EBOOK ... ***", licence)
   repeats the title and steals its times - the EPUB layer must leave it
   WAV OVER 4 GB (owner, 17:15: the audiobook converted at full rate was
   5 GB): Whisper.Audio read only the wrapped size (5 GB -> ~0.7 GB: the
   first part of the book, SILENTLY). Fixed in zip 03: data size Int64;
   plain RIFF over 4 GB reads to the end; RF64 / BW64 via ds64; decoded
   1 MB at a time (no 5 GB copy); over High(Integer) frames = error asking
   for 16 kHz mono. Tested (FPC): small RIFF + jfk.wav identical to the
   old reader; RF64; a sparse 4.4 GB float stereo file -> 550M frames,
   75 s. Advice stays: ffmpeg -ac 1 -ar 16000 (~0.9 GB for 8 h).
   MAGICIAN RUN (owner, 19:06; zip 04 on Win64, FFmpeg 8 GPL 62.13 DLLs
   found by name): 36 h 15 m M4B, 40 chapters, --chapters en --no-context
   --carry-prompt (names prompt): chapter lengths decoded EXACTLY
   (9.82 / 5.48 / 13.30 / 2523.27 s ...; "timescale not set" harmless),
   ~1.3 s decode per 40 min chapter, whole book 25 min (87x real time),
   20711 segments, 291521 words, 2 fallbacks, no loops, no word times
   going back. Aligned here (FPC harness, EPUB text extracted in spine
   order, inline tags joined - drop caps OK) with the Calibre EPUB's
   293.5k words in 1.45 s: 282836 exact (96.4%), 6488 similar (2.2%),
   2676 interpolated (0.9%), 1200 not spoken (982 = front matter incl.
   "Foreword to the Revised Edition", not read). Same edition. FINDINGS:
   (a) WHISPER DROPOUTS: 51 transcript gaps > 5 s (444 s), 11 > 10 s; the
   decoder ends a window early and skips the rest (e.g. 23:08-23:31 "set
   the | The Franklin", 54 book words then called NOT SPOKEN - wrong;
   others called interpolated; one with a repeated/garbled sentence).
   Fix to build: re-transcribe each gap (time range + the book words it
   should hold are known), and in the aligner treat book words inside a
   transcript time gap as NOT HEARD, never "not spoken". (b) NAMES are
   most similar pairs (Tsurani->Surani/Sarani/Sorani 588, Borric->Boric
   250, Milamber->Milamba 227, Kasumi->Kazumi 205, Krondor->Crondor 114):
   build the prompt from the book's own frequent names. (c) US/UK
   spellings (armor/armour, honor, harbor) should count as exact;
   contractions (is->it's 97, am->I'm 88) stay similar (may be the
   narrator). (d) console: chapter title "Sorcerer's" shows as mojibake
   (Windows console code page), and "from " is empty when FFmpeg is found
   by name.
   STEP 1 DONE (zip 05, 19:20): (a) Whisper.Align: transcript tokens
   carry SilenceAfter (>= WHISPER_ALIGN_SILENCE = 3 s to the next word);
   AlignGap leaves book tokens unpaired there for COST_GAP_IN_SILENCE
   (0.05) instead of 1, so missing book words go INTO the silence (the
   "set the | The Franklin" case had paired a far "the"); an unpaired run
   spanning >= 3 s with no transcript word starting inside is the new
   wamNotHeard (times interpolated; stats NotHeard; regions; console
   labels "NOT HEARD (check by ear)", words marked " ?"). Magician: 755
   not heard, not spoken 1200 -> 1087, interpolated 2676 -> 2038; the
   remaining big interpolated runs are number splits ("30" ",000" - see
   below) and a real 30-word narrator skip stays NOT SPOKEN (21324-21353,
   "She rode along in silence ..."). Aladdin unchanged (5218/33/13/3057).
   (b) Whisper.Core: TWhisperRun.FillGaps(Samples, var Result, 3 s,
   level 0.01, 20 % voiced) - re-runs Execute on each voiced stretch
   without words (start, between, end; words, else segments), drops
   segments that only repeat the initial prompt, inserts in time order
   with WhisperInsertTranscription (new); events off during the pass.
   Console: on by default (per chapter before appending), logs each gap,
   --no-fill-gaps. Tested here mechanically only (random model, jfk +
   4 s silence + jfk: gap found, inserted, order and ids right). OWNER
   TO TEST: rerun Magician; expect "Second pass: ... words added" lines
   and far fewer not-heard words. TODO noticed: WhisperBuildWords should
   join a token like ",000" to the number before ("30" ",000"); the
   component has no FillGaps property yet.
   MAGICIAN RUN 2 (owner, 19:50, zip 05): second pass looked at 146
   gaps >= 3 s, 51 with sound re-run, 875 words added; 292395 words,
   4 fallbacks, 25 min. Align: not heard 755 -> 46, exact 282835 ->
   283603; left: the 30-word narrator skip (2:26:05) and a 31-word one
   at 27:42:28 stay NOT SPOKEN. Owner found the time stamps suspicious:
   whisper.cpp's own SEGMENT times at a dropout span the skipped speech
   ("[00:23:09.680 --> 00:23:38.840] The Franklin unfastened ..." - the
   words start 23:31), and 19 inserted segments were out of order
   against them; words were right. Zip 06: with DTW, Execute now sets
   each segment's T0 / T1 from its words; FillGaps does up to 3 rounds
   (a partly filled stretch - 23:09 gave 26 of 54 words, skipping the
   first 10 s - is tried again), each stretch once.
   MOMENT OF THE MAGICIAN (owner, 20:00, zip 05/06 build): M4B 8 h 45 m,
   19 chapters (Introduction, Chapter 1..17, Acknowledgements) = UNABRIDGED
   (the 1 h 59 m WAV was the 4 GB wrap); 87768 words, 7 min, 11 fallbacks;
   second pass 9 gaps, 206 words. Aligned with the RETAIL EPUB (87510
   words): 83095 exact (95.0%), 2389 similar, 983 interpolated, 901 not
   spoken (front ads 97, back bio / ads ~650), 0 not heard; 10 passes
   (MAX_PASSES hit: isolated clusters in the bio, 94 dropped - harmless,
   3.8 s). Same edition. FOUND: (a) a decoder LOOP at 5:04:58 - "He was a
   big one of the most powerful things that he had to do." as 7 segments
   (each repeat its own segment) over ~20 s of real speech; (b) a PROMPT
   ECHO at 5:55:47 - "Quasequa, Quasequa, Quasequa." (a prompt name) with
   DTW stretching the words over 30 s (11 s and 17.6 s words), so no gap
   was seen. Zip 07: WhisperCleanTranscription (Core) takes out segments
   wholly inside a loop (phrase of 2-40 words x3+, 9+ words, across
   segments) and prompt-only segments (3+ words or over 3 s; 'Mudge!'
   stays), cuts words > WHISPER_MAX_WORD_SECONDS (4 s) to 1 s, then
   FillGaps fills what that opened (and cleans its own parts). On the
   real transcripts: Moment 7 loop segments + 1 echo + 1 long word;
   Magician 0 / 0 / 2 (no false positives). Console calls it before the
   second pass (logs "Cleaned: ..."). Also zip 07: Whisper.Words joins a
   hyphen / comma / full stop with no space on either side into the word
   ('three-foot-long', '30,000'; OpenAI and we gave 'three' '-foot'
   '-long', '30' ',000'); console flushes stdout / stderr so a log of both
   keeps the order.
   LEARNED HABITS (zip 08, 20:25; owner: "content unaware" - no name
   lists, no LLM): Whisper.Align counts book-token / heard-token pairs of
   the last pass; a book token paired >= 5 times and heard differently in
   >= half of them is learned with each heard form seen >= 2 times,
   unless the heard form is a token of the book (may be the reader) or
   is heard for two book tokens; transcript tokens are rewritten and the
   alignment run again (excluded clusters stay out). Stats.Learned
   ('book=heard (n)'), Stats.LearnedWords; console prints the first 20.
   Magician (run 2): exact 283603 -> 287307 (97.9%), similar 6507 ->
   2865, interpolated 1926 -> 1864, 209 habits, 4 s. Moment (v6 json):
   exact 83473 (95.4%), similar 2037, 59 habits (some odd but harmless:
   cherjal=cherry, geolks=oaks - not book words), 8.4 s because the
   isolation loop hits MAX_PASSES in the author bio (both phases; harmless,
   could be looked at). Aladdin unchanged. Moment v6: second pass caught
   the loop (105 words in 20 s); the echo needs v7.
   MANY FILES (zip 09, 20:30; owner: creators use a file per chapter or
   several per chapter, often OGG / WAV): new lib/Whisper.AudioSet.pas
   (after Whisper.Core in the package): WhisperListAudioFiles (file,
   folder in natural order, .m3u / .m3u8 / .txt playlist),
   TWhisperAudioSet (parts = files, or chapters with --chapters; Read(i)
   one at a time, WAV direct, else FFmpeg; Offset = sum of DECODED
   lengths before, exact when read in order), WhisperAudioPartsToJson.
   WhisperNaturalCompare: case-insensitive, separators and extension
   ignored, digit runs by value, English number words 0-99 (cardinal and
   ordinal, camelCase or separated: chapterOne, Chapter_Twenty-One) and
   stand-alone upper-case Roman numerals (Part IV) as numbers, only where
   a word starts and ends (stone, often, oneself stay words); tested on
   18 names. Owner: a GUI can offer drag and drop to fix the order.
   Console: <audio> may be a folder or playlist; parts logged; JSON gets
   "parts"; --labels writes NAME-01.txt ... per file in file time. Tested
   (random model): folder of ch1.wav, ch2.m4b (3 chapters), ch10.wav with
   and without --chapters, and an .m3u in reverse order.
   MOMENT v7 RUN (owner, 20:26): the cleaning removed the "Quasequa x3"
   echo and a stretched word; but both bad stretches (5:04:57 loop, 20 s;
   5:55:47 echo, 30 s) gave 0 words when transcribed again (the part
   looped / echoed again and was cleaned away), so they stayed as gaps
   (not heard 219; exact 83420). Zip 10: FillGaps retries a stretch that
   gave nothing usable once WITHOUT the prompt at temperature 0.2
   (TWhisperGap.Retried; console says "tried again without the prompt");
   console prints "WhisperConsole, TWhisper delivery N" first.
   DRM CHECK (zip 11, 20:58; owner: Audible books can be kept encrypted
   or decrypted by a tool and keep the .aax name either way): Whisper.FFmpeg
   WhisperMp4Protection reads the top-level boxes to moov (64-bit sizes,
   moov at either end, at most 64 MB read) and looks for box types adrm
   (Audible), drms (FairPlay), sinf / enca (encrypted) with a plausible
   box size in front; TWhisperAudioFile.Create refuses such a file
   ("copy protected ... a DRM-free copy of the book is needed"). No
   decryption is offered, ever. Tested: test.m4b and a copy named .aax ->
   none; a copy with a box renamed adrm -> "Audible DRM (adrm)"; a WAV ->
   none. .aax added to the folder extensions. MOMENT v10: both bad
   stretches recovered by the retry without the prompt (68 and 89 real
   words); exact 83558 (95.5%), not heard 52 (53 words at 1:10:05 where
   "she" was stretched 24 s - the retry got only the stretch's end).
   SILVERTHORN BLIND TEST (owner, 21:10; v10, generic prompt, the owner
   told nothing; decrypted .aax): 16 h 52 m, 24 parts, 11.5 min, 132336
   words, 19 fallbacks, no loops / echoes, second pass 41 gaps re-run,
   553 words (1 retry). Calibre EPUB (131278 words): 128349 exact
   (97.8%), 1516 similar, 1061 interpolated, 94 not spoken (28 = start
   of the "Our Story So Far" recap; the rest 4-13-word runs - candidate
   reader skips / edition differences), 0 not heard; 150 habits learned
   with no prompt help (arutha=aruta 713, arruta 149; calin heard 5 ways;
   US/UK spellings), 2.3 s.
   HOBBIT (owner, 21:42; v11, decrypted .aax, generic prompt): 10 h 25 m,
   21 chapters, 7.5 min, 95820 words, 0 gaps >= 5 s left (29 re-run, 5
   retries). EPUB = a DIFFERENT EDITION: HarperCollins illustrated, EPUB 3
   (iBooks prefix), 48 spine items, 77 images, captions
   p.image_caption, verse p.vext / vext1 / vext3, chapter heads h1.cn +
   h1.ct; 105764 words. Aligned: 94229 exact, 679 similar, 664
   interpolated, 10155 not spoken, 5 not heard, 8.2 s, 29 habits (dwarf
   names: bombur=bomba 38, kili=killy 32, dori=dory 27, dain=dane 25,
   oin=owen 17...). Not spoken = front matter 8604 (accessibility note,
   introductions), back 1419 (other books, credits), and the IMAGE
   CAPTIONS one by one (10 of them, 4-13 words: "The Misty Mountains
   looking West ...") - correctly not spoken; two candidate reader /
   abridgement differences: the "(Look at the map at the beginning of
   this book ...)" aside (17 words) and a 15-word Troll line. Story
   body ~95.5k words: ~98.7% exact. EPUB layer: captions (and other
   figure text) must stay outside the sync (no span, no SMIL entry) -
   the aligner already marks them not spoken.
   GPU MEMORY PLAN (owner 21:55-22:01; build AFTER the EPUB layer):
   free VRAM is known (ggml device memory, already in the device list);
   the risk is OTHER programs taking it during a run and a failed
   allocation inside compute aborting the process (CUDA's pool grows
   during compute). Layers: (1) save each finished part to disk + resume
   from the first unfinished one; (2) measured need per model (benchmark
   records free before / after load) + a pre-load check with ~1 GB
   margin; ladder: other GPU -> same GPU with system-RAM fallback ->
   smaller model -> CPU; (3) GUI: transcription in a WORKER PROCESS
   (crash-proof, and the only way to change the switches below - they
   are read once per process), free memory shown during the run.
   UNIFIED / SYSTEM MEMORY SWITCHES (checked in whisper.cpp 1.9.5 /
   ggml source): GGML_CUDA_ENABLE_UNIFIED_MEMORY (ggml-cuda.cu
   ggml_cuda_device_malloc -> cudaMallocManaged; static const, read once);
   GGML_VK_ALLOW_SYSMEM_FALLBACK, GGML_VK_PREFER_HOST_MEMORY,
   GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM (ggml-vulkan.cpp device init).
   HIP shares the CUDA code: the same CUDA switch -> hipMallocManaged;
   on WINDOWS hipMallocManaged is unsupported and the code warns and
   falls back to hipMalloc (switch does nothing) - use Vulkan there;
   on Linux it works (oversubscription depends on GPU / XNACK / HMM;
   test on the Steam Machine); Linux APUs (UMA) read free memory from
   /proc/meminfo. CUDA managed memory oversubscribes on Linux only; on
   Windows NVIDIA drivers (536+) have their own "CUDA Sysmem Fallback
   Policy" (Control Panel, default on) - from memory, not verified.
   SETTING THEM: in our own process BEFORE TWhisperLib.Load loads the
   backends: Windows SetEnvironmentVariableW AND ucrtbase.dll's
   _wputenv_s (the UCRT keeps its own copy, built at its first getenv;
   _wputenv_s updates both), bound by name; POSIX libc setenv. Plan: a
   load option (e.g. GpuMemoryFallback) that sets the right variables
   per backend and platform. Spilled memory is reached over PCIe: many
   times slower for that work, but no crash.
   NIGHT WATCH - FOOTNOTES (owner, 22:02; v11): 14 h 41 m, 75 parts, 10
   min, 113701 words. Calibre EPUB from MOBI (filepos anchors); the 10
   footnotes are each a <p> with <sup class="calibre7">*</sup> in its own
   split file (split_013-022) AFTER the copyright page; references are
   '*' + links in the text; no epub:type. Aligned: 108369 exact, 1900
   similar, 2062 interpolated, 1211 not spoken, 10 not heard, 48 habits
   (carcer=carsa 45, keel=kiel 45, dickins=dickens 39), 3.3 s; story
   ~96.5% exact. The NARRATOR READS EACH FOOTNOTE IN PLACE (at its
   reference: note 1 at 0:27:35, 63 unpaired transcript words there,
   53 of 61 4-grams found; all 10 found): in book order they are at the
   end -> "not spoken", and their spoken words sit unpaired in the
   transcript. Main text unaffected. PLAN (content-unaware, no footnote
   detection needed): a RELOCATION PASS after the main alignment - each
   not-spoken book run is searched (n-grams) among the transcript's
   unpaired stretches; a strong match takes those times (a new match
   kind, e.g. moved). Catches footnotes read in place, moved paragraphs,
   reordered editions. The EPUB layer then gives note text its own spans
   and SMIL entries at the spoken time.
   RELOCATION PASS DONE (zip 12, 22:15): Whisper.Align Relocate after the
   learned-habit passes: transcript words used = paired (plus the
   transcript words inside a paired word's time); unpaired stretches of
   >= RELOCATE_MIN_STRETCH (4) words, their 3-token grams indexed; each
   not-spoken run (>= 4 words; punctuation-only words inside it count)
   is a work list of token ranges: best stretch by hits, the hits bound
   the book and transcript ranges, accepted with >= 3 hits and >= 0.4 of
   the book grams between first and last hit, aligned with AlignGap;
   paired words -> wamMoved (WordIndex / times where spoken), unpaired
   words between moved ones placed between them; what is left either
   side goes back on the work list (one run held all ten notes). Stats
   .Moved; regions; console prints moved. Night Watch: all 10 footnotes
   moved to where they are read (0:27:35 ... 12:21:31), 441 words, not
   spoken 1211 -> 770. Other books: Magician / Hobbit / Silverthorn /
   Aladdin 0 moved; Moment 6 ("copyright (c) 1984 by Thranx, Inc." found
   in the end credits - right). EPUB layer: moved words keep their book
   place for the text, their spoken time for SMIL.
   LATER (owner, 18:19): turn the FFmpeg code into its own reusable
   components - TFFmpegAPI - "good reusable code". To settle when it is
   taken up: (1) where it lives - inside TWhisper (own runtime package
   FFmpegAPI before WhisperAPI in BUILD ORDER) or a separate repository
   that TWhisper and SRDelphiFMX both use; (2) framework-free core +
   TCustom... base + FMX publish, as TCustomWhisper / TWhisperAPI; (3)
   names without "Whisper" (TFFmpegDynLib or shared DynLib, FFmpeg.Layout
   tool); (4) scope beyond audio (video decode as SRDelphiFMX does,
   metadata, cover art, chapters for the EPUB layer). Not started.
   FFMPEG INPUT DONE (zip 04, 2026-11-14 ~18:15): lib/Whisper.FFmpeg.pas
   (TWhisperFFmpeg loads avutil-60 / swresample-6 / avcodec-62 /
   avformat-62 by name through TWhisperDynLib, in that order, from a
   folder or exe folder + system path; checks majors and the Pascal record
   layout; TWhisperAudioFile: chapters, Read(start, end) -> 16 kHz mono via
   swr_convert, seek + trim to the range). Large-struct fields by offset
   (FFOFS_* from Whisper.FFmpegLayout.inc, generated by
   tools/ffmpeg_layout.py from FFmpeg 8.1 headers for all 9 targets:
   P64 / P32 / P32I386 like whisper.h). The owner's DelphiFFmpeg.com
   headers (BSD-style, 8.1, external declarations, "tested Win32 only";
   SRDelphiFMX uses them with "delayed") were NOT copied in: TWhisper
   binds by name and only needs ~35 functions. Whisper.Core:
   WhisperAppendTranscription (join chapter results with a time offset).
   Console: non-.wav input through FFmpeg, --chapters, --ffmpeg FOLDER
   (default: exe folder / system path, then whisper.dll's folder); bench
   reads through FFmpeg too. TESTED here (FPC 3.0, Linux x64, FFmpeg 8.1
   built from source, LGPL minimal): a generated 3-chapter AAC 22.05 kHz
   stereo M4B of jfk.wav - chapters read in reverse order each match
   jfk.wav (lag ~18 samples, ~1 ms); whole file; a 1 s range; console
   --chapters with offsets right in segments, words and JSON; the WAV path
   unchanged; a missing-FFmpeg message. NOT TESTED: Delphi build, Win64
   DLLs (owner's 8.x; avformat 62.13), Win32, a real audiobook.
   M4B FIRST (owner, 17:51: "doing m4b would be easier as it's internally
   chapterised"): FFmpeg input moves up, ahead of / together with the
   EPUB layer. Plan: Whisper.FFmpeg unit loading the FFmpeg 8 shared dlls
   by name (avformat-62, avcodec-62, avutil-60, swresample-6; same
   pattern as whisper.dll, no static linking); read chapters (start/end/
   title from AVFormatContext.chapters), decode + resample to 16 kHz mono
   ONE CHAPTER AT A TIME (bounded memory, no 37 h limit), transcribe per
   chapter, word times offset by the chapter start. The chapter list is
   also the first guide for matching audio to EPUB chapters. AAX (Audible)
   is DRM'd - not read; DRM-free m4b only. Owner's ffmpeg is Lavf62.13
   (FFmpeg 8.x); needs a SHARED build for the dlls.
   (Book 2's audiobook turned out ABRIDGED - 1 h 59 for ~86.7k words; the
   owner dropped it, 17:48.)
   EPUB TEST BOOK 3 (owner, 17:48): a CALIBRE conversion (calibre 0.9.0,
   from an OpenOffice-made book; Raymond E. Feist, HarperCollins 2012) -
   COPYRIGHTED, local tests only. Shape: EPUB 2, one source split into
   38 files Magician_split_NNN.html + calibre titlepage.xhtml; ~293k words
   (very long - likely 30 h+ of audio; 16 kHz mono reaches High(Integer)
   frames at 37.3 h). Real Unicode punctuation (no entities). Body
   p.calibre4; parts in h1, chapters in h2 (number spelled out, " - ",
   title) with empty anchors inside; SPLIT DROP CAPS: the first letter in
   span[title]>span.calibre5>b.calibre6, the rest of the word straight
   after the closing tags - words must join across inline tags (only
   whitespace, <br> and block ends separate words); <br> inside
   paragraphs (verse / letters) and empty p.western3 of <br>s as scene
   breaks.
   EPUB TEST BOOK 2 (owner, 2026-11-14): a DRM-free RETAIL EPUB (Alan Dean
   Foster, Open Road) - COPYRIGHTED: never commit any of it or text from
   it; local tests only. Shape: EPUB 2 (OPF 2.0 + NCX), XHTML 1.1 files
   named .html, UTF-8 with BOM, all punctuation as numeric references
   (&#8217; &#8220; &#8230; &#8212;); spine = cover, 2 publisher ads,
   image, title, contents, dedication, image, 17 chapters (headings are
   Roman numerals in p.ct linking to contents), image, bio, credits, 2 ads;
   2 files in the zip are not in the spine. Body p.tx; first paragraph
   p.tx1 opens with a small-caps lead-in in <small> (whole words, upper
   case, sometimes with <i> inside - not a split drop cap); p.ttx = verse
   (the spellsongs), often in <i>; ~86.7k words (~9-10 h audio). Em dash
   between words 13x (split handles U+2014); ellipsis always followed by
   a space. Needs: spine order, entity decoding, BOM, words keeping their
   file + text-node offsets for span wrapping across <i>/<small>, Roman
   numeral headings vs spoken "Chapter One".
   out. NEXT: the EPUB layer (lib/, Delphi System.Zip / FPC zipper): read
   OPF + spine, pick the spoken text (skip boilerplate, keep headings
   such as the h1 title), split at white space and dashes, wrap words or
   sentences in <span id>, write SMIL per XHTML, upgrade to EPUB 3
   (version 3.0, nav document, media-overlay, media:duration, audio in
   the package); numbers / abbreviations ("Mr", "XIV") as later
   refinements. Then the cue builder for subtitles (below).
4. FFmpeg input (mp3 / m4a / m4b) - needed for real audiobooks.
5. Later: CUDA 12.9 + 13 fallback; NPU / OpenVINO (plans below).
The owner said "no more backends yet".

## Plans (agreed, not started)

### Benchmark stretch - DONE in zip 26 (moved to the zip 26 notes below)

### Volunteer transcribers (owner's idea, 2026-11-15 - design only)
LibriVox readers have no GPU; the owner's Mac (and anyone's idle machine
with a decent GPU) could transcribe for them. Shape discussed:
- A server keeps a job list; WORKERS POLL it (no inbound ports, works
  behind any router), take a job with a lease, post the result back; a
  lapsed lease puts the job back on the list.
- A job is usually a LINK, not an upload: LibriVox's own files on
  archive.org + the text edition (LibriVox readers mostly read a known
  Gutenberg edition). One job per LibriVox SECTION file (a chapter or
  two) - minutes of GPU time, spread over many machines.
- The worker returns the transcript JSON only (--json); the server
  aligns (seconds - Moby-Dick re-aligned in 11 s) and keeps the texts
  and edition checks in one place.
- Results check themselves: a right recording of the right text aligns
  ~98 % exact (Moby-Dick); a low figure = wrong file / bad worker /
  garbage -> redo elsewhere; spot re-runs on a second machine.
- Workers report what they can do when they ask: GPU memory, models
  they can run, backend and speed from their OWN TWhisperBenchmark run
  (never a fixed rule - Vulkan beat CUDA on the 5090 laptop, HIP beat
  Vulkan on the Steam Machine: HIP.md). Results record the model, so a
  turbo transcript can be redone with large-v3 later.
- Memory: large-v3 ~3 GB, large-v3-turbo ~1.6 GB plus working space -
  6 GB+ is comfortable (owner: "any OK GPU would be OK at transcription
  as long as it had 6Gb+").
- Candidate workers: the owner's Mac (Metal; no audio output needed, so
  macOS works headless now), the Steam Machine (HIP, ~28x on Aladdin with
  beam search - HIP.md), the Deck (Vulkan only), gaming PCs.
- Worker = WhisperConsole --json + a fetch / transcribe / upload loop.
- Pairs with EpubUnum's plans: timings published beside the original
  EPUB, pointing at LibriVox's downloads (see Epubunum CLAUDE.md, "Shall
  we do this"); LibriVox recordings and Gutenberg texts are public
  domain - a conversation with LibriVox is about working together.

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

### Proof-listener for LibriVox (owner, 2026-11-14: give it away free)
Automated proof-listening: the section text + the recording -> every
place the reading differs, with its time, as Audacity labels the reader
imports to overdub / re-record. Built on Whisper.Align (its not-spoken and
interpolated regions, and the paired words that differ). FIRST TEST
(Aladdin, two transcripts: medium.en and turbo, flagging only where BOTH
disagree with the text): ~16 candidates in 35 min, most genuine misreadings
(4:16 "to a niche", 4:22 "bring it to me", 8:53 "the napkin", 13:28 "and
bade", 15:19 "I will", 16:59 "intended", 24:07 "In that instant", 24:13
"was scaling", 31:31 "her face", 32:47 "he replied", 34:02 "in your
wife's head"); false alarms e.g. "sorter"/"daughter" (accent), "hit"/"hid".
Rules: NEVER give Whisper the book text as prompt (it would correct the
reader); two models or decodes, flag only agreements; word probability as
confidence. Inputs: Gutenberg .txt (plain-text path) or EPUB, MP3 (needs
the FFmpeg step); find the section inside the whole book by content. Also:
check the LibriVox intro / outro wording. Limits: Whisper drops stumbles
and doubled words, so false starts are not reliably caught. Default model
for volunteers' laptops: base.en / small.en on CPU, medium.en "thorough".
Later a small FMX app.

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

### AMD (HIP) and Intel Arc (SYCL / OpenVINO) - wait for testers
Owner (2026-11-14): support them once someone can test; Vulkan covers both
until then.
- HIP: EVERYTHING IS IN HIP.md (repository root) - HIP SDK 7.x facts,
  AMD's official 7.2 list, laptops, the whisper-dev to-dos (new target
  list without gfx1030, Windows DLL names, Linux bundling, gfx11-generic),
  the Steam Machine Linux test procedure and results (HIP 28.1x vs Vulkan
  22.7x on gfx1102 - HIP wins there, the opposite of the 5090 laptop), the
  comparison with the 5090 and the open steps. Keep HIP.md up to date
  instead of repeating it here.
- Intel Arc: Vulkan now; candidates ggml-sycl (oneAPI DPC++ / icx: a
  second tree like HIP; large oneAPI runtime DLLs) and the OpenVINO GPU
  device (see NPU plan). The owner's Intel iGPU can do a first SYCL /
  OpenVINO smoke test, but Arc numbers need an Arc card.

### FMX on Linux / Steam - reuse TSteamAPI's findings (same owner)
TSteamAPI's CLAUDE.md and docs/ (fmx-steamos-gtk3-bug*.md,
fmx-menu-bug-fix.md) cover FMXLinux; apply them to the demo when Linux
starts: use Steam Linux Runtime 3.0 "sniper" (4.0 has no GTK 3: "GTK 3 is
required" + runtime error 217); add TSteamAPI's FmxLinuxGtkGlobal unit
(dlopen libgtk-3 / libgdk-3 RTLD_GLOBAL - otherwise FMX's global dlsym
misses GTK inside pressure-vessel and creating a TListBox (combo-box
popups too) calls nil = AV); FmxLinuxMenu if the demo gets a menu (GTK
bar shows first letters only); libfmux is unpacked by FMXLinux itself
(~/.fmxlinux), not a depot file; the game folder is NOT writable in the
runtime - settings / logs / output under the user's folders (XDG); log to
stderr for "%command% > file 2>&1" captures. SteamOS's remaining issues in
TSteamAPI are 3D only (a Gorilla3D bug, owner 2026-11-14) - they do not
affect TWhisper. Our own libs:
whisper / ggml .so beside the exe, loaded with RTLD_LAZY (local) - fine.

### Other open items
WhisperConsole --check on each platform; macOS dyld reuse of preloaded
dylibs (else build with @loader_path rpath, README); the Android library
folder (bare-name load path); a VCL twin; the token-data shim on ARM64
(compiler record return, as TSteamAPI's Motion shim).

## History (sessions 1-5, newest last)
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
Session 5 (2026-11-14, word timings): lib/Whisper.Words (model header ->
DTW alignment heads; tokens -> words, a port of OpenAI's timing.py /
tokenizer.py word grouping, punctuation merge and segment-boundary rules;
JSON and Audacity label export); TWhisperRun.IncludeWords,
TWhisperTranscription.Words / WordTiming, TWhisperModel.DtwEnabled,
WhisperSaveTextFile (UTF-8, no BOM); component WordTimestamps; benchmark
picks DTW heads per model. Found in whisper.cpp 1.9.5 source (5922450):
- flash_attn (default ON) silently disables DTW -> WhisperEnableDtw turns
  it off.
- t_dtw = where the DTW path ENTERS the next token's row = OpenAI's END of
  the token (OpenAI's start of token k = entry into row k, whose input is
  the token before). So token start = previous token's t_dtw.
- With DTW the new_segment_callback loop is "for (seg = size - n; seg < n;
  ...)": no callbacks after the first window -> segments are also
  collected in the encoder_begin callback (they are final by then).
- DTW WHISPER_ASSERTs n_frames <= 2 * audio_ctx (AudioContext > 0 = process
  dies) -> refused; its DTW decode runs without the abort callback (cancel
  cannot hit its "DECODER FAILED" assert).
- With VAD only segment t0/t1 are mapped back to original time, not token
  times -> words + Vad refused.
- TWhisperTokenInfo.Special was "id >= [_BEG_]"; now "id >= EOT" (SOT,
  language, [_SOLM_] ... are not text either). New field Utf8 (raw bytes:
  tokens can split a character; words are joined from bytes).
- One deliberate deviation from OpenAI: a token made only of closing marks
  ('!"', '."', '),') merges into the previous word (OpenAI only merges
  single marks, leaving '!"' as a word - bad for dialogue-heavy books).
TEST METHOD THAT WORKS IN THE CLOUD (no Delphi): FPC 3.0.0 x86_64-linux is
committed in github.com/macmike/fpc-lambda (fpc-runtime/fpc3; sparse
checkout ~100 MB; ppcx64 in lib/fpc/3.0.0, units beside it; link with
-k-ldl -k-lc). It lacks TStringBuilder (3.2+) - give a scratch copy a
small stand-in unit. Hugging Face is blocked and GitHub copies of models
are LFS, so make a RANDOM-WEIGHT model: header + mel filters + vocab of
whisper.cpp's models/for-tests-ggml-tiny.en.bin (ftype set to 0) followed
by f32 tensors named and shaped as in whisper_model_load. It transcribes
nonsense but runs every code path (DTW, callbacks, words, export). Done
here: whisper.cpp 1.9.5 built (GGML_BACKEND_DL, CPU variants), FPC-built
WhisperConsole: --check passed (111 values), DTW run over 44 s (two
windows): tiny.en heads detected, flash attention off, all segments
delivered, words / JSON / labels written; --no-dtw gives token-timestamp
words. A unit test of WhisperBuildWords (split UTF-8 character, quotes,
parentheses, pause, Japanese per-character) gave the expected words.
