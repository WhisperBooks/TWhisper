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
```

Word options: `--words` loads the model with DTW (alignment heads from the
model file, flash attention off) and prints every word with its start, end
and probability; `--labels FILE` writes an Audacity label track instead,
`--json FILE` segments and words as JSON (both imply `--words`); `--no-dtw`
takes the times from whisper.cpp's token time stamps, to compare.

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
