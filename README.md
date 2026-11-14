# TWhisperAPI - whisper.cpp for Delphi (FMX)

A Pascal binding of [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
(local speech-to-text with OpenAI's Whisper models) for Delphi FireMonkey.
It follows the structure and source rules of
[TSteamAPI](https://github.com/G3DGames/TSteamAPI):

- a framework-free core in `lib/` that also compiles with FPC 3.2.2
- one non-visual component, `TWhisperAPI`, for FMX in `fmx/`
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
WAV files in any rate, bit depth and channel count and converts them, RF64
and WAV files over 4 GB included.

## Other audio formats and audiobook chapters (FFmpeg)

Everything FFmpeg reads - M4B / M4A, MP3, FLAC, Ogg, Opus, the sound of
a video - comes in through **TFFMpegAPI** (github.com/G3DGames/TFFMpegAPI,
package `FFmpegAPI`, units `FFmpeg.API` and `FFmpeg.Media`): FFmpeg's **shared**
libraries, loaded at run time by name like whisper.cpp's. Nothing is
linked in; a program that never opens such a file never needs them.
TWhisper has no FFmpeg code of its own: the libraries, their versions and
struct layout, chapters, decoding, cover art, copy protection and FFmpeg's
licence are all FFmpegAPI's - see its README.

- **Getting it:** TFFMpegAPI is installed separately, before TWhisper is
  built - see "Packages and demos".
- **Which libraries:** FFmpeg 8 as a "shared" build - `avutil-60.dll`,
  `swresample-6.dll`, `avcodec-62.dll`, `avformat-62.dll` on Windows (the
  usual single `ffmpeg.exe` downloads have no DLLs). The licence is in the
  log line; `TFFmpegLibrary.Create(Folder, flpLGPL)` refuses GPL and
  non-free builds.
- **Chapters:** an audiobook is best transcribed a chapter at a time: one
  chapter in memory, however long the book. `TWhisperAudioSet` (below)
  does that, or directly:

```pascal
FF := TFFmpegLibrary.Create;                   // FFmpeg.API; or Create('C:\ffmpeg\bin')
Book := TFFmpegMediaFile.Create(FF, 'book.m4b');  // FFmpeg.Media
Dec := TFFmpegAudioDecoder.Create(Book, -1, WHISPER_SAMPLE_RATE, 1);  // 16 kHz mono
for I := 0 to High(Book.Chapters) do
begin
  Samples := TWhisperSamples(Dec.Read(Book.Chapters[I].StartTime, Book.Chapters[I].EndTime));
  Part := Run.Execute(Samples);
  WhisperAppendTranscription(All, Part, Book.Chapters[I].StartTime);
end;
```

Copy-protected files (Audible `.aax` straight from Audible, FairPlay) are
refused by FFmpegAPI with a clear message; a DRM-free copy reads like any
M4B whatever its extension.

**A recording in many files** - one file per chapter, several files per
chapter, WAV / FLAC / OGG / MP3 mixed - is a `TWhisperAudioSet`
(`Whisper.AudioSet`): `WhisperListAudioFiles` takes a file, a folder
(every audio file in it, in natural order) or a playlist (`.m3u`, `.m3u8`,
`.txt`); each file is a part, or each chapter of a file with chapters, read
one at a time. A part's `Offset` on the joined time line is the sum of the
lengths decoded before it, so a word's time maps back exactly to a file and
a time in it. The natural order reads file names as people do, without
case: `chapter2` before `chapter10`, and `chapterOne`, `ChapterTwo`,
`chapter_three`, `chapter4`, `Part IV`, `Twenty-First` by their numbers
(English number words and Roman numerals, where a word starts and ends).
A playlist fixes any other order.

## Choosing the device (and model)

whisper.cpp can be told which device to use, but only by position: its
`gpu_device` counts the GPU and integrated-GPU devices in ggml's list. ggml
loads backends in a fixed order (CUDA, HIP, Vulkan), so on an NVIDIA machine
`CUDA0` always comes before `Vulkan0`, and whisper.cpp left alone always
takes CUDA. On some systems Vulkan is faster for real transcription, and only
timing real transcription tells. The binding therefore:

- lists the devices: `TWhisperLib.Devices` / `TWhisperAPI.Devices` give name
  (`CPU`, `CUDA0`, `Vulkan0`, `ROCm0`, ...), description, backend, type and
  memory;
- selects one by name: `TWhisperAPI.Device := 'Vulkan0'`, or
  `TWhisperLib.ContextParamsFor` for the classes. `'CPU'` means no GPU. An
  unknown name falls back to the default with a warning, so a program keeps
  working when a GPU disappears;
- times them: `TWhisperBenchmark` / `TWhisperAPI.BenchmarkFileAsync`.

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

## Word timings

Segments are far too coarse to sync text to speech (the first segment of an
audiobook can span 26 s), so the binding gives every word its own start and
end. The accurate source is DTW: dynamic time warping over the
cross-attention of the model's alignment heads, OpenAI's `word_timestamps`
method, which whisper.cpp implements as `dtw_token_timestamps`.

- **Component:** set `WordTimestamps := True` before `Active`. Every
  `TWhisperTranscription` then has `Words` (text, `T0` / `T1` in 10 ms units,
  probability, segment index) and `WordTiming` (`wwtDtw`).
- **Classes:** `WhisperEnableDtw(ModelFile, ContextParams)` before
  `TWhisperModel.Create`, then `TWhisperRun.IncludeWords := True`.
- **Export:** `WhisperWordsToLabels` (an Audacity label track, to check the
  timings by ear: File > Import > Labels in Audacity 3, File > Import in
  Audacity 4) and `WhisperWordsToJson` (segments with their words). Save with
  `WhisperSaveTextFile` (UTF-8 without a byte order mark).

What `WhisperEnableDtw` does, and why:
- **Alignment heads:** it reads the model file's header and picks the
  matching heads: tiny ... large-v3, large-v3-turbo, quantised files too.
  large-v1 and v2 share a header, so a file name with `v1` means v1. Other
  models (distil-whisper) get the top half of the decoder layers, OpenAI's
  default.
- **Flash attention OFF:** whisper.cpp's default is on, and it silently
  disables DTW with flash attention. Runs are therefore somewhat slower;
  benchmark with word timings on to see by how much (the benchmark chooses
  the heads per model).
- **DTW memory:** `dtw_mem_size` grows when the heads need more than the
  default 128 MB.

How tokens become words (`Whisper.Words`): a port of OpenAI's timing.py.
- **Joining:** tokens are joined into whole UTF-8 characters, then into
  words at spaces. Chinese, Japanese, Thai, Lao, Burmese and Cantonese have
  no spaces, so every character is a word.
- **Punctuation:** opening marks join the following word, closing marks the
  previous one. Tokens such as `!"` and `."` count too, which OpenAI's rule
  misses.
- **Boundaries:** words at sentence ends and after pauses are bounded by
  the median word duration and the segment's own start and end.

Things to know:
- **DTW times are token ENDS.** whisper.cpp's `t_dtw` is where the
  alignment path enters the next token's row, so a token starts where the
  previous one ended. Words are therefore contiguous: there are no silences
  between them.
- **Without DTW** (a model loaded without it, or `--no-dtw` in the console),
  words come from whisper.cpp's token time stamps. These are a heuristic and
  noticeably less accurate.
- **Not with `Vad`:** whisper.cpp maps only segment times back to the
  original audio, not token times. `TWhisperRun` refuses the combination.
- **`AudioContext` must be 0** on a DTW model: whisper.cpp asserts
  otherwise, which ends the process, so `TWhisperRun` refuses it.
- **Live segments with DTW:** whisper.cpp 1.9.5's new-segment callback stops
  after the first 30 s window. `TWhisperRun` also collects segments when the
  next window starts, so `OnSegment` keeps arriving.

## Aligning a book's text (EPUB sync, proof-listening)

`WhisperAlignText(WhisperSplitText(BookText), Transcription.Words, Stats)`
(`Whisper.Align`) gives every word of the book its spoken time, or marks it
**not spoken**. The book is the text of record: the transcript only supplies
times, so its misspellings and mistakes never reach the reader.

Nothing relies on markup: where the reading starts and ends follows from the
alignment itself. That matters because Gutenberg, calibre and retail EPUBs
all differ, and text and recording may come from different editions.
- **Tokens.** Lower case, letters and digits only. Soft hyphens and
  zero-width characters are dropped, Latin accents folded and ligatures
  expanded. Numbers become words: "40" = forty, "1867" = eighteen sixty
  seven, "21st" = twenty first.
- **Anchors.** Three-token sequences found exactly once in both texts. Only
  the longest chain that runs in order through both is kept.
- **Gaps.** Between anchors, an edit-distance alignment pairs equal or
  similar tokens (Mustapha / Mustafa), and two tokens against one when they
  spell the same ("on to" / "onto").
- **Times.** Unpaired words take the time between their neighbours, unless
  that would mean reading far faster than this reader does (2.5 times their
  speed, and at least 6 words a second). Such a run was not spoken, and so
  is text before the first or after the last timed word.
- **Silences of the transcript.** Where the transcript has no words for
  3 s or more (`WHISPER_ALIGN_SILENCE`), the book words it lacks go into
  that silence and are **not heard** (`wamNotHeard`), not blamed on the
  reader: the recogniser may have dropped them. `TWhisperRun.FillGaps`
  transcribes such stretches again first (whisper.cpp sometimes ends a 30 s
  window early and skips the rest of it).
- **The recogniser's habits.** After a first alignment, a book word heard
  differently in at least half of its places (5 or more) is learned with
  each way it was heard twice or more - unless that form is itself a word
  of the book, where the difference may be the reader's. The alignment is
  run again with these counting as equal. Nothing about names or spelling
  is built in: "Tsurani" heard as "Surani", "Borric" as "Boric", "armor" as
  "armour" are all learned from the book and the recording alone. For a
  proof-listener this is the line between the recogniser's habit (all
  through the book) and a reader's slip (once). `Stats.Learned` lists them.
- **Moved text.** A run not spoken in book order is looked for among the
  transcript words nothing paired with (three-word sequences, close
  together); found, it is **moved** (`wamMoved`) and timed where it was
  spoken. Nothing marks footnotes in most EPUBs, and none is needed: in a
  Discworld novel whose ten footnotes sit after the copyright page, the
  narrator reads each where it is referenced, and all ten were found and
  timed there (441 words).
- **Coincidences.** A small cluster of matches with unspoken text on both
  sides is taken out and the alignment is run again. Gutenberg's header
  repeats the title, so this finds the title where it is really read.
- **Report.** `WhisperAlignRegions` lists the stretches that were not
  spoken or not heard clearly.

Tested on Aladdin (Gutenberg #57, medium.en DTW words), with the whole EPUB
text including the Gutenberg header and licence:

| Test | Result |
|---|---|
| The book as it is | 5218 exact, 33 similar, 13 interpolated (each alone); header and licence not spoken |
| Book has an extra 130-word paragraph | exactly those 130 words not spoken |
| Recording has a paragraph the book lacks | no effect |
| Preface and table of contents repeating the title | all not spoken |
| Soft hyphens, ligatures, accents, numbers as digits | no word lost |

A 166k-word book aligns in about a second.

Tested on a 36-hour unabridged audiobook (M4B, 40 chapters, large-v3-turbo
DTW words, 291 521 words) against a calibre EPUB of the same edition
(293 527 words): 96.4 % exact, 2.2 % similar (mostly invented names), 0.7 %
interpolated, 0.4 % not spoken (mostly a foreword the reader does not
read; one 30-word sentence the reader skipped), 0.3 % not heard (where
whisper.cpp dropped speech), in 1.4 s; with the second pass, not heard fell
from 755 words to 46, and learning the recogniser's habits (209 of them,
mostly invented names) took exact to 97.9 % and similar to 1.0 %. A retail EPUB (Open Road) against its 8 h 45 m
audiobook: 95.0 % exact, the publisher's front and back matter not spoken.

Before the second pass, `WhisperCleanTranscription` takes out what the
decoder made up: a sentence repeated as a loop over real speech, a carried
prompt given back ("Name, Name, Name." stretched over 30 s), and words DTW
stretched over speech it skipped. The gaps that leaves are transcribed
again.

In WhisperConsole: `--align book.txt --align-labels book-labels.txt` (see
demos/WhisperConsole/README.md).

## Using the component

1. Build and install the packages (see below), drop a `TWhisperAPI`
   (palette page "WhisperAPI") on a form and set `ModelFile`.
2. Set `Active := True` (in code, or in the form file). This loads the
   library, checks the record layout and loads the model. A failure fires
   `OnLoadFailed`, or is shown if that event is not assigned. It never
   raises.
3. Call `TranscribeFileAsync('speech.wav')` or `TranscribeAsync(Samples)`.
   `OnSegment`, `OnProgress`, `OnLog` and finally `OnComplete` arrive on the
   main thread. `Cancel` stops a run and keeps the segments so far.

```pascal
procedure TfrmMain.WhisperAPI1Segment(Sender: TObject; const ASegment: TWhisperSegment);
begin
  memText.Lines.Add(Format('[%s --> %s] %s', [WhisperTimeToStr(ASegment.T0),
    WhisperTimeToStr(ASegment.T1), ASegment.Text]));
end;
```

`Transcribe` / `TranscribeFile` run on the calling thread instead. Set
`Device` before `Active` to choose the compute device (see above). Published
properties cover the common settings (Language, Translate, Threads,
Strategy, BeamSize, TokenTimestamps, MaxSegmentLength, InitialPrompt, Vad,
WordTimestamps, ...). `Params` and `OnBeforeRun` give access to every field of
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
  Whisper.Words         word timings: model header -> DTW heads, tokens -> words, JSON / Audacity labels
  Whisper.Align         book text <-> transcript words: every book word gets its spoken time
  Whisper.Core          TWhisperModel, TWhisperParams, TWhisperRun, TWhisperBenchmark, text export
  Whisper.AudioSet      a recording in many files (folder, playlist, chapters) on one time line; FFmpeg via TFFMpegAPI
  Whisper.Components    TCustomWhisper (lifecycle, worker thread, main-thread events)
fmx/       Whisper.FMX (TWhisperAPI), Whisper.FMX.Reg (design time)
packages/  WhisperAPI (runtime, requires rtl and TFFMpegAPI's FFmpegAPI), WhisperAPIFMX (runtime), dclWhisperAPIFMX (design): .dpk + .dproj
WhisperAPI.groupproj   every project: runtime packages, design package, apps
demos/     WhisperDemo (FMX), WhisperConsole (console, smoke test): .dpr + .dproj + README.md
tools/     verify_layout.py, pasdoc_check.py, gen_projects.py, project_check.py
```

## Packages and demos

**Dependency: TFFMpegAPI.** TWhisper depends on it; install it first,
like any third-party component: clone github.com/G3DGames/TFFMpegAPI anywhere, open its
`FFmpegAPI.groupproj`, Build All for every platform you target (and Win32
for the 32-bit IDE), and install `dclFFmpegAPIFMX` (`TFFmpegAPI`, palette
page "FFmpegAPI"). Its runtime package's `FFmpegAPI.dcp` and DCUs then sit
in Delphi's Dcp folder, where `WhisperAPI` (which requires it) and the
demos find them; nothing of it is in this repository or in
`WhisperAPI.groupproj`. Rebuild it there after updating TFFMpegAPI, then
rebuild TWhisper's packages.

Then open **`WhisperAPI.groupproj`** at the repository root. It lists the
projects in build order:
1. the runtime package `WhisperAPI`;
2. the FMX runtime package `WhisperAPIFMX`;
3. the design package `dclWhisperAPIFMX`;
4. the demos.

"Cannot find FFmpegAPI.dcp" (or a missing `FFmpeg.*` unit) means
TFFMpegAPI is not built for that platform yet.

Build All compiles each package before everything that needs it, so
Delphi's quick re-compilation works. Keep that order: another one breaks
builds. `tools/project_check.py` reports any other order.

| Project | Kind | Platforms |
|---|---|---|
| `demos/WhisperDemo` | FMX application | Win64, macOS, Linux64 |
| `demos/WhisperConsole` | console | Win64, macOS, Linux64 |
| `packages/WhisperAPI` | runtime, rtl only: `lib/` | + Win32 (for the 32-bit IDE), Android64 |
| `packages/WhisperAPIFMX` | runtime: `Whisper.FMX` | + Win32 (for the 32-bit IDE), Android64 |
| `packages/dclWhisperAPIFMX` | design: registers `TWhisperAPI` | Win32 / Win64 (the IDE's) |

1. **Runtime packages:** build `WhisperAPI` and `WhisperAPIFMX` (after TFFMpegAPI's `FFmpegAPI`) for every platform
   you target. Their DCUs go to `$(BDSCOMMONDIR)\Dcp\$(Platform)`, next to
   their `.dcp`, which is on the IDE's default Library path. Projects using
   the library therefore need no search paths. Debug and Release share that
   folder (the last build wins).
2. **Design package:** install `dclWhisperAPIFMX` for the IDE you run
   (TFFMpegAPI's `dclFFmpegAPIFMX` is installed from its own repository).
   - With the 32-bit IDE that means building the runtime packages for Win32
     too. The IDE loads them, but never loads whisper.dll, so no 32-bit DLL
     is needed.
   - With the 64-bit IDE (Delphi 12.2+), build them for Win64 only.
3. **Demos:** they use the library like any user project. They list only
   their own sources and link the packages' DCUs, so build the packages
   first; a library change needs a package rebuild before a demo sees it.
   Each demo's `README.md`, shown by the IDE as the project page, says what
   goes next to the executable.
4. **Libraries:** copy whisper-dev's `dlls\` folder next to the built
   executable (for example `demos\WhisperDemo\Win64\Debug`), put it on
   PATH, or set `LibraryPath`.

The project files were generated by `tools/gen_projects.py`, as in TSteamAPI.
Once the IDE has re-saved them, the saved files are authoritative.
`tools/project_check.py` checks them: BOM, XML, the same units in `.dpr` /
`.dpk` and `.dproj`, and that every group member exists.

Run **WhisperConsole first** on every new platform:

```
WhisperConsole --check                                       library, layout check, device list
WhisperConsole --bench ggml-base.en.bin jfk.wav              time every device
WhisperConsole --bench ggml-base.bin talk.wav en --also ggml-small.bin --seconds 60
WhisperConsole --bench ggml-large-v3-turbo.bin book.wav --seconds all --devices CUDA0,Vulkan0 --runs 3
WhisperConsole ggml-base.en.bin jfk.wav --device Vulkan0     transcribe on a chosen device
WhisperConsole ggml-base.bin speech.wav auto --tokens        detect language, token data
WhisperConsole ggml-large-v3-turbo.bin book.wav --labels words.txt --json words.json
                                                             word timings (DTW), Audacity labels + JSON
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
  `TWhisperAPI.CheckLayout` (default on) refuses a library that fails.
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
python3 tools/project_check.py                      .dproj / .groupproj / .dpr / .dpk consistency
python3 tools/verify_layout.py <whisper.cpp> --write  after updating whisper.cpp
```
