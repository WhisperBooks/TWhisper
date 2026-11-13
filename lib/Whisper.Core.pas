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
  Whisper.Types, Whisper.API;

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
    { One line describing the model, for logs. }
    function Description: string;

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
    { Do not use earlier text as prompt. }
    property NoContext: Boolean read FRaw.no_context write FRaw.no_context;
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
    { Repeat the initial prompt in every window. }
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
      @raises(EWhisperError when ASamples is empty or an event handler raised.) }
    function Execute(const ASamples: TWhisperSamples): TWhisperTranscription;
    { Asks the run in progress to stop (any thread). It stops at the next
      check; the segments so far are kept and the result says Cancelled. }
    procedure Cancel;
    { @true while Execute runs. }
    property Running: Boolean read FRunning;
    { @true after Cancel (reset by Execute). }
    property Cancelled: Boolean read FCancel;
    { Fill TWhisperSegment.Tokens. }
    property IncludeTokens: Boolean read FIncludeTokens write FIncludeTokens;
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
      are set per device. Default: the library's defaults. }
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
  Beg: TWhisperToken;
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
  if not FIncludeTokens or not Assigned(F.whisper_full_n_tokens) or
    not Assigned(F.whisper_full_get_token_text) or not Assigned(F.whisper_full_get_token_data) then
    Exit;
  if Assigned(F.whisper_token_beg) then
    Beg := F.whisper_token_beg(ACtx)
  else
    Beg := High(TWhisperToken);
  N := F.whisper_full_n_tokens(ACtx, AIndex);
  SetLength(Result.Tokens, N);
  for I := 0 to N - 1 do
  begin
    TD := FModel.Lib.GetTokenData(ACtx, nil, AIndex, I);
    Result.Tokens[I].Id := TD.id;
    Result.Tokens[I].Text := WhisperStr(F.whisper_full_get_token_text(ACtx, AIndex, I));
    Result.Tokens[I].Probability := TD.p;
    Result.Tokens[I].T0 := TD.t0;
    Result.Tokens[I].T1 := TD.t1;
    Result.Tokens[I].TDtw := TD.t_dtw;
    Result.Tokens[I].Special := TD.id >= Beg;
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
begin
  if Length(ASamples) = 0 then
    raise EWhisperError.Create('No audio to transcribe');
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
    P := FParams.Build(FModel.IsMultilingual);
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
