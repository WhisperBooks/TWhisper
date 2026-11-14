(* @abstract(Object layer over the flat API: @link(TWhisperModel) (a loaded
  model), @link(TWhisperParams) (transcription settings) and
  @link(TWhisperRun) (one transcription with Pascal events), plus text export
  helpers.)

  Framework-free (no FMX / VCL / LCL); compiles with Delphi and FPC. Events
  of @link(TWhisperRun) run on the thread that calls
  @link(TWhisperRun.Execute); the TWhisperAPI component (Whisper.Components)
  runs it on a worker thread and moves the events to the main thread.

  @longCode(#
  var
    Model: TWhisperModel;
    Params: TWhisperParams;
    Run: TWhisperRun;
    R: TWhisperTranscription;
    I: Integer;
  begin
    TWhisperLib.Load;
    Model := TWhisperModel.Create('ggml-base.en.bin', True);
    Params := TWhisperParams.Create;
    Run := TWhisperRun.Create(Model, Params);
    try
      R := Run.Execute(WhisperLoadWav('jfk.wav'));
      for I := 0 to High(R.Segments) do
        WriteLn(WhisperTimeToStr(R.Segments[I].T0), ' ', R.Segments[I].Text);
    finally
      Run.Free;
      Params.Free;
      Model.Free;
    end;
  end;
  #) *)
unit Whisper.Core;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes, SyncObjs, DateUtils,
  Whisper.Types, Whisper.API, Whisper.Words;

type
  { A loaded model (whisper_context). Thread-safe to share; transcriptions
    on one model run one at a time (@link(Lock)). For parallel runs load
    the model several times. }
  TWhisperModel = class
  private
    { The library the model was loaded with. }
    FLib: TWhisperLib;
    { The C context. }
    FCtx: PWhisperContext;
    { Backing field of @link(FileName). }
    FFileName: string;
    { Serialises runs on this model (they share the context's state). }
    FLock: TCriticalSection;
    { @true once counted in the library (TWhisperLib.ModelCreated). }
    FCounted: Boolean;
    { Backing field of @link(ContextParams). }
    FContextParams: TWhisperContextParams;
    { Shared code of the constructors. }
    procedure Init;
  public
    { Loads a model file.
      @param(AFileName  A ggml model (ggml-*.bin).)
      @param(AParams  Context params, from @code(TWhisperLib.DefaultContextParams).)
      @raises(EWhisperError when the library is not loaded or the model
        cannot be loaded - the log says why.) }
    constructor Create(const AFileName: string; const AParams: TWhisperContextParams); overload;
    { Loads a model file with default context params.
      @param(AUseGPU  Use the GPU backend when the library has one.) }
    constructor Create(const AFileName: string; AUseGPU: Boolean = True); overload;
    { Loads a model from memory (e.g. an Android asset). ABuffer is only
      read during the call. }
    constructor CreateFromBuffer(ABuffer: Pointer; ASize: NativeUInt;
      const AParams: TWhisperContextParams);
    { Frees the model (whisper_free). }
    destructor Destroy; override;

    { Waits until no other run uses the model and takes it. }
    procedure Lock;
    { Releases the model taken with @link(Lock). }
    procedure Unlock;

    { @true for a multilingual model (else English only). }
    function IsMultilingual: Boolean;
    { Model type as text ('tiny', 'base', 'small', 'medium', 'large'). }
    function ModelType: string;
    { Vocabulary size. }
    function VocabSize: Integer;
    { One line describing the model, for logs (with the DTW alignment heads
      when DTW is on). }
    function Description: string;
    { @true when the model was loaded with DTW token times
      (@code(WhisperEnableDtw)): runs then give accurate word timings. }
    function DtwEnabled: Boolean;

    { The C context, for calls through @code(TWhisperLib.Flat). }
    property Handle: PWhisperContext read FCtx;
    { The library. }
    property Lib: TWhisperLib read FLib;
    { File the model came from ('' for a buffer). }
    property FileName: string read FFileName;
    { Context params the model was loaded with. }
    property ContextParams: TWhisperContextParams read FContextParams;
  end;

  { Transcription settings: @link(TWhisperFullParams) with Pascal
    properties, strings kept alive here. Starts from the library's
    defaults, with whisper.cpp's own console printing turned off. Use
    @link(Raw) for the fields without a property. }
  TWhisperParams = class
  private
    { The C params (string pointers are set by Build). }
    FRaw: TWhisperFullParams;
    { Backing field of @link(Language). }
    FLanguage: string;
    { Backing field of @link(InitialPrompt). }
    FInitialPrompt: string;
    { Backing field of @link(SuppressRegex). }
    FSuppressRegex: string;
    { Backing field of @link(VadModelFile). }
    FVadModelFile: string;
    { UTF-8 copy of FLanguage that the C params point to. }
    FLanguageU8: UTF8String;
    { UTF-8 copy of FInitialPrompt that the C params point to. }
    FInitialPromptU8: UTF8String;
    { UTF-8 copy of FSuppressRegex that the C params point to. }
    FSuppressRegexU8: UTF8String;
    { UTF-8 copy of FVadModelFile that the C params point to. }
    FVadModelFileU8: UTF8String;
    { Getter of @link(Raw). }
    function GetRaw: PWhisperFullParams;
  public
    { Library defaults for AStrategy; BestOf and BeamSize both 5.
      @raises(EWhisperError when the library is not loaded.) }
    constructor Create(AStrategy: TWhisperSamplingStrategy = wssGreedy);
    { Copies every setting of ASource. }
    procedure Assign(ASource: TWhisperParams);
    { The C params for a run: a copy of @link(Raw) whose string fields point
      into this object (valid while it lives and is not changed).
      @param(AMultilingual  @false for an English-only model: an 'auto' or
        empty language becomes 'en' (no detection step).) }
    function Build(AMultilingual: Boolean = True): TWhisperFullParams;

    { The C params; change any field (strings: use the properties). }
    property Raw: PWhisperFullParams read GetRaw;
    { Decoding strategy. }
    property Strategy: TWhisperSamplingStrategy read FRaw.strategy write FRaw.strategy;
    { CPU threads (library default: up to 4). }
    property Threads: Int32 read FRaw.n_threads write FRaw.n_threads;
    { Language code ('en', 'de', ...); 'auto' or '' = detect. }
    property Language: string read FLanguage write FLanguage;
    { Only detect the language, do not transcribe. }
    property DetectLanguageOnly: Boolean read FRaw.detect_language write FRaw.detect_language;
    { Translate to English. }
    property Translate: Boolean read FRaw.translate write FRaw.translate;
    { Start offset in ms. }
    property OffsetMs: Int32 read FRaw.offset_ms write FRaw.offset_ms;
    { Duration to process in ms (0 = to the end). }
    property DurationMs: Int32 read FRaw.duration_ms write FRaw.duration_ms;
    { whisper.cpp's no_context: start without the text of an EARLIER
      whisper_full call on the same context. It does NOT stop the 30 s
      windows of one run from being conditioned on the text before them -
      that is @link(MaxTextContext) = 0. }
    property NoContext: Boolean read FRaw.no_context write FRaw.no_context;
    { Most tokens of the text so far given to the decoder as context for the
      next 30 s window (whisper.cpp's n_max_text_ctx; library default 16384,
      capped at half the model's text context). 0 = every window is decoded
      on its own (OpenAI's condition_on_previous_text = False): a mistake
      such as a stray quote cannot repeat window after window, at some cost
      in consistency of spelling and punctuation. With 0 and
      @link(CarryInitialPrompt), a run gives whisper.cpp just enough room for
      the initial prompt (whisper.cpp would otherwise drop the prompt too),
      so every window sees the prompt and nothing else. }
    property MaxTextContext: Int32 read FRaw.n_max_text_ctx write FRaw.n_max_text_ctx;
    { Do not produce time stamps. }
    property NoTimestamps: Boolean read FRaw.no_timestamps write FRaw.no_timestamps;
    { One segment only (streaming). }
    property SingleSegment: Boolean read FRaw.single_segment write FRaw.single_segment;
    { Token-level time stamps. }
    property TokenTimestamps: Boolean read FRaw.token_timestamps write FRaw.token_timestamps;
    { Max segment length in characters (0 = no limit); 1 = one word per segment
      with TokenTimestamps and SplitOnWord. }
    property MaxSegmentLength: Int32 read FRaw.max_len write FRaw.max_len;
    { Split on words rather than tokens (with MaxSegmentLength). }
    property SplitOnWord: Boolean read FRaw.split_on_word write FRaw.split_on_word;
    { Max tokens per segment (0 = no limit). }
    property MaxTokens: Int32 read FRaw.max_tokens write FRaw.max_tokens;
    { Audio context size (0 = model's; smaller = faster, less accurate). }
    property AudioContext: Int32 read FRaw.audio_ctx write FRaw.audio_ctx;
    { tinydiarize speaker turns (needs a tdrz model). }
    property SpeakerTurns: Boolean read FRaw.tdrz_enable write FRaw.tdrz_enable;
    { Initial prompt: vocabulary, names, style. }
    property InitialPrompt: string read FInitialPrompt write FInitialPrompt;
    { Repeat the initial prompt in every window. With @link(MaxTextContext)
      = 0 the prompt is the only context a window gets: punctuation and
      capitals from a punctuated prompt, no carried-over mistakes. }
    property CarryInitialPrompt: Boolean read FRaw.carry_initial_prompt write FRaw.carry_initial_prompt;
    { Regular expression of tokens to suppress. }
    property SuppressRegex: string read FSuppressRegex write FSuppressRegex;
    { Suppress blank output at the start. }
    property SuppressBlank: Boolean read FRaw.suppress_blank write FRaw.suppress_blank;
    { Suppress non-speech tokens. }
    property SuppressNonSpeech: Boolean read FRaw.suppress_nst write FRaw.suppress_nst;
    { Initial temperature. }
    property Temperature: Single read FRaw.temperature write FRaw.temperature;
    { Temperature increment of the fallback (0 = no fallback). }
    property TemperatureInc: Single read FRaw.temperature_inc write FRaw.temperature_inc;
    { Entropy threshold of the fallback. }
    property EntropyThreshold: Single read FRaw.entropy_thold write FRaw.entropy_thold;
    { Log probability threshold of the fallback. }
    property LogprobThreshold: Single read FRaw.logprob_thold write FRaw.logprob_thold;
    { No-speech threshold. }
    property NoSpeechThreshold: Single read FRaw.no_speech_thold write FRaw.no_speech_thold;
    { Greedy: candidates when sampling with temperature. }
    property BestOf: Int32 read FRaw.greedy_best_of write FRaw.greedy_best_of;
    { Beam search: beams. }
    property BeamSize: Int32 read FRaw.beam_search_beam_size write FRaw.beam_search_beam_size;
    { Voice activity detection (needs VadModelFile, e.g. ggml-silero-v6.2.0.bin). }
    property Vad: Boolean read FRaw.vad write FRaw.vad;
    { VAD model file. }
    property VadModelFile: string read FVadModelFile write FVadModelFile;
    { VAD speech probability threshold. }
    property VadThreshold: Single read FRaw.vad_params_threshold write FRaw.vad_params_threshold;
    { VAD minimum speech duration, ms. }
    property VadMinSpeechMs: Int32 read FRaw.vad_params_min_speech_duration_ms
      write FRaw.vad_params_min_speech_duration_ms;
    { VAD minimum silence duration, ms. }
    property VadMinSilenceMs: Int32 read FRaw.vad_params_min_silence_duration_ms
      write FRaw.vad_params_min_silence_duration_ms;
    { VAD padding around speech, ms. }
    property VadSpeechPadMs: Int32 read FRaw.vad_params_speech_pad_ms write FRaw.vad_params_speech_pad_ms;
  end;

  { New segment of a run. }
  TWhisperSegmentEvent = procedure(Sender: TObject; const ASegment: TWhisperSegment) of object;
  { Progress of a run, 0..100. }
  TWhisperProgressEvent = procedure(Sender: TObject; AProgress: Integer) of object;

  { A stretch of a transcription without words that @link(TWhisperRun.FillGaps)
    looked at. Times in 10 ms units of the transcription. }
  TWhisperGap = record
    { Start: the end of the word before (0 at the start). }
    T0: Int64;
    { End: the start of the word after (the end of the audio at the end). }
    T1: Int64;
    { Share of 20 ms frames above the sound level, 0..1. }
    Voiced: Single;
    { Words the second pass found there (0 when it was not run or found
      nothing usable). }
    Words: Integer;
    { The gap was transcribed again (it had sound). }
    Transcribed: Boolean;
    { The first try gave nothing usable (a loop or the prompt given back),
      so it was tried once more without the prompt, at temperature 0.2. }
    Retried: Boolean;
  end;
  { Gaps, in time order. }
  TWhisperGapArray = array of TWhisperGap;

  { One transcription: runs whisper_full on the calling thread and turns
    the C callbacks into Pascal events. Reusable: call Execute again. }
  TWhisperRun = class
  private
    { The model. }
    FModel: TWhisperModel;
    { The settings. }
    FParams: TWhisperParams;
    { Set by Cancel; polled by the abort and encoder-begin callbacks. }
    FCancel: Boolean;
    { Segments collected so far. }
    FSegments: TWhisperSegmentArray;
    { Used length of FSegments. }
    FCount: Integer;
    { Backing field of @link(IncludeTokens). }
    FIncludeTokens: Boolean;
    { Backing field of @link(IncludeWords). }
    FIncludeWords: Boolean;
    { End-of-text token of the model: ids from here on are not text. }
    FEot: TWhisperToken;
    { Last progress reported (no duplicates). }
    FLastProgress: Integer;
    { First exception raised by an event handler inside a callback. }
    FHandlerError: string;
    { Backing field of @link(Running). }
    FRunning: Boolean;
    { Backing field of @link(OnSegment). }
    FOnSegment: TWhisperSegmentEvent;
    { Backing field of @link(OnProgress). }
    FOnProgress: TWhisperProgressEvent;
    { Reads one finished segment from the context. }
    function ReadSegment(ACtx: PWhisperContext; AIndex: Integer): TWhisperSegment;
    { Collects (and reports) segments not collected yet. Robust against
      the n_new value of the callback, which is not always a count. }
    procedure CollectNew(ACtx: PWhisperContext);
    { Called by the progress callback. }
    procedure DoProgress(AProgress: Integer);
    { Records a handler exception and cancels the run. }
    procedure HandlerFailed(E: Exception);
  public
    { A run of AModel with AParams (neither is owned). }
    constructor Create(AModel: TWhisperModel; AParams: TWhisperParams);
    { Transcribes ASamples (mono, 16 kHz). Waits for other runs on the same
      model. Does not raise for whisper.cpp errors (see ResultCode /
      ErrorMessage of the result).
      @raises(EWhisperError when ASamples is empty, an event handler raised,
        or the settings cannot work: IncludeWords with Vad, or AudioContext
        on a model loaded with DTW (whisper.cpp would end the process).) }
    function Execute(const ASamples: TWhisperSamples): TWhisperTranscription;
    { Second pass over the stretches of AResult (a run over ASamples)
      without words: whisper.cpp sometimes ends a 30 s window early and
      skips the rest of it, leaving 5 - 25 s of speech untranscribed. Every
      such stretch of at least AMinGapSeconds that has sound in at least
      AMinVoiced of its 20 ms frames (RMS of at least AMinLevel) is
      transcribed again on its own and its segments and words are put in
      place. Segments that only repeat the initial prompt (what a carried
      prompt gives back on silence) are dropped; a stretch that gives
      nothing usable is tried once more without the prompt at temperature
      0.2 (the prompt is what the decoder gave back). A stretch only partly
      filled leaves a shorter one, tried again in a next round (at most
      three rounds; each stretch once). OnSegment and OnProgress are not
      called for this pass. Works on segments when AResult has no words.
      @returns(Every gap looked at, with what was found, in the order
        looked at.) }
    function FillGaps(const ASamples: TWhisperSamples; var AResult: TWhisperTranscription;
      AMinGapSeconds: Double = 3; AMinLevel: Single = 0.01; AMinVoiced: Single = 0.2): TWhisperGapArray;
    { Asks the run in progress to stop (any thread). It stops at the next
      check; the segments so far are kept and the result says Cancelled. }
    procedure Cancel;
    { @true while Execute runs. }
    property Running: Boolean read FRunning;
    { @true after Cancel (reset by Execute). }
    property Cancelled: Boolean read FCancel;
    { Fill TWhisperSegment.Tokens. }
    property IncludeTokens: Boolean read FIncludeTokens write FIncludeTokens;
    { Fill TWhisperTranscription.Words (@code(WhisperBuildWords)); also
      fills the tokens. The times come from DTW when the model was loaded
      with it (@link(TWhisperModel.DtwEnabled)), else from whisper.cpp's
      token time stamps, which are then turned on for the run (less
      accurate). With DTW the segments of the result then span their words
      (whisper.cpp's own segment time stamps can be far out where it
      skipped speech; OnSegment still reports them as they came). Not with
      Vad: whisper.cpp does not map token times back to the original
      audio. }
    property IncludeWords: Boolean read FIncludeWords write FIncludeWords;
    { Each new segment, on the thread of Execute. }
    property OnSegment: TWhisperSegmentEvent read FOnSegment write FOnSegment;
    { Progress 0..100, on the thread of Execute. }
    property OnProgress: TWhisperProgressEvent read FOnProgress write FOnProgress;
  end;

  { A model is about to be timed on a device. }
  TWhisperBenchmarkStartEvent = procedure(Sender: TObject; const AModelFile: string;
    const ADevice: TWhisperDevice) of object;
  { A device has been timed. }
  TWhisperBenchmarkEvent = procedure(Sender: TObject; const AResult: TWhisperBenchmarkResult) of object;

  { Times transcription with one or more models on several devices, to find
    the fastest device (per model, or the fastest model / device pair) on
    this machine. For each model and device: load the model onto it, run a short warm-up
    (one-time costs: shader / kernel compilation, allocation), then a timed
    run on the same audio. Runs on the calling thread and takes a while
    (seconds per device, more for big models): use a worker thread or
    @code(TCustomWhisper.BenchmarkDevicesAsync). Results are only
    comparable for the same model, audio and settings, so time with the
    model and kind of audio you will use. }
  TWhisperBenchmark = class
  private
    { Backing field of @link(ModelFiles). }
    FModelFiles: TStringList;
    { Audio (mono, 16 kHz). }
    FSamples: TWhisperSamples;
    { Backing field of @link(Params). }
    FParams: TWhisperParams;
    { Backing field of @link(ContextParams). }
    FContextParams: TWhisperContextParams;
    { Backing field of @link(MaxSeconds). }
    FMaxSeconds: Double;
    { Backing field of @link(WarmupSeconds). }
    FWarmupSeconds: Double;
    { Backing field of @link(CpuThreads). }
    FCpuThreads: Integer;
    { Backing field of @link(Runs). }
    FRuns: Integer;
    { Set by Cancel. }
    FCancel: Boolean;
    { The run in progress (for Cancel). }
    FCurrentRun: TWhisperRun;
    { Backing field of @link(OnStart). }
    FOnStart: TWhisperBenchmarkStartEvent;
    { Backing field of @link(OnResult). }
    FOnResult: TWhisperBenchmarkEvent;
    { The first ASeconds of the audio. }
    function Slice(ASeconds: Double): TWhisperSamples;
  public
    { A benchmark of AModelFile on ASamples (at least a few seconds of
      speech; MaxSeconds of it are used). Add more models to ModelFiles to
      compare them too.
      @raises(EWhisperError when the library is not loaded or there is no audio.) }
    constructor Create(const AModelFile: string; const ASamples: TWhisperSamples);
    { Frees ModelFiles. }
    destructor Destroy; override;
    { Times every model of ModelFiles on every device of ADevices, model by
      model (empty ADevices: all of @code(TWhisperLib.SelectableDevices)). A
      pair that fails is reported (Ok = @false) and the next one is tried.
      @returns(One result per pair timed (fewer when cancelled).) }
    function Run(const ADevices: TWhisperDeviceArray): TWhisperBenchmarkArray;
    { Times one model on one device. }
    function RunOne(const AModelFile: string; const ADevice: TWhisperDevice): TWhisperBenchmarkResult;
    { Stops after the run in progress (any thread). }
    procedure Cancel;
    { Index of the fastest successful result; -1 when none succeeded.
      @param(AModelFile  '' = over every model (the fastest pair); a model
        file = the fastest device for that model.) }
    class function Best(const AResults: TWhisperBenchmarkArray; const AModelFile: string = ''): Integer; static;

    { Models to time (the constructor's model is the first). }
    property ModelFiles: TStringList read FModelFiles;
    { Transcription settings of the runs (not owned; @nil = defaults with
      language 'auto'). Use the settings you will use for real. }
    property Params: TWhisperParams read FParams write FParams;
    { Model loading settings (flash attention, ...); use_gpu and gpu_device
      are set per device. With dtw_token_timestamps on, the alignment heads
      are chosen per model (@code(WhisperEnableDtw); custom heads are kept),
      so the timing includes the cost of word timings. Default: the
      library's defaults. }
    property ContextParams: TWhisperContextParams read FContextParams write FContextParams;
    { Seconds of audio in the timed run (default 30: one full encoder window,
      the unit whisper.cpp works in); 0 or less = the whole audio. }
    property MaxSeconds: Double read FMaxSeconds write FMaxSeconds;
    { CPU threads when timing the CPU device: 0 (default) = every logical
      processor (TThread.ProcessorCount). whisper.cpp's own default is at
      most 4, which leaves most of a modern CPU idle and makes it look far
      slower than it is. GPU devices use Params.Threads. }
    property CpuThreads: Integer read FCpuThreads write FCpuThreads;
    { Timed runs per model / device (default 1); with more, RunMs and Speed
      come from the median run, so short clips give stable rankings. }
    property Runs: Integer read FRuns write FRuns;
    { Seconds of audio in the warm-up run (default 5). }
    property WarmupSeconds: Double read FWarmupSeconds write FWarmupSeconds;
    { @true after Cancel. }
    property Cancelled: Boolean read FCancel;
    { Before each model / device pair (on the calling thread). }
    property OnStart: TWhisperBenchmarkStartEvent read FOnStart write FOnStart;
    { After each model / device pair (on the calling thread). }
    property OnResult: TWhisperBenchmarkEvent read FOnResult write FOnResult;
  end;

{ Text of a whisper_full result code. }
function WhisperResultText(ACode: Integer): string;

{ The segments as plain text, one per line.
  @param(ATimestamps  Prefix each line with [start --> end].) }
function WhisperSegmentsToText(const ASegments: TWhisperSegmentArray; ATimestamps: Boolean = False): string;

{ The segments as SubRip subtitles (.srt). }
function WhisperSegmentsToSrt(const ASegments: TWhisperSegmentArray): string;

{ The segments as WebVTT subtitles (.vtt). }
function WhisperSegmentsToVtt(const ASegments: TWhisperSegmentArray): string;

{ Writes AText to AFileName as UTF-8 without a byte order mark (what
  Audacity labels, JSON and subtitle files expect), replacing the file.
  @raises(EFCreateError / EStreamError when the file cannot be written.) }
procedure WhisperSaveTextFile(const AFileName, AText: string);

{ Reads a UTF-8 text file (a byte order mark is skipped), e.g. a Project
  Gutenberg plain-text book for @code(WhisperSplitText).
  @raises(EFOpenError / EStreamError when the file cannot be read.) }
function WhisperLoadTextFile(const AFileName: string): string;

{ Appends APart (a run over a piece of a longer recording, e.g. one
  chapter) to ATarget, moving its times by AOffsetSeconds: segment, token
  and word times, segment indexes and the words' segment numbers continue
  ATarget's. AudioSeconds and ElapsedMs add up; the language, word timing
  and result code are taken from the first part, and a failed or cancelled
  part marks the whole. }
procedure WhisperAppendTranscription(var ATarget: TWhisperTranscription;
  const APart: TWhisperTranscription; AOffsetSeconds: Double);

type
  { What @link(WhisperCleanTranscription) took out. }
  TWhisperCleanStats = record
    { Segments wholly inside a phrase repeated three or more times in a row
      (the decoder looping). }
    Loops: Integer;
    { Segments made only of words of the initial prompt (a carried prompt
      given back where the decoder heard nothing it could use). }
    PromptEchoes: Integer;
    { Words longer than @code(WHISPER_MAX_WORD_SECONDS), cut to one
      second: DTW stretches the last word it has over speech the decoder
      skipped. }
    LongWords: Integer;
  end;

const
  { A word longer than this (seconds) covers speech the decoder skipped. }
  WHISPER_MAX_WORD_SECONDS = 4;

{ Takes out of AResult what is not speech that was heard: segments wholly
  inside a loop (a phrase of two or more words three or more times in a
  row, nine or more words in all, across segments) and segments of nothing
  but words of APrompt (the initial prompt, when one is carried), three or
  more of them or stretched over 3 s; cuts words longer than
  WHISPER_MAX_WORD_SECONDS to one second. Segments are renumbered and,
  with DTW times (AResult.WordTiming = wwtDtw), span their words again.
  What is taken out leaves a gap that @code(TWhisperRun.FillGaps)
  transcribes again. }
function WhisperCleanTranscription(var AResult: TWhisperTranscription;
  const APrompt: string): TWhisperCleanStats;

{ Puts APart (a run over a stretch of the same recording, e.g. a gap run
  again) into ATarget in time order, its times moved by AOffsetSeconds:
  its segments go before the first segment of ATarget that starts at or
  after APart's first segment, its words likewise; segment indexes and the
  words' segment numbers are renumbered. Nothing else of ATarget changes. }
procedure WhisperInsertTranscription(var ATarget: TWhisperTranscription;
  const APart: TWhisperTranscription; AOffsetSeconds: Double);

implementation

uses
  Math;

{ C callbacks: user_data is the TWhisperRun. They must not let an exception
  escape into the library. }

procedure NewSegmentTrampoline(ctx: PWhisperContext; state: PWhisperState; n_new: Int32;
  user_data: Pointer); cdecl;
begin
  try
    TWhisperRun(user_data).CollectNew(ctx);
  except
    on E: Exception do
      TWhisperRun(user_data).HandlerFailed(E);
  end;
end;

procedure ProgressTrampoline(ctx: PWhisperContext; state: PWhisperState; progress: Int32;
  user_data: Pointer); cdecl;
begin
  try
    TWhisperRun(user_data).DoProgress(progress);
  except
    on E: Exception do
      TWhisperRun(user_data).HandlerFailed(E);
  end;
end;

function EncoderBeginTrampoline(ctx: PWhisperContext; state: PWhisperState;
  user_data: Pointer): Boolean; cdecl;
begin
  // With DTW, whisper.cpp 1.9.5 reports the segments of the first window
  // only (its callback loop runs "seg < n_segments" from the total minus
  // n_segments). Every window's segments - DTW times included - are final
  // when the next window starts, so they are collected here as well.
  try
    TWhisperRun(user_data).CollectNew(ctx);
  except
    on E: Exception do
      TWhisperRun(user_data).HandlerFailed(E);
  end;
  Result := not TWhisperRun(user_data).FCancel;
end;

function AbortTrampoline(data: Pointer): Boolean; cdecl;
begin
  Result := TWhisperRun(data).FCancel;
end;

function WhisperResultText(ACode: Integer): string;
begin
  case ACode of
    0: Result := 'success';
    -1: Result := 'voice activity detection failed (VAD model?)';
    -2: Result := 'failed to compute the log mel spectrogram';
    -3: Result := 'language detection failed or was aborted';
    -4: Result := 'too many decoders requested (BestOf / BeamSize)';
    -5: Result := 'AudioContext is larger than the model allows';
    -6: Result := 'encoder failed or was aborted';
    -7: Result := 'failed to allocate the KV cache';
    -8: Result := 'decoder failed or was aborted';
  else
    Result := Format('whisper_full error %d', [ACode]);
  end;
end;

function WhisperSegmentsToText(const ASegments: TWhisperSegmentArray; ATimestamps: Boolean): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(ASegments) do
    begin
      if ATimestamps then
        SB.Append(Format('[%s --> %s] ', [WhisperTimeToStr(ASegments[I].T0),
          WhisperTimeToStr(ASegments[I].T1)]));
      SB.Append(Trim(ASegments[I].Text));
      SB.Append(sLineBreak);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function WhisperSegmentsToSrt(const ASegments: TWhisperSegmentArray): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(ASegments) do
    begin
      SB.Append(IntToStr(I + 1)).Append(sLineBreak);
      SB.Append(WhisperTimeToStr(ASegments[I].T0, True)).Append(' --> ')
        .Append(WhisperTimeToStr(ASegments[I].T1, True)).Append(sLineBreak);
      SB.Append(Trim(ASegments[I].Text)).Append(sLineBreak).Append(sLineBreak);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function WhisperSegmentsToVtt(const ASegments: TWhisperSegmentArray): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('WEBVTT').Append(sLineBreak).Append(sLineBreak);
    for I := 0 to High(ASegments) do
    begin
      SB.Append(WhisperTimeToStr(ASegments[I].T0)).Append(' --> ')
        .Append(WhisperTimeToStr(ASegments[I].T1)).Append(sLineBreak);
      SB.Append(Trim(ASegments[I].Text)).Append(sLineBreak).Append(sLineBreak);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure WhisperSaveTextFile(const AFileName, AText: string);
var
  S: TFileStream;
  U: UTF8String;
begin
  U := UTF8String(AText);
  S := TFileStream.Create(AFileName, fmCreate);
  try
    if U <> '' then
      S.WriteBuffer(PAnsiChar(U)^, Length(U));
  finally
    S.Free;
  end;
end;

procedure WhisperAppendTranscription(var ATarget: TWhisperTranscription;
  const APart: TWhisperTranscription; AOffsetSeconds: Double);
var
  Ofs: Int64;
  NS, NW, I, J: Integer;
  First: Boolean;
begin
  Ofs := Round(AOffsetSeconds * 100);   // 10 ms units
  First := (Length(ATarget.Segments) = 0) and (Length(ATarget.Words) = 0) and
    (ATarget.LanguageCode = '');
  NS := Length(ATarget.Segments);
  SetLength(ATarget.Segments, NS + Length(APart.Segments));
  for I := 0 to High(APart.Segments) do
  begin
    ATarget.Segments[NS + I] := APart.Segments[I];
    ATarget.Segments[NS + I].Tokens := Copy(APart.Segments[I].Tokens);
    with ATarget.Segments[NS + I] do
    begin
      Index := NS + I;
      Inc(T0, Ofs);
      Inc(T1, Ofs);
      for J := 0 to High(Tokens) do
      begin
        if Tokens[J].T0 >= 0 then
          Inc(Tokens[J].T0, Ofs);
        if Tokens[J].T1 >= 0 then
          Inc(Tokens[J].T1, Ofs);
        if Tokens[J].TDtw >= 0 then
          Inc(Tokens[J].TDtw, Ofs);
      end;
    end;
  end;
  NW := Length(ATarget.Words);
  SetLength(ATarget.Words, NW + Length(APart.Words));
  for I := 0 to High(APart.Words) do
  begin
    ATarget.Words[NW + I] := APart.Words[I];
    Inc(ATarget.Words[NW + I].T0, Ofs);
    Inc(ATarget.Words[NW + I].T1, Ofs);
    Inc(ATarget.Words[NW + I].Segment, NS);
  end;
  if First then
  begin
    ATarget.WordTiming := APart.WordTiming;
    ATarget.LanguageCode := APart.LanguageCode;
    ATarget.LanguageName := APart.LanguageName;
    ATarget.ResultCode := APart.ResultCode;
  end
  else if (ATarget.ResultCode = 0) and (APart.ResultCode <> 0) then
    ATarget.ResultCode := APart.ResultCode;
  if APart.Cancelled then
    ATarget.Cancelled := True;
  if (ATarget.ErrorMessage = '') and (APart.ErrorMessage <> '') then
    ATarget.ErrorMessage := APart.ErrorMessage;
  ATarget.AudioSeconds := ATarget.AudioSeconds + APart.AudioSeconds;
  ATarget.ElapsedMs := ATarget.ElapsedMs + APart.ElapsedMs;
end;

{ Lower-case letters and digits of AText (non-ASCII kept as is). }
function PlainLetters(const AText: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(AText) do
  begin
    C := AText[I];
    if CharInSet(C, ['A'..'Z']) then
      Result := Result + Chr(Ord(C) + 32)
    else if CharInSet(C, ['a'..'z', '0'..'9']) or (Ord(C) > 127) then
      Result := Result + C;
  end;
end;

type
  { One flag per word. }
  TBooleanDynArray2 = array of Boolean;

{ Marks the words of AWords that belong to a loop: a phrase of two or more
  words repeated three or more times in a row, nine or more words in all
  (across segment boundaries: the decoder often gives each repeat its own
  segment). }
function LoopMask(const AWords: TWhisperWordArray): TBooleanDynArray2;
const
  MIN_REPEATS = 3;
  MIN_LOOP_WORDS = 9;
  MAX_PHRASE = 40;
var
  N, I, K, Reps, Len, Best: Integer;
  Norm: array of string;
  Same: Boolean;
begin
  Len := Length(AWords);
  Result := nil;
  SetLength(Result, Len);
  Norm := nil;
  SetLength(Norm, Len);
  for I := 0 to Len - 1 do
    Norm[I] := PlainLetters(AWords[I].Text);
  I := 0;
  while I < Len do
  begin
    Best := 0;
    for N := 2 to MAX_PHRASE do
    begin
      if I + N * MIN_REPEATS > Len then
        Break;
      Reps := 1;
      while I + (Reps + 1) * N <= Len do
      begin
        Same := True;
        for K := 0 to N - 1 do
          if Norm[I + Reps * N + K] <> Norm[I + K] then
          begin
            Same := False;
            Break;
          end;
        if not Same then
          Break;
        Inc(Reps);
      end;
      if (Reps >= MIN_REPEATS) and (Reps * N >= MIN_LOOP_WORDS) and (Reps * N > Best) then
        Best := Reps * N;
    end;
    if Best > 0 then
    begin
      for K := I to I + Best - 1 do
        Result[K] := True;
      Inc(I, Best);
    end
    else
      Inc(I);
  end;
end;

function WhisperCleanTranscription(var AResult: TWhisperTranscription;
  const APrompt: string): TWhisperCleanStats;
var
  PromptWords: TStringList;
  Drop: array of Boolean;
  First, Last: array of Integer;
  Map: array of Integer;
  Loop: TBooleanDynArray2;
  I, S, N, K: Integer;
  Echo: Boolean;
  Segs: TWhisperSegmentArray;
  Words: TWhisperWordArray;
  Word: string;
begin
  Result := Default(TWhisperCleanStats);
  N := Length(AResult.Segments);
  if N = 0 then
    Exit;
  // the words of each segment
  First := nil;
  Last := nil;
  SetLength(First, N);
  SetLength(Last, N);
  for S := 0 to N - 1 do
  begin
    First[S] := -1;
    Last[S] := -2;
  end;
  for I := 0 to High(AResult.Words) do
  begin
    S := AResult.Words[I].Segment;
    if (S < 0) or (S >= N) then
      Continue;
    if First[S] < 0 then
      First[S] := I;
    Last[S] := I;
  end;
  PromptWords := TStringList.Create;
  try
    PromptWords.Sorted := True;
    PromptWords.Duplicates := dupIgnore;
    Word := '';
    for I := 1 to Length(APrompt) + 1 do
      if (I <= Length(APrompt)) and not CharInSet(APrompt[I], [' ', ',', '.', ';', ':', '!', '?', '"']) then
        Word := Word + APrompt[I]
      else if Word <> '' then
      begin
        PromptWords.Add(PlainLetters(Word));
        Word := '';
      end;
    Loop := LoopMask(AResult.Words);
    Drop := nil;
    SetLength(Drop, N);
    for S := 0 to N - 1 do
    begin
      if First[S] < 0 then
        Continue;
      // a segment wholly inside a loop
      Echo := True;
      for I := First[S] to Last[S] do
        if not Loop[I] then
        begin
          Echo := False;
          Break;
        end;
      if Echo then
      begin
        Drop[S] := True;
        Inc(Result.Loops);
        Continue;
      end;
      if PromptWords.Count = 0 then
        Continue;
      // a segment of nothing but prompt words, three or more of them or
      // stretched over 3 s ('Mudge!' alone is speech)
      Echo := (Last[S] - First[S] + 1 >= 3) or
        (AResult.Words[Last[S]].T1 - AResult.Words[First[S]].T0 >= 3 * WHISPER_TICKS_PER_SECOND);
      if Echo then
        for I := First[S] to Last[S] do
          if PromptWords.IndexOf(PlainLetters(AResult.Words[I].Text)) < 0 then
          begin
            Echo := False;
            Break;
          end;
      if Echo then
      begin
        Drop[S] := True;
        Inc(Result.PromptEchoes);
      end;
    end;
  finally
    PromptWords.Free;
  end;
  // rebuild without the dropped segments
  Map := nil;
  SetLength(Map, N);
  Segs := nil;
  K := 0;
  for S := 0 to N - 1 do
    if Drop[S] then
      Map[S] := -1
    else
    begin
      SetLength(Segs, K + 1);
      Segs[K] := AResult.Segments[S];
      Segs[K].Index := K;
      Map[S] := K;
      Inc(K);
    end;
  Words := nil;
  K := 0;
  SetLength(Words, Length(AResult.Words));
  for I := 0 to High(AResult.Words) do
  begin
    S := AResult.Words[I].Segment;
    if (S >= 0) and (S < N) and (Map[S] < 0) then
      Continue;
    Words[K] := AResult.Words[I];
    if (S >= 0) and (S < N) then
      Words[K].Segment := Map[S];
    if Words[K].T1 - Words[K].T0 > WHISPER_MAX_WORD_SECONDS * WHISPER_TICKS_PER_SECOND then
    begin
      Words[K].T1 := Words[K].T0 + WHISPER_TICKS_PER_SECOND;
      Inc(Result.LongWords);
    end;
    Inc(K);
  end;
  SetLength(Words, K);
  AResult.Segments := Segs;
  AResult.Words := Words;
  if AResult.WordTiming = wwtDtw then
  begin
    S := -1;
    for I := 0 to High(AResult.Words) do
    begin
      K := AResult.Words[I].Segment;
      if (K < 0) or (K > High(AResult.Segments)) then
        Continue;
      if K <> S then
      begin
        AResult.Segments[K].T0 := AResult.Words[I].T0;
        S := K;
      end;
      AResult.Segments[K].T1 := AResult.Words[I].T1;
    end;
  end;
end;

procedure WhisperInsertTranscription(var ATarget: TWhisperTranscription;
  const APart: TWhisperTranscription; AOffsetSeconds: Double);
var
  Tmp: TWhisperTranscription;
  Ofs, Start: Int64;
  PS, PW, NS, NW, I: Integer;
  Segs: TWhisperSegmentArray;
  Words: TWhisperWordArray;
begin
  if Length(APart.Segments) = 0 then
    Exit;
  // the part on its own, times moved (append to an empty one)
  Tmp := Default(TWhisperTranscription);
  WhisperAppendTranscription(Tmp, APart, AOffsetSeconds);
  Ofs := Tmp.Segments[0].T0;
  PS := 0;
  while (PS <= High(ATarget.Segments)) and (ATarget.Segments[PS].T0 < Ofs) do
    Inc(PS);
  if Length(Tmp.Words) > 0 then
    Start := Tmp.Words[0].T0
  else
    Start := Ofs;
  PW := 0;
  while (PW <= High(ATarget.Words)) and (ATarget.Words[PW].T0 < Start) do
    Inc(PW);
  NS := Length(Tmp.Segments);
  NW := Length(Tmp.Words);
  Segs := nil;
  SetLength(Segs, Length(ATarget.Segments) + NS);
  for I := 0 to PS - 1 do
    Segs[I] := ATarget.Segments[I];
  for I := 0 to NS - 1 do
  begin
    Segs[PS + I] := Tmp.Segments[I];
    Segs[PS + I].Index := PS + I;
  end;
  for I := PS to High(ATarget.Segments) do
  begin
    Segs[I + NS] := ATarget.Segments[I];
    Segs[I + NS].Index := I + NS;
  end;
  Words := nil;
  SetLength(Words, Length(ATarget.Words) + NW);
  for I := 0 to PW - 1 do
    Words[I] := ATarget.Words[I];
  for I := 0 to NW - 1 do
  begin
    Words[PW + I] := Tmp.Words[I];
    Inc(Words[PW + I].Segment, PS);
  end;
  for I := PW to High(ATarget.Words) do
  begin
    Words[I + NW] := ATarget.Words[I];
    if Words[I + NW].Segment >= PS then
      Inc(Words[I + NW].Segment, NS);
  end;
  ATarget.Segments := Segs;
  ATarget.Words := Words;
end;

function WhisperLoadTextFile(const AFileName: string): string;
const
  BOM_SIZE = 3;
var
  S: TFileStream;
  U: UTF8String;
  N: Integer;
begin
  S := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    N := S.Size;
    SetLength(U, N);
    if N > 0 then
      S.ReadBuffer(PAnsiChar(U)^, N);
  finally
    S.Free;
  end;
  if (Length(U) >= BOM_SIZE) and (Ord(U[1]) = $EF) and (Ord(U[2]) = $BB) and (Ord(U[3]) = $BF) then
    Delete(U, 1, BOM_SIZE);
  Result := string(U);
end;

{ TWhisperModel }

constructor TWhisperModel.Create(const AFileName: string; const AParams: TWhisperContextParams);
begin
  inherited Create;
  Init;
  FFileName := AFileName;
  FContextParams := AParams;
  if not FileExists(AFileName) then
    raise EWhisperError.CreateFmt('Model file not found: %s', [AFileName]);
  FCtx := FLib.InitFromFile(AFileName, AParams);
  if FCtx = nil then
    raise EWhisperError.CreateFmt('whisper.cpp could not load the model %s (see the log)', [AFileName]);
end;

constructor TWhisperModel.Create(const AFileName: string; AUseGPU: Boolean);
var
  P: TWhisperContextParams;
begin
  P := TWhisperLib.Instance.DefaultContextParams;
  P.use_gpu := AUseGPU;
  Create(AFileName, P);
end;

constructor TWhisperModel.CreateFromBuffer(ABuffer: Pointer; ASize: NativeUInt;
  const AParams: TWhisperContextParams);
begin
  inherited Create;
  Init;
  FContextParams := AParams;
  FCtx := FLib.InitFromBuffer(ABuffer, ASize, AParams);
  if FCtx = nil then
    raise EWhisperError.CreateFmt('whisper.cpp could not load the model from a %d-byte buffer (see the log)',
      [Int64(ASize)]);
end;

procedure TWhisperModel.Init;
begin
  FLib := TWhisperLib.Instance;
  FLock := TCriticalSection.Create;
  FLib.ModelCreated;
  FCounted := True;
end;

destructor TWhisperModel.Destroy;
begin
  if FCtx <> nil then
  begin
    FLock.Acquire;          // a run in progress finishes first
    try
      FLib.Flat.whisper_free(FCtx);
      FCtx := nil;
    finally
      FLock.Release;
    end;
  end;
  if FCounted then
    FLib.ModelFreed;
  FreeAndNil(FLock);
  inherited;
end;

procedure TWhisperModel.Lock;
begin
  FLock.Acquire;
end;

procedure TWhisperModel.Unlock;
begin
  FLock.Release;
end;

function TWhisperModel.IsMultilingual: Boolean;
begin
  Result := Assigned(FLib.Flat.whisper_is_multilingual) and (FLib.Flat.whisper_is_multilingual(FCtx) <> 0);
end;

function TWhisperModel.ModelType: string;
begin
  if Assigned(FLib.Flat.whisper_model_type_readable) then
    Result := WhisperStr(FLib.Flat.whisper_model_type_readable(FCtx))
  else
    Result := '';
end;

function TWhisperModel.VocabSize: Integer;
begin
  if Assigned(FLib.Flat.whisper_n_vocab) then
    Result := FLib.Flat.whisper_n_vocab(FCtx)
  else
    Result := 0;
end;

function TWhisperModel.Description: string;
const
  LANGS: array[Boolean] of string = ('English only', 'multilingual');
begin
  Result := Format('%s, %s, vocabulary %d, GPU %s', [ModelType, LANGS[IsMultilingual], VocabSize,
    BoolToStr(FContextParams.use_gpu, True)]);
  if DtwEnabled then
    Result := Result + Format(', DTW word timings (alignment heads %s, flash attention %s)',
      [WhisperDtwPresetName(FContextParams.dtw_aheads_preset), BoolToStr(FContextParams.flash_attn, True)]);
end;

function TWhisperModel.DtwEnabled: Boolean;
begin
  Result := FContextParams.dtw_token_timestamps and (FContextParams.dtw_aheads_preset <> wahNone) and
    not FContextParams.flash_attn;
end;

{ TWhisperParams }

constructor TWhisperParams.Create(AStrategy: TWhisperSamplingStrategy);
const
  DEFAULT_CANDIDATES = 5;   // whisper.cpp's default best_of / beam_size
begin
  inherited Create;
  FRaw := TWhisperLib.Instance.DefaultFullParams(AStrategy);
  FRaw.print_progress := False;
  FRaw.print_realtime := False;
  FRaw.print_timestamps := False;
  FRaw.print_special := False;
  FRaw.greedy_best_of := DEFAULT_CANDIDATES;
  FRaw.beam_search_beam_size := DEFAULT_CANDIDATES;
  FLanguage := WHISPER_LANGUAGE_AUTO;
end;

procedure TWhisperParams.Assign(ASource: TWhisperParams);
begin
  FRaw := ASource.FRaw;
  FLanguage := ASource.FLanguage;
  FInitialPrompt := ASource.FInitialPrompt;
  FSuppressRegex := ASource.FSuppressRegex;
  FVadModelFile := ASource.FVadModelFile;
end;

function TWhisperParams.GetRaw: PWhisperFullParams;
begin
  Result := @FRaw;
end;

function TWhisperParams.Build(AMultilingual: Boolean): TWhisperFullParams;

  function Ptr(const S: UTF8String): PAnsiChar;
  begin
    if S = '' then
      Result := nil
    else
      Result := PAnsiChar(S);
  end;

begin
  FLanguageU8 := UTF8String(Trim(FLanguage));
  if (not AMultilingual) and ((FLanguageU8 = '') or SameText(string(FLanguageU8), WHISPER_LANGUAGE_AUTO)) then
    FLanguageU8 := 'en';
  FInitialPromptU8 := UTF8String(FInitialPrompt);
  FSuppressRegexU8 := UTF8String(FSuppressRegex);
  FVadModelFileU8 := UTF8String(FVadModelFile);
  Result := FRaw;
  Result.language := Ptr(FLanguageU8);
  Result.initial_prompt := Ptr(FInitialPromptU8);
  Result.suppress_regex := Ptr(FSuppressRegexU8);
  Result.vad_model_path := Ptr(FVadModelFileU8);
end;

{ TWhisperRun }

constructor TWhisperRun.Create(AModel: TWhisperModel; AParams: TWhisperParams);
begin
  inherited Create;
  if (AModel = nil) or (AParams = nil) then
    raise EWhisperError.Create('TWhisperRun needs a model and params');
  FModel := AModel;
  FParams := AParams;
end;

function TWhisperRun.FillGaps(const ASamples: TWhisperSamples; var AResult: TWhisperTranscription;
  AMinGapSeconds: Double; AMinLevel: Single; AMinVoiced: Single): TWhisperGapArray;
const
  { Samples per level frame (20 ms). }
  FRAME = WHISPER_SAMPLE_RATE div 50;
  { Shortest stretch run again, samples (whisper.cpp pads to 30 s anyway). }
  MIN_SAMPLES = WHISPER_SAMPLE_RATE div 2;
  { Rounds: a stretch the pass only partly filled leaves a shorter one,
    which the next round tries again (whisper.cpp can skip the start of
    the stretch, too). }
  MAX_ROUNDS = 3;
  { Temperature of the retry of a stretch that gave nothing usable. }
  RETRY_TEMPERATURE = 0.2;
var
  Edges: array of Int64;   // pairs: end of an item, start of the next
  N, I, K, F, Frames, Loud, S0, S1, G, Round_, Added: Integer;
  Total: Int64;
  Sum: Double;
  Sub: TWhisperSamples;
  Part, Kept: TWhisperTranscription;
  SaveSeg: TWhisperSegmentEvent;
  SaveProg: TWhisperProgressEvent;
  Prompt, SavePrompt: string;
  SaveCarry: Boolean;
  SaveTemp: Single;
  Gap: TWhisperGap;
  UseWords, Tried: Boolean;

  // Runs ASub; APart gets the raw result, the result is what is kept: no
  // loops, no prompt echoes, no segment that is only the prompt.
  function RunStretch(const ASub: TWhisperSamples; out APart: TWhisperTranscription): TWhisperTranscription;
  var
    J, M: Integer;
    Txt: string;
  begin
    APart := Execute(ASub);
    WhisperCleanTranscription(APart, FParams.InitialPrompt);
    Result := APart;
    Result.Segments := nil;
    Result.Words := nil;
    for J := 0 to High(APart.Segments) do
    begin
      Txt := PlainLetters(APart.Segments[J].Text);
      if (Txt = '') or ((Prompt <> '') and (Pos(Txt, Prompt) > 0)) then
        Continue;
      SetLength(Result.Segments, Length(Result.Segments) + 1);
      Result.Segments[High(Result.Segments)] := APart.Segments[J];
      for M := 0 to High(APart.Words) do
        if APart.Words[M].Segment = J then
        begin
          SetLength(Result.Words, Length(Result.Words) + 1);
          Result.Words[High(Result.Words)] := APart.Words[M];
          Result.Words[High(Result.Words)].Segment := High(Result.Segments);
        end;
    end;
  end;

begin
  Result := nil;
  Total := Round(Length(ASamples) / WHISPER_SAMPLE_RATE * WHISPER_TICKS_PER_SECOND);
  Prompt := PlainLetters(FParams.InitialPrompt);
  SaveSeg := FOnSegment;
  SaveProg := FOnProgress;
  FOnSegment := nil;
  FOnProgress := nil;
  try
    for Round_ := 1 to MAX_ROUNDS do
    begin
      UseWords := Length(AResult.Words) > 0;
      if UseWords then
        N := Length(AResult.Words)
      else
        N := Length(AResult.Segments);
      // stretches: before the first item, between items, after the last
      Edges := nil;
      SetLength(Edges, 2 * (N + 1));
      Edges[0] := 0;
      for I := 0 to N - 1 do
        if UseWords then
        begin
          Edges[2 * I + 1] := AResult.Words[I].T0;
          Edges[2 * I + 2] := AResult.Words[I].T1;
        end
        else
        begin
          Edges[2 * I + 1] := AResult.Segments[I].T0;
          Edges[2 * I + 2] := AResult.Segments[I].T1;
        end;
      Edges[2 * N + 1] := Total;
      Added := 0;
      for G := 0 to N do
      begin
        Gap := Default(TWhisperGap);
        Gap.T0 := Edges[2 * G];
        Gap.T1 := Edges[2 * G + 1];
        if (Gap.T1 - Gap.T0) < Round(AMinGapSeconds * WHISPER_TICKS_PER_SECOND) then
          Continue;
        // each stretch once
        Tried := False;
        for K := 0 to High(Result) do
          if (Result[K].T0 = Gap.T0) and (Result[K].T1 = Gap.T1) then
          begin
            Tried := True;
            Break;
          end;
        if Tried then
          Continue;
        S0 := Round(Gap.T0 * WHISPER_SAMPLE_RATE / WHISPER_TICKS_PER_SECOND);
        S1 := Round(Gap.T1 * WHISPER_SAMPLE_RATE / WHISPER_TICKS_PER_SECOND);
        if S0 < 0 then
          S0 := 0;
        if S1 > Length(ASamples) then
          S1 := Length(ASamples);
        if S1 - S0 < MIN_SAMPLES then
          Continue;
        // sound level
        Frames := (S1 - S0) div FRAME;
        Loud := 0;
        for F := 0 to Frames - 1 do
        begin
          Sum := 0;
          for K := S0 + F * FRAME to S0 + (F + 1) * FRAME - 1 do
            Sum := Sum + Sqr(ASamples[K]);
          if Sqrt(Sum / FRAME) >= AMinLevel then
            Inc(Loud);
        end;
        if Frames > 0 then
          Gap.Voiced := Loud / Frames;
        if Gap.Voiced >= AMinVoiced then
        begin
          Gap.Transcribed := True;
          Sub := Copy(ASamples, S0, S1 - S0);
          Kept := RunStretch(Sub, Part);
          if (Length(Kept.Words) = 0) and (Part.ResultCode = 0) and not Part.Cancelled and
            ((FParams.InitialPrompt <> '') or (FParams.Temperature < RETRY_TEMPERATURE)) then
          begin
            // the decoder looped or gave the prompt back on this stretch
            // again: once more without the prompt and a little randomness
            Gap.Retried := True;
            SavePrompt := FParams.InitialPrompt;
            SaveCarry := FParams.CarryInitialPrompt;
            SaveTemp := FParams.Temperature;
            try
              FParams.InitialPrompt := '';
              FParams.CarryInitialPrompt := False;
              if FParams.Temperature < RETRY_TEMPERATURE then
                FParams.Temperature := RETRY_TEMPERATURE;
              AResult.ElapsedMs := AResult.ElapsedMs + Part.ElapsedMs;
              Kept := RunStretch(Sub, Part);
            finally
              FParams.InitialPrompt := SavePrompt;
              FParams.CarryInitialPrompt := SaveCarry;
              FParams.Temperature := SaveTemp;
            end;
          end;
          Gap.Words := Length(Kept.Words);
          if (Part.ResultCode = 0) and not Part.Cancelled and (Length(Kept.Segments) > 0) then
          begin
            WhisperInsertTranscription(AResult, Kept, S0 / WHISPER_SAMPLE_RATE);
            Inc(Added, Gap.Words);
          end
          else
            Gap.Words := 0;
          AResult.ElapsedMs := AResult.ElapsedMs + Part.ElapsedMs;
        end;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Gap;
        if FCancel then
          Exit;
      end;
      if Added = 0 then
        Break;
    end;
  finally
    FOnSegment := SaveSeg;
    FOnProgress := SaveProg;
  end;
end;

procedure TWhisperRun.Cancel;
begin
  FCancel := True;
end;

procedure TWhisperRun.HandlerFailed(E: Exception);
begin
  if FHandlerError = '' then
    FHandlerError := E.ClassName + ': ' + E.Message;
  FCancel := True;
end;

procedure TWhisperRun.DoProgress(AProgress: Integer);
begin
  // whisper.cpp can report more than 100 when its last window runs past the
  // end of the audio (seen: 272 for an 11 s file).
  if AProgress > 100 then
    AProgress := 100
  else if AProgress < 0 then
    AProgress := 0;
  if AProgress = FLastProgress then
    Exit;
  FLastProgress := AProgress;
  if Assigned(FOnProgress) then
    FOnProgress(Self, AProgress);
end;

function TWhisperRun.ReadSegment(ACtx: PWhisperContext; AIndex: Integer): TWhisperSegment;
var
  F: PWhisperFlat;
  N, I: Integer;
  TD: TWhisperTokenData;
begin
  F := FModel.Lib.Flat;
  Result.Index := AIndex;
  Result.T0 := F.whisper_full_get_segment_t0(ACtx, AIndex);
  Result.T1 := F.whisper_full_get_segment_t1(ACtx, AIndex);
  Result.Text := WhisperStr(F.whisper_full_get_segment_text(ACtx, AIndex));
  if Assigned(F.whisper_full_get_segment_no_speech_prob) then
    Result.NoSpeechProb := F.whisper_full_get_segment_no_speech_prob(ACtx, AIndex)
  else
    Result.NoSpeechProb := 0;
  Result.SpeakerTurnNext := Assigned(F.whisper_full_get_segment_speaker_turn_next) and
    F.whisper_full_get_segment_speaker_turn_next(ACtx, AIndex);
  Result.Tokens := nil;
  if not (FIncludeTokens or FIncludeWords) or not Assigned(F.whisper_full_n_tokens) or
    not Assigned(F.whisper_full_get_token_text) or not Assigned(F.whisper_full_get_token_data) then
    Exit;
  N := F.whisper_full_n_tokens(ACtx, AIndex);
  SetLength(Result.Tokens, N);
  for I := 0 to N - 1 do
  begin
    TD := FModel.Lib.GetTokenData(ACtx, nil, AIndex, I);
    Result.Tokens[I].Id := TD.id;
    Result.Tokens[I].Utf8 := UTF8String(F.whisper_full_get_token_text(ACtx, AIndex, I));
    Result.Tokens[I].Text := WhisperStr(PAnsiChar(Result.Tokens[I].Utf8));
    Result.Tokens[I].Probability := TD.p;
    Result.Tokens[I].T0 := TD.t0;
    Result.Tokens[I].T1 := TD.t1;
    Result.Tokens[I].TDtw := TD.t_dtw;
    Result.Tokens[I].Special := TD.id >= FEot;
  end;
end;

procedure TWhisperRun.CollectNew(ACtx: PWhisperContext);
var
  N: Integer;
begin
  N := FModel.Lib.Flat.whisper_full_n_segments(ACtx);
  while FCount < N do
  begin
    if FCount >= Length(FSegments) then
      SetLength(FSegments, FCount + 64);
    FSegments[FCount] := ReadSegment(ACtx, FCount);
    Inc(FCount);
    if Assigned(FOnSegment) then
      FOnSegment(Self, FSegments[FCount - 1]);
  end;
end;

function TWhisperRun.Execute(const ASamples: TWhisperSamples): TWhisperTranscription;
var
  P: TWhisperFullParams;
  Ctx: PWhisperContext;
  F: PWhisperFlat;
  Start: TDateTime;
  LangId: Integer;
  Timing: TWhisperWordTiming;
  PromptTokens: Int32;
  I, K, SegFirst: Integer;
  PromptBuf: array of TWhisperToken;
begin
  if Length(ASamples) = 0 then
    raise EWhisperError.Create('No audio to transcribe');
  if FIncludeWords and FParams.Vad then
    raise EWhisperError.Create('Word timings do not work with Vad: whisper.cpp maps only segment times, ' +
      'not token times, back to the original audio');
  if FModel.DtwEnabled and (FParams.AudioContext <> 0) then
    raise EWhisperError.CreateFmt('AudioContext must be 0 for a model loaded with DTW (whisper.cpp asserts ' +
      'that DTW sees the whole %d s window and would end the process)', [WHISPER_CHUNK_SIZE]);
  if not FIncludeWords then
    Timing := wwtNone
  else if FModel.DtwEnabled then
    Timing := wwtDtw
  else
    Timing := wwtTokenTimestamps;
  FModel.Lock;
  try
    FRunning := True;
    FCancel := False;
    FHandlerError := '';
    FSegments := nil;
    FCount := 0;
    FLastProgress := -1;
    Ctx := FModel.Handle;
    F := FModel.Lib.Flat;
    if Assigned(F.whisper_token_eot) then
      FEot := F.whisper_token_eot(Ctx)
    else if Assigned(F.whisper_token_beg) then
      FEot := F.whisper_token_beg(Ctx)
    else
      FEot := High(TWhisperToken);
    P := FParams.Build(FModel.IsMultilingual);
    if (P.n_max_text_ctx = 0) and P.carry_initial_prompt and (P.initial_prompt <> nil) then
    begin
      // whisper.cpp uses no prompt at all when n_max_text_ctx is 0, so a
      // carried prompt gets exactly its own room: the prompt plus the
      // previous-text marker, none for the text before.
      // A buffer as long as the prompt's bytes always holds its tokens
      // (whisper_token_count would log an error for its own probe).
      SetLength(PromptBuf, Length(UTF8String(FParams.InitialPrompt)) + 1);
      if Assigned(F.whisper_tokenize) then
        PromptTokens := F.whisper_tokenize(Ctx, P.initial_prompt, @PromptBuf[0], Length(PromptBuf))
      else
        PromptTokens := 0;
      if PromptTokens > 0 then
        P.n_max_text_ctx := PromptTokens + 1;
    end;
    if Timing = wwtTokenTimestamps then
      P.token_timestamps := True;
    P.new_segment_callback := NewSegmentTrampoline;
    P.new_segment_callback_user_data := Self;
    P.progress_callback := ProgressTrampoline;
    P.progress_callback_user_data := Self;
    P.encoder_begin_callback := EncoderBeginTrampoline;
    P.encoder_begin_callback_user_data := Self;
    P.abort_callback := AbortTrampoline;
    P.abort_callback_user_data := Self;

    Start := Now;
    Result.ResultCode := FModel.Lib.Full(Ctx, nil, P, @ASamples[0], Length(ASamples));
    Result.ElapsedMs := MilliSecondsBetween(Now, Start);
    try
      CollectNew(Ctx);       // anything the callback did not report
    except
      on E: Exception do
        HandlerFailed(E);
    end;
    if (Result.ResultCode = 0) and not FCancel then
      DoProgress(100);
    SetLength(FSegments, FCount);
    Result.Segments := FSegments;
    Result.Cancelled := FCancel;
    Result.AudioSeconds := Length(ASamples) / WHISPER_SAMPLE_RATE;
    LangId := -1;
    if Assigned(F.whisper_full_lang_id) then
      LangId := F.whisper_full_lang_id(Ctx);
    if LangId >= 0 then
    begin
      Result.LanguageCode := FModel.Lib.LanguageCode(LangId);
      Result.LanguageName := FModel.Lib.LanguageName(LangId);
    end
    else
    begin
      Result.LanguageCode := '';
      Result.LanguageName := '';
    end;
    if (Result.ResultCode <> 0) and not FCancel then
      Result.ErrorMessage := WhisperResultText(Result.ResultCode)
    else
      Result.ErrorMessage := '';
    Result.Words := nil;
    Result.WordTiming := Timing;
    if Timing <> wwtNone then
      Result.Words := WhisperBuildWords(Result.Segments, Result.LanguageCode, Timing);
    // DTW word times are better than whisper.cpp's segment time stamps,
    // which can be far out where it skipped speech: segments span their
    // words.
    if Timing = wwtDtw then
    begin
      SegFirst := -1;
      for I := 0 to High(Result.Words) do
      begin
        K := Result.Words[I].Segment;
        if (K < 0) or (K > High(Result.Segments)) then
          Continue;
        if K <> SegFirst then
        begin
          Result.Segments[K].T0 := Result.Words[I].T0;
          SegFirst := K;
        end;
        Result.Segments[K].T1 := Result.Words[I].T1;
      end;
    end;
  finally
    FRunning := False;
    FModel.Unlock;
  end;
  if FHandlerError <> '' then
    raise EWhisperError.Create('An event handler raised during the transcription: ' + FHandlerError);
end;

{ TWhisperBenchmark }

constructor TWhisperBenchmark.Create(const AModelFile: string; const ASamples: TWhisperSamples);
const
  DEFAULT_MAX_SECONDS = WHISPER_CHUNK_SIZE;
  DEFAULT_WARMUP_SECONDS = 5;
begin
  inherited Create;
  if Length(ASamples) = 0 then
    raise EWhisperError.Create('A benchmark needs audio');
  FModelFiles := TStringList.Create;
  FModelFiles.Add(AModelFile);
  FSamples := ASamples;
  FContextParams := TWhisperLib.Instance.DefaultContextParams;
  FMaxSeconds := DEFAULT_MAX_SECONDS;
  FWarmupSeconds := DEFAULT_WARMUP_SECONDS;
  FRuns := 1;
end;

destructor TWhisperBenchmark.Destroy;
begin
  FreeAndNil(FModelFiles);
  inherited;
end;

procedure TWhisperBenchmark.Cancel;
var
  R: TWhisperRun;
begin
  FCancel := True;
  R := FCurrentRun;
  if R <> nil then
    R.Cancel;
end;

function TWhisperBenchmark.Slice(ASeconds: Double): TWhisperSamples;
var
  N: Integer;
begin
  if ASeconds <= 0 then
    N := Length(FSamples)
  else
    N := Min(Length(FSamples), Max(1, Integer(Round(ASeconds * WHISPER_SAMPLE_RATE))));
  Result := Copy(FSamples, 0, N);
end;

class function TWhisperBenchmark.Best(const AResults: TWhisperBenchmarkArray;
  const AModelFile: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(AResults) do
    if AResults[I].Ok and ((AModelFile = '') or SameFileName(AResults[I].ModelFile, AModelFile)) and
      ((Result < 0) or (AResults[I].Speed > AResults[Result].Speed)) then
      Result := I;
end;

function TWhisperBenchmark.RunOne(const AModelFile: string;
  const ADevice: TWhisperDevice): TWhisperBenchmarkResult;
var
  CP: TWhisperContextParams;
  Model: TWhisperModel;
  P: TWhisperParams;
  R: TWhisperRun;
  T: TWhisperTranscription;
  Timed: TWhisperSamples;
  Start: TDateTime;
  Times: array of Int64;
  I, J: Integer;
  Tmp: Int64;
begin
  Result.ModelFile := AModelFile;
  Result.Device := ADevice;
  Result.Ok := False;
  Result.ErrorMessage := '';
  Result.LoadMs := 0;
  Result.WarmupMs := 0;
  Result.RunMs := 0;
  Result.Runs := 0;
  Result.Threads := 0;
  Result.AudioSeconds := 0;
  Result.Speed := 0;
  Result.Text := '';
  CP := FContextParams;
  // DTW alignment heads belong to a model: choose them for this one
  if CP.dtw_token_timestamps and (CP.dtw_aheads_preset <> wahCustom) and
    not WhisperEnableDtw(AModelFile, CP) then
    CP.dtw_token_timestamps := False;
  if not TWhisperLib.Instance.ContextParamsFor(ADevice.Name, CP) then
  begin
    Result.ErrorMessage := Format('Device %s cannot be selected for whisper.cpp', [ADevice.Name]);
    Exit;
  end;
  Model := nil;
  P := nil;
  R := nil;
  try
    try
      Start := Now;
      Model := TWhisperModel.Create(AModelFile, CP);
      Result.LoadMs := MilliSecondsBetween(Now, Start);
      P := TWhisperParams.Create;
      if FParams <> nil then
        P.Assign(FParams);
      if ADevice.DeviceType = wdtCPU then
      begin
        if FCpuThreads > 0 then
          P.Threads := FCpuThreads
        else
          P.Threads := TThread.ProcessorCount;
      end;
      Result.Threads := P.Threads;
      R := TWhisperRun.Create(Model, P);
      FCurrentRun := R;
      if FCancel then
        Exit;
      T := R.Execute(Slice(FWarmupSeconds));
      Result.WarmupMs := T.ElapsedMs;
      if T.ErrorMessage <> '' then
        raise EWhisperError.Create('Warm-up run failed: ' + T.ErrorMessage);
      if FCancel then
        Exit;
      Timed := Slice(FMaxSeconds);
      SetLength(Times, Max(1, FRuns));
      for I := 0 to High(Times) do
      begin
        T := R.Execute(Timed);
        if T.ErrorMessage <> '' then
          raise EWhisperError.Create('Timed run failed: ' + T.ErrorMessage);
        if T.Cancelled then
          Exit;
        Times[I] := T.ElapsedMs;
      end;
      // median (insertion sort: a handful of values)
      for I := 1 to High(Times) do
      begin
        Tmp := Times[I];
        J := I - 1;
        while (J >= 0) and (Times[J] > Tmp) do
        begin
          Times[J + 1] := Times[J];
          Dec(J);
        end;
        Times[J + 1] := Tmp;
      end;
      Result.RunMs := Times[High(Times) div 2];
      Result.Runs := Length(Times);
      Result.AudioSeconds := Length(Timed) / WHISPER_SAMPLE_RATE;
      Result.Speed := Result.AudioSeconds * 1000 / Max(Int64(1), Result.RunMs);
      Result.Text := Trim(WhisperSegmentsToText(T.Segments));
      Result.Ok := True;
    except
      on E: Exception do
        Result.ErrorMessage := E.Message;
    end;
  finally
    FCurrentRun := nil;
    R.Free;
    P.Free;
    Model.Free;
  end;
end;

function TWhisperBenchmark.Run(const ADevices: TWhisperDeviceArray): TWhisperBenchmarkArray;
var
  Devs: TWhisperDeviceArray;
  I, M, N: Integer;
begin
  Result := nil;
  FCancel := False;
  if Length(ADevices) = 0 then
    Devs := TWhisperLib.Instance.SelectableDevices
  else
    Devs := ADevices;
  SetLength(Result, Length(Devs) * FModelFiles.Count);
  N := 0;
  for M := 0 to FModelFiles.Count - 1 do
    for I := 0 to High(Devs) do
    begin
      if FCancel then
        Break;
      if Assigned(FOnStart) then
        FOnStart(Self, FModelFiles[M], Devs[I]);
      Result[N] := RunOne(FModelFiles[M], Devs[I]);
      if FCancel and not Result[N].Ok then
        Break;   // cancelled mid-run: not a result
      Inc(N);
      if Assigned(FOnResult) then
        FOnResult(Self, Result[N - 1]);
    end;
  SetLength(Result, N);
end;

end.
