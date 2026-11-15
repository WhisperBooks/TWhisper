# WhisperConsole - running and deploying (Windows)

Console smoke test of the binding, without the component. Run it first on
every new platform: library loading, the record layout check, the device
list and a transcription, each step logged with its values.

## Before the first build

Build the runtime package **WhisperAPI** for the same platform first (open
`WhisperAPI.groupproj` at the repository root and build all).

## Next to WhisperConsole.exe

Everything from **whisper-dev's `dlls\` folder** (see
demos/WhisperDemo/README.md for the list), copied next to the executable,
e.g. `Win64\Debug\` - or that folder on PATH.

## Commands

```
WhisperConsole --check                                       library, layout check, device list
WhisperConsole --bench ggml-base.en.bin jfk.wav              time every device
WhisperConsole --bench ggml-base.bin talk.wav en --also ggml-small.bin --seconds 60
WhisperConsole --bench ggml-large-v3-turbo.bin book.wav --seconds all --devices CUDA0,Vulkan0 --runs 3
WhisperConsole ggml-base.en.bin jfk.wav --device Vulkan0     transcribe on a chosen device
WhisperConsole ggml-base.bin speech.wav auto --tokens        detect language, token data
WhisperConsole ggml-large-v3-turbo.bin aladdin.wav --labels aladdin-words.txt --json aladdin.json
                                                             word timings (DTW)
WhisperConsole ggml-large-v3-turbo.bin aladdin.wav --labels aladdin-tokens.txt --no-dtw
                                                             the same from token time stamps
WhisperConsole ggml-large-v3-turbo.bin book.m4b --chapters --json book.json
                                                             an audiobook, chapter by chapter
```

Audio: a file, a **folder** (every audio file in it, in natural order -
`chapter2` before `chapter10`, `chapterOne` before `ChapterTwo`, without
case) or a **playlist** (`.m3u`, `.m3u8` or a `.txt` list, for any other
order). Several files are transcribed one at a time on one joined time
line; `--json` adds a `"parts"` list (file, title, start and end in the
file, offset on the joined time line) and `--labels NAME.txt` writes one
label track per file (`NAME-01.txt`, ...) with that file's own times.
A `.wav` file is read directly; any other file (`.m4b`, `.m4a`,
`.mp3`, `.flac`, `.ogg`, ...) through FFmpeg 8's shared libraries -
`avutil-60.dll`, `swresample-6.dll`, `avcodec-62.dll`, `avformat-62.dll`
from a "shared" FFmpeg build - next to the executable, on PATH, in
whisper.dll's folder, or in the folder given with `--ffmpeg FOLDER`. The
log shows the chapters. `--chapters` transcribes one chapter at a time (one
chapter in memory, however long the book), with times from the start of
the file; the language heard in the first chapter is kept for the rest.

Word options: `--words` loads the model with DTW (alignment heads from the
model file, flash attention off) and prints every word with its start, end
and probability; `--labels FILE` writes an Audacity label track instead,
`--json FILE` segments and words as JSON (both imply `--words`); `--no-dtw`
takes the times from whisper.cpp's token time stamps, to compare.
`--no-flash` turns flash attention off without DTW (DTW always turns it
off), to tell a difference caused by DTW from one caused by the different
arithmetic. `--no-context` stops each 30 s window from being conditioned on
the text before it, so a mistake cannot repeat from window to window.
An unknown option starting with `-` is an error.

`--prompt TEXT` gives an initial prompt: vocabulary, names, and the style of
the text. `--carry-prompt` repeats it in every 30 s window. With
`--no-context` the windows otherwise lose their punctuation and capitals,
and a punctuated prompt should keep them. The prompt is then the only
context each window gets (the "Transcribing:" line says "initial prompt in
every window"):
```
.\WhisperConsole ggml-large-v3-turbo.bin aladdin.wav --no-context --carry-prompt --prompt "Once upon a time, there was a story. It was read aloud." --labels words.txt
```

`--align BOOK.txt` aligns the words with the text of record. The book is a
UTF-8 plain text, for example a Project Gutenberg `.txt`; implies `--words`.
It prints how many book words were matched, then every stretch of at least
three words that was **not spoken** (the reader skipped it, or it is front
matter or a licence), **interpolated** (spoken, but not heard as written) or
**not heard** (the transcript has no words there for 3 s or more - the
recogniser dropped them, or it is music or silence: check by ear), each with
its time. `--align-labels FILE` writes the book's own words as Audacity
labels (interpolated and not-heard words end in " ?"), plus a "NOT SPOKEN"
label where each skipped stretch belongs and a "NOT HEARD" label at each
stretch to check by ear.

Second pass: after each run (each chapter with `--chapters`) every
stretch of 3 s or more without words that has sound in it is transcribed
again on its own and put in place - whisper.cpp sometimes ends a 30 s
window early and skips the rest of it (51 such stretches in a 36-hour
audiobook; the pass added 875 words there). A stretch only partly filled
is tried again (up to three rounds). Each one is logged; `--no-fill-gaps`
turns the pass off. With DTW words, segment times are taken from their
words: whisper.cpp's own segment time stamps can span seconds of skipped
speech. That is the start of an automated
proof-listener for LibriVox recordings.
```
.\WhisperConsole ggml-medium.en.bin aladdin.wav --align aladdin.txt --align-labels aladdin-book.txt
```

## Syncing an EPUB (with EpubUnum's EpubConsole)

Three steps, joined by plain files - TWhisper and EpubUnum stay separate:

1. The book's words, numbered as the reader numbers them:
   ```
   .\EpubConsole book.epub --words book-words.txt
   ```
2. Transcribe the recording once, save it as JSON, align it with those
   words and write the timed words:
   ```
   .\WhisperConsole ggml-large-v3-turbo.bin C:\audio\book --chapters --no-context --carry-prompt --prompt "It was read aloud, with care." --json book.json --align-words book-words.txt --timings book-timings.txt
   ```
   `<audio>` can be a folder (every file in it, in natural order) or a
   playlist. `--align-words` leaves out the contents page; reports give
   the EPUB's word numbers. `--timings` writes one line per timed word
   ("number start end audio", seconds in that audio file) after the list
   of the files ("# audio N: path"); words not spoken or not heard get no
   line.
3. Write the synced book (EPUB 3 media overlays; the audio files named in
   the timings are copied in):
   ```
   .\EpubConsole book.epub --overlay book-timings.txt book-synced.epub
   ```

To align again - another edition of the book, a newer aligner - without
transcribing again (no model, seconds):

```
.\WhisperConsole --from-json book.json --align-words book-words.txt --timings book-timings.txt
```

`--from-json` also takes `--align`, `--align-labels` and `--labels`.

**Checking word timings by ear:** open the WAV in Audacity, File > Import >
Labels..., choose the labels file. Each word is a label over the audio:
click a label to select its span and play it (space). Check the start of a
chapter, a passage of fast dialogue, a pause between sentences, numbers and
names.

Benchmark options: `--seconds N|all` (audio per timed run, default 30),
`--devices A,B` (only those devices), `--runs N` (median of N timed runs),
`--threads N` (CPU threads; the benchmark gives the CPU device every logical
processor by default - whisper.cpp's own default of at most 4 makes a modern
CPU look several times slower than it is).

Exit code 0 = success. `--check` must print "Layout check passed"; a layout
failure means the libraries were built from a different whisper.h than the
binding (README, "C ABI details").
