(* @abstract(@link(TCustomWhisper): the framework-free base of the TWhisperAPI
  component - library and model lifecycle, transcription on a worker
  thread, events on the main thread.)

  A framework unit (Whisper.FMX) derives TWhisperAPI from it, publishes the
  properties and shows handler exceptions the framework's way; everything
  else lives here, as TCustomSteamAPI does in TSteamAPI.

  @bold(Lifecycle.) Setting @link(TCustomWhisper.Active) to @true loads the
  library (@link(TCustomWhisper.LibraryPath)), optionally checks the record
  layout, and loads @link(TCustomWhisper.ModelFile). A failure fires
  @link(TCustomWhisper.OnLoadFailed) (or is shown when that is not
  assigned) and leaves Active @false - it never raises, so Active = True in
  the form file cannot end the program. At design time nothing is loaded.

  @bold(Transcription.) @link(TCustomWhisper.TranscribeAsync) /
  @link(TCustomWhisper.TranscribeFileAsync) run on a worker thread;
  OnSegment, OnProgress, OnComplete and OnLog are delivered on the main
  thread through TThread.Queue (a console program must call
  CheckSynchronize). @link(TCustomWhisper.Transcribe) runs on the calling
  thread and fires the events there. One transcription at a time per
  component (@link(TCustomWhisper.Busy)).

  @bold(Devices.) @link(TCustomWhisper.Device) names the compute device
  the model is loaded onto ('CPU', 'CUDA0', 'Vulkan1', ...; '' =
  whisper.cpp's default: the first GPU when UseGPU). An unknown name falls
  back to the default with a warning in OnLog, so a program keeps working
  when a GPU or its driver disappears. @link(TCustomWhisper.Devices) lists
  what the loaded backends offer; @link(TCustomWhisper.BenchmarkFileAsync)
  times them - for ModelFile or for several models - and reports the
  fastest (OnBenchmarkComplete), for the program to store in Device (and
  ModelFile). *)
unit Whisper.Components;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes, SyncObjs,
  Whisper.Types, Whisper.API, Whisper.Core, Whisper.Audio;

{$ifndef FPC}
const
  { Platforms of the Whisper components (ComponentPlatformsAttribute):
    64-bit only. No Win32: there is no 32-bit whisper.dll to ship (ggml
    1.9.5 does not link for 32-bit MSVC - _pdep_u64 is x64-only - and the
    owner does not ship 32-bit). lib/ still compiles for Win32, which a
    32-bit IDE needs to load the design-time package. }
  WHISPER_COMPONENT_PLATFORMS = pidWin64 or pidOSX64 or pidOSXArm64 or pidLinux64 or
    pidAndroidArm64;
{$endif}

type
  TCustomWhisper = class;

  { The model could not be loaded. }
  TWhisperFailedEvent = procedure(Sender: TObject; const AMessage: string) of object;
  { A transcription finished (also when cancelled or failed: see the record). }
  TWhisperCompleteEvent = procedure(Sender: TObject; const AResult: TWhisperTranscription) of object;
  { A benchmark finished: every result and the index of the fastest
    successful model / device pair (-1 when none succeeded or it was
    cancelled before any); @code(TWhisperBenchmark.Best) with a model file
    gives the fastest device of one model. }
  TWhisperBenchmarkCompleteEvent = procedure(Sender: TObject; const AResults: TWhisperBenchmarkArray;
    ABest: Integer) of object;
  { Last chance to change the settings of a run (main thread, before the
    worker starts). }
  TWhisperBeforeRunEvent = procedure(Sender: TObject; AParams: TWhisperParams) of object;

  { What a queued message carries. }
  TWhisperMessageKind = (
    { A segment. }
    wmkSegment,
    { Progress. }
    wmkProgress,
    { A log line. }
    wmkLog,
    { The run finished. }
    wmkComplete,
    { The benchmark starts a model / device pair. }
    wmkBenchDevice,
    { The benchmark timed a device. }
    wmkBenchResult,
    { The benchmark finished. }
    wmkBenchComplete
  );

  { One event moved from a worker thread to the main thread. Frees itself
    after delivery; delivered only while its component lives. }
  TWhisperQueuedMessage = class
  private
    { Component to deliver to; @nil once the component is gone. }
    FOwner: TCustomWhisper;
    { What this is. }
    FKind: TWhisperMessageKind;
    { Segment (wmkSegment). }
    FSegment: TWhisperSegment;
    { Progress (wmkProgress). }
    FProgress: Integer;
    { Log level (wmkLog). }
    FLevel: TWhisperLogLevel;
    { Log text (wmkLog). }
    FText: string;
    { Result (wmkComplete). }
    FResult: TWhisperTranscription;
    { Device (wmkBenchDevice). }
    FDevice: TWhisperDevice;
    { Model file (wmkBenchDevice). }
    FModelFile: string;
    { One benchmark result (wmkBenchResult). }
    FBench: TWhisperBenchmarkResult;
    { Every benchmark result (wmkBenchComplete). }
    FBenchResults: TWhisperBenchmarkArray;
    { Index of the fastest (wmkBenchComplete). }
    FBest: Integer;
  public
    { Runs on the main thread: hands itself to the component, then frees itself. }
    procedure Deliver;
  end;

  { Worker thread of one asynchronous transcription. }
  TWhisperWorker = class(TThread)
  private
    { The component. }
    FOwner: TCustomWhisper;
    { The run (owned). }
    FRun: TWhisperRun;
    { Settings of the run (owned). }
    FParams: TWhisperParams;
    { Audio, when given directly. }
    FSamples: TWhisperSamples;
    { WAV file to read, when given as a file. }
    FFileName: string;
    { Run's OnSegment: queues the segment. }
    procedure RunSegment(Sender: TObject; const ASegment: TWhisperSegment);
    { Run's OnProgress: queues the progress. }
    procedure RunProgress(Sender: TObject; AProgress: Integer);
  protected
    { Reads the audio (if a file), runs, queues the result. }
    procedure Execute; override;
  public
    { A suspended worker; the component starts it. }
    constructor Create(AOwner: TCustomWhisper; AParams: TWhisperParams;
      const ASamples: TWhisperSamples; const AFileName: string);
    { Frees the run and the params. }
    destructor Destroy; override;
    { Cancels the run. }
    procedure Cancel;
  end;

  { Worker thread of one asynchronous benchmark. }
  TWhisperBenchmarkWorker = class(TThread)
  private
    { The component. }
    FOwner: TCustomWhisper;
    { The benchmark (owned; created in Execute once the audio is read). }
    FBench: TWhisperBenchmark;
    { Settings of the runs (owned). }
    FParams: TWhisperParams;
    { Model loading settings. }
    FContextParams: TWhisperContextParams;
    { Model files (owned copy). }
    FModelFiles: TStringList;
    { Audio, when given directly. }
    FSamples: TWhisperSamples;
    { WAV file to read, when given as a file. }
    FFileName: string;
    { Seconds of audio per timed run. }
    FMaxSeconds: Double;
    { Devices to time (empty = all selectable). }
    FDevices: TWhisperDeviceArray;
    { Set by Cancel before FBench exists. }
    FCancel: Boolean;
    { Guards FBench against Cancel. }
    FLock: TCriticalSection;
    { Benchmark's OnStart: queues the model and device. }
    procedure BenchDevice(Sender: TObject; const AModelFile: string; const ADevice: TWhisperDevice);
    { Benchmark's OnResult: queues the result. }
    procedure BenchResult(Sender: TObject; const AResult: TWhisperBenchmarkResult);
  protected
    { Reads the audio (if a file), times the devices, queues the outcome. }
    procedure Execute; override;
  public
    { A suspended worker; the component starts it. }
    constructor Create(AOwner: TCustomWhisper; AParams: TWhisperParams;
      const AContextParams: TWhisperContextParams; AModelFiles: TStrings;
      const ASamples: TWhisperSamples; const AFileName: string; AMaxSeconds: Double;
      const ADevices: TWhisperDeviceArray);
    { Frees the benchmark, the params and the model list. }
    destructor Destroy; override;
    { Stops after the run in progress. }
    procedure Cancel;
  end;

  { Framework-free whisper.cpp component. See the unit description. }
  TCustomWhisper = class(TComponent)
  private
    { Backing field of @link(Active). }
    FActive: Boolean;
    { Active as read from the form file, applied in Loaded. }
    FStreamedActive: Boolean;
    { Backing field of @link(LibraryPath). }
    FLibraryPath: string;
    { Backing field of @link(ModelFile). }
    FModelFile: string;
    { Backing field of @link(UseGPU). }
    FUseGPU: Boolean;
    { Backing field of @link(FlashAttention). }
    FFlashAttention: Boolean;
    { Backing field of @link(GPUDevice). }
    FGPUDevice: Integer;
    { Backing field of @link(Device). }
    FDevice: string;
    { Name of the device the model was loaded onto. }
    FActiveDevice: string;
    { Worker of the benchmark in progress. }
    FBenchWorker: TWhisperBenchmarkWorker;
    { Backing field of @link(OnBenchmarkStart). }
    FOnBenchmarkStart: TWhisperBenchmarkStartEvent;
    { Backing field of @link(OnBenchmarkResult). }
    FOnBenchmarkResult: TWhisperBenchmarkEvent;
    { Backing field of @link(OnBenchmarkComplete). }
    FOnBenchmarkComplete: TWhisperBenchmarkCompleteEvent;
    { Backing field of @link(DtwPreset). }
    FDtwPreset: TWhisperAlignmentHeadsPreset;
    { Backing field of @link(CheckLayout). }
    FCheckLayout: Boolean;
    { Backing field of @link(Language). }
    FLanguage: string;
    { Backing field of @link(Translate). }
    FTranslate: Boolean;
    { Backing field of @link(Threads). }
    FThreads: Integer;
    { Backing field of @link(Strategy). }
    FStrategy: TWhisperSamplingStrategy;
    { Backing field of @link(BeamSize). }
    FBeamSize: Integer;
    { Backing field of @link(TokenTimestamps). }
    FTokenTimestamps: Boolean;
    { Backing field of @link(MaxSegmentLength). }
    FMaxSegmentLength: Integer;
    { Backing field of @link(SplitOnWord). }
    FSplitOnWord: Boolean;
    { Backing field of @link(InitialPrompt). }
    FInitialPrompt: string;
    { Backing field of @link(NoContext). }
    FNoContext: Boolean;
    { Backing field of @link(SuppressNonSpeech). }
    FSuppressNonSpeech: Boolean;
    { Backing field of @link(Vad). }
    FVad: Boolean;
    { Backing field of @link(VadModelFile). }
    FVadModelFile: string;
    { Backing field of @link(IncludeTokens). }
    FIncludeTokens: Boolean;
    { Backing field of @link(LogLevel). }
    FLogLevel: TWhisperLogLevel;
    { The loaded model. }
    FModel: TWhisperModel;
    { Backing field of @link(Params) (created on first use). }
    FParams: TWhisperParams;
    { Worker of the asynchronous run in progress. }
    FWorker: TWhisperWorker;
    { Run of the synchronous transcription in progress. }
    FSyncRun: TWhisperRun;
    { Messages queued and not yet delivered. }
    FPending: TList;
    { Guards FPending. }
    FPendingLock: TCriticalSection;
    { @true once Destroy started: messages are no longer delivered. }
    FClosing: Boolean;
    { @true while subscribed to the library log. }
    FLogHooked: Boolean;
    { Backing field of @link(OnLoaded). }
    FOnLoaded: TNotifyEvent;
    { Backing field of @link(OnLoadFailed). }
    FOnLoadFailed: TWhisperFailedEvent;
    { Backing field of @link(OnUnloaded). }
    FOnUnloaded: TNotifyEvent;
    { Backing field of @link(OnBeforeRun). }
    FOnBeforeRun: TWhisperBeforeRunEvent;
    { Backing field of @link(OnSegment). }
    FOnSegment: TWhisperSegmentEvent;
    { Backing field of @link(OnProgress). }
    FOnProgress: TWhisperProgressEvent;
    { Backing field of @link(OnComplete). }
    FOnComplete: TWhisperCompleteEvent;
    { Backing field of @link(OnLog). }
    FOnLog: TWhisperLogEvent;
    { Setter of @link(Active). }
    procedure SetActive(const AValue: Boolean);
    { Loads library and model; sets FActive or fires the failure. }
    procedure DoActivate;
    { Cancels and waits for a run, frees the model. }
    procedure DoDeactivate;
    { Getter of @link(Busy). }
    function GetBusy: Boolean;
    { Getter of @link(Params). }
    function GetParams: TWhisperParams;
    { Library log listener (any thread). }
    procedure LibLog(Sender: TObject; ALevel: TWhisperLogLevel; const AText: string);
    { Builds the settings of one run from the properties and Params. }
    function BuildRunParams: TWhisperParams;
    { Starts a worker for samples or a file. }
    procedure StartWorker(const ASamples: TWhisperSamples; const AFileName: string);
    { Context params from UseGPU, GPUDevice, FlashAttention, DtwPreset and
      Device; ADeviceUsed receives the device they select. }
    function BuildContextParams(ALib: TWhisperLib; out ADeviceUsed: string): TWhisperContextParams;
    { Starts a benchmark worker for samples or a file. }
    procedure StartBenchmark(const ASamples: TWhisperSamples; const AFileName: string;
      AMaxSeconds: Double; const ADevices: TWhisperDeviceArray; AModelFiles: TStrings);
    { Starts the benchmark worker for a non-empty model list. }
    procedure StartBenchmarkWorker(const ASamples: TWhisperSamples; const AFileName: string;
      AMaxSeconds: Double; const ADevices: TWhisperDeviceArray; AModels: TStringList);
    { Run's OnSegment for synchronous runs. }
    procedure SyncSegment(Sender: TObject; const ASegment: TWhisperSegment);
    { Run's OnProgress for synchronous runs. }
    procedure SyncProgress(Sender: TObject; AProgress: Integer);
    { Fires OnLog (main thread), with a handler exception shown. }
    procedure FireLog(ALevel: TWhisperLogLevel; const AText: string);
  protected
    { Applies Active from the form file. }
    procedure Loaded; override;
    { Shows an exception raised by an event handler or a failed activation
      (the framework unit uses Application.ShowException). Default:
      re-raise nothing, write nothing. }
    procedure ShowHandlerException(E: Exception); virtual;
    { Stops message delivery for good (Destroy): queued messages are
      orphaned and later ones are only freed. }
    procedure OrphanPending;
    { Adds a message for the main thread (any thread). }
    procedure Post(AMessage: TWhisperQueuedMessage);
    { Delivers a message on the main thread (called by the message). }
    procedure DeliverMessage(AMessage: TWhisperQueuedMessage);
    { Writes a line of the component's own to OnLog. }
    procedure Log(ALevel: TWhisperLogLevel; const AText: string);
  public
    { Defaults: UseGPU, FlashAttention, CheckLayout on; Language 'auto';
      greedy decoding; LogLevel info. }
    constructor Create(AOwner: TComponent); override;
    { Cancels a run or benchmark in progress, waits for it and unloads the model. }
    destructor Destroy; override;

    { Transcribes on the calling thread; events fire on that thread.
      @returns(The result (also passed to OnComplete).)
      @raises(EWhisperError when not active or already busy.) }
    function Transcribe(const ASamples: TWhisperSamples): TWhisperTranscription;
    { Reads a WAV file (Whisper.Audio) and transcribes it on the calling thread. }
    function TranscribeFile(const AFileName: string): TWhisperTranscription;
    { Transcribes on a worker thread; events arrive on the main thread,
      ending with OnComplete.
      @raises(EWhisperError when not active or already busy.) }
    procedure TranscribeAsync(const ASamples: TWhisperSamples);
    { Reads a WAV file and transcribes it on a worker thread. A file that
      cannot be read ends with OnComplete (ErrorMessage set). }
    procedure TranscribeFileAsync(const AFileName: string);
    { Asks the run or benchmark in progress to stop; OnComplete (Cancelled)
      or OnBenchmarkComplete follows. }
    procedure Cancel;

    { Every device of the loaded backends (loads the library when needed;
      empty when it cannot be loaded - the reason goes to OnLog). }
    function Devices: TWhisperDeviceArray;
    { The devices Device can name: the CPU, then every GPU / IGPU. }
    function SelectableDevices: TWhisperDeviceArray;
    { Times transcription of the first AMaxSeconds of ASamples with each
      model of AModelFiles (@nil or empty = ModelFile) on each of ADevices
      (empty = all selectable), on a worker thread, with the published
      settings (Active not needed; each model is loaded once per device,
      besides any active one). OnBenchmarkStart, OnBenchmarkResult and
      OnBenchmarkComplete follow on the main thread.
      @raises(EWhisperError when busy or there is no model.) }
    procedure BenchmarkAsync(const ASamples: TWhisperSamples; AMaxSeconds: Double;
      const ADevices: TWhisperDeviceArray; AModelFiles: TStrings = nil);
    { BenchmarkAsync on a WAV file, read on the worker thread. }
    procedure BenchmarkFileAsync(const AFileName: string; AMaxSeconds: Double;
      const ADevices: TWhisperDeviceArray; AModelFiles: TStrings = nil);
    { Name of the device the active model runs on ('' while not active). }
    property ActiveDevice: string read FActiveDevice;

    { Codes of every language the library knows ('en', 'zh', ...), loading
      the library when needed; empty when it cannot be loaded. }
    function LanguageCodes: TStringList;

    { @true while a transcription runs. }
    property Busy: Boolean read GetBusy;
    { The loaded model (@nil while not active). }
    property Model: TWhisperModel read FModel;
    { Settings beyond the published properties, applied to every run after
      them (the published ones win). Changes apply to the next run. }
    property Params: TWhisperParams read GetParams;

    { Loads the library and the model (@true) or unloads the model. }
    property Active: Boolean read FActive write SetActive default False;
    { The whisper.cpp library: '' = next to the executable / system search,
      a folder or a file. }
    property LibraryPath: string read FLibraryPath write FLibraryPath;
    { The ggml model file (ggml-base.en.bin, ...). }
    property ModelFile: string read FModelFile write FModelFile;
    { Use the GPU backend (when the library has one). Applies on activation. }
    property UseGPU: Boolean read FUseGPU write FUseGPU default True;
    { Flash attention. Applies on activation. }
    property FlashAttention: Boolean read FFlashAttention write FFlashAttention default True;
    { GPU device index. Applies on activation. }
    property GPUDevice: Integer read FGPUDevice write FGPUDevice default 0;
    { Compute device by name: 'CPU', 'CUDA0', 'Vulkan1', ... (see Devices);
      '' = UseGPU / GPUDevice decide. Overrides them when set. An unknown
      name falls back to them with a warning. Applies on activation. }
    property Device: string read FDevice write FDevice;
    { DTW token time stamps: the preset of the model in use (wahNone = off).
      Applies on activation. }
    property DtwPreset: TWhisperAlignmentHeadsPreset read FDtwPreset write FDtwPreset default wahNone;
    { Check the record layout against whisper.h on activation and refuse a
      library that does not match. }
    property CheckLayout: Boolean read FCheckLayout write FCheckLayout default True;
    { Language code, or 'auto' to detect. }
    property Language: string read FLanguage write FLanguage;
    { Translate to English. }
    property Translate: Boolean read FTranslate write FTranslate default False;
    { CPU threads; 0 = library default (up to 4). }
    property Threads: Integer read FThreads write FThreads default 0;
    { Greedy (fast) or beam search (more accurate). }
    property Strategy: TWhisperSamplingStrategy read FStrategy write FStrategy default wssGreedy;
    { Beams of the beam search. }
    property BeamSize: Integer read FBeamSize write FBeamSize default 5;
    { Token-level time stamps. }
    property TokenTimestamps: Boolean read FTokenTimestamps write FTokenTimestamps default False;
    { Max segment length in characters (0 = no limit). }
    property MaxSegmentLength: Integer read FMaxSegmentLength write FMaxSegmentLength default 0;
    { Split on words (with MaxSegmentLength). }
    property SplitOnWord: Boolean read FSplitOnWord write FSplitOnWord default False;
    { Initial prompt: vocabulary, names, style. }
    property InitialPrompt: string read FInitialPrompt write FInitialPrompt;
    { Do not use earlier text as prompt. }
    property NoContext: Boolean read FNoContext write FNoContext default False;
    { Suppress non-speech tokens. }
    property SuppressNonSpeech: Boolean read FSuppressNonSpeech write FSuppressNonSpeech default False;
    { Voice activity detection (needs VadModelFile). }
    property Vad: Boolean read FVad write FVad default False;
    { Silero VAD model (ggml-silero-*.bin). }
    property VadModelFile: string read FVadModelFile write FVadModelFile;
    { Fill the Tokens of each segment. }
    property IncludeTokens: Boolean read FIncludeTokens write FIncludeTokens default False;
    { Lowest level of library log lines passed to OnLog (wllNone = all). }
    property LogLevel: TWhisperLogLevel read FLogLevel write FLogLevel default wllInfo;

    { The model is loaded. }
    property OnLoaded: TNotifyEvent read FOnLoaded write FOnLoaded;
    { The library or the model could not be loaded. }
    property OnLoadFailed: TWhisperFailedEvent read FOnLoadFailed write FOnLoadFailed;
    { The model was unloaded. }
    property OnUnloaded: TNotifyEvent read FOnUnloaded write FOnUnloaded;
    { Change the settings of a run before it starts. }
    property OnBeforeRun: TWhisperBeforeRunEvent read FOnBeforeRun write FOnBeforeRun;
    { A new segment. }
    property OnSegment: TWhisperSegmentEvent read FOnSegment write FOnSegment;
    { Progress 0..100. }
    property OnProgress: TWhisperProgressEvent read FOnProgress write FOnProgress;
    { The run finished. }
    property OnComplete: TWhisperCompleteEvent read FOnComplete write FOnComplete;
    { Log lines of whisper.cpp / ggml and of the component. }
    property OnLog: TWhisperLogEvent read FOnLog write FOnLog;
    { A benchmark starts a model / device pair. }
    property OnBenchmarkStart: TWhisperBenchmarkStartEvent read FOnBenchmarkStart write FOnBenchmarkStart;
    { A benchmark timed a model / device pair. }
    property OnBenchmarkResult: TWhisperBenchmarkEvent read FOnBenchmarkResult write FOnBenchmarkResult;
    { A benchmark finished. }
    property OnBenchmarkComplete: TWhisperBenchmarkCompleteEvent read FOnBenchmarkComplete
      write FOnBenchmarkComplete;
  end;

implementation

uses
  StrUtils, DateUtils;

{ TWhisperQueuedMessage }

procedure TWhisperQueuedMessage.Deliver;
begin
  try
    if FOwner <> nil then
      FOwner.DeliverMessage(Self);
  finally
    Free;
  end;
end;

{ TWhisperWorker }

constructor TWhisperWorker.Create(AOwner: TCustomWhisper; AParams: TWhisperParams;
  const ASamples: TWhisperSamples; const AFileName: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FParams := AParams;
  FSamples := ASamples;
  FFileName := AFileName;
  FRun := TWhisperRun.Create(AOwner.Model, AParams);
  FRun.IncludeTokens := AOwner.IncludeTokens;
  FRun.OnSegment := RunSegment;
  FRun.OnProgress := RunProgress;
end;

destructor TWhisperWorker.Destroy;
begin
  FreeAndNil(FRun);
  FreeAndNil(FParams);
  inherited;
end;

procedure TWhisperWorker.Cancel;
begin
  if FRun <> nil then
    FRun.Cancel;
end;

procedure TWhisperWorker.RunSegment(Sender: TObject; const ASegment: TWhisperSegment);
var
  M: TWhisperQueuedMessage;
begin
  M := TWhisperQueuedMessage.Create;
  M.FKind := wmkSegment;
  M.FSegment := ASegment;
  FOwner.Post(M);
end;

procedure TWhisperWorker.RunProgress(Sender: TObject; AProgress: Integer);
var
  M: TWhisperQueuedMessage;
begin
  M := TWhisperQueuedMessage.Create;
  M.FKind := wmkProgress;
  M.FProgress := AProgress;
  FOwner.Post(M);
end;

procedure TWhisperWorker.Execute;
var
  R: TWhisperTranscription;
  M: TWhisperQueuedMessage;
  Info: TWhisperWavInfo;
  ReadStart: TDateTime;
begin
  FillChar(Info, SizeOf(Info), 0);
  R.Segments := nil;
  R.LanguageCode := '';
  R.LanguageName := '';
  R.ResultCode := 0;
  R.Cancelled := False;
  R.AudioSeconds := 0;
  R.ElapsedMs := 0;
  R.ErrorMessage := '';
  try
    if FFileName <> '' then
    begin
      ReadStart := Now;
      FSamples := WhisperLoadWav(FFileName, Info);
      M := TWhisperQueuedMessage.Create;
      M.FKind := wmkLog;
      M.FLevel := wllInfo;
      M.FText := Format('Read %s: %d channel(s), %d Hz, %d bits, %d frames -> %d samples at %d Hz (%.2f s) in %d ms',
        [FFileName, Info.Channels, Info.SampleRate, Info.BitsPerSample, Info.Frames,
         Length(FSamples), WHISPER_SAMPLE_RATE, WhisperSamplesSeconds(FSamples), MilliSecondsBetween(Now, ReadStart)]);
      FOwner.Post(M);
    end;
    R := FRun.Execute(FSamples);
  except
    on E: Exception do
    begin
      R.ErrorMessage := E.Message;
      R.Cancelled := FRun.Cancelled;
    end;
  end;
  M := TWhisperQueuedMessage.Create;
  M.FKind := wmkComplete;
  M.FResult := R;
  FOwner.Post(M);
end;

{ TWhisperBenchmarkWorker }

constructor TWhisperBenchmarkWorker.Create(AOwner: TCustomWhisper; AParams: TWhisperParams;
  const AContextParams: TWhisperContextParams; AModelFiles: TStrings;
  const ASamples: TWhisperSamples; const AFileName: string; AMaxSeconds: Double;
  const ADevices: TWhisperDeviceArray);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FParams := AParams;
  FContextParams := AContextParams;
  FModelFiles := TStringList.Create;
  FModelFiles.Assign(AModelFiles);
  FSamples := ASamples;
  FFileName := AFileName;
  FMaxSeconds := AMaxSeconds;
  FDevices := ADevices;
  FLock := TCriticalSection.Create;
end;

destructor TWhisperBenchmarkWorker.Destroy;
begin
  FreeAndNil(FBench);
  FreeAndNil(FParams);
  FreeAndNil(FModelFiles);
  FreeAndNil(FLock);
  inherited;
end;

procedure TWhisperBenchmarkWorker.Cancel;
begin
  FLock.Acquire;
  try
    FCancel := True;
    if FBench <> nil then
      FBench.Cancel;
  finally
    FLock.Release;
  end;
end;

procedure TWhisperBenchmarkWorker.BenchDevice(Sender: TObject; const AModelFile: string;
  const ADevice: TWhisperDevice);
var
  M: TWhisperQueuedMessage;
begin
  M := TWhisperQueuedMessage.Create;
  M.FKind := wmkBenchDevice;
  M.FModelFile := AModelFile;
  M.FDevice := ADevice;
  FOwner.Post(M);
end;

procedure TWhisperBenchmarkWorker.BenchResult(Sender: TObject; const AResult: TWhisperBenchmarkResult);
var
  M: TWhisperQueuedMessage;
begin
  M := TWhisperQueuedMessage.Create;
  M.FKind := wmkBenchResult;
  M.FBench := AResult;
  FOwner.Post(M);
end;

procedure TWhisperBenchmarkWorker.Execute;
var
  Results: TWhisperBenchmarkArray;
  M: TWhisperQueuedMessage;
  Bench: TWhisperBenchmark;
  I: Integer;
begin
  Results := nil;
  try
    if FFileName <> '' then
      FSamples := WhisperLoadWav(FFileName);
    Bench := TWhisperBenchmark.Create(FModelFiles[0], FSamples);
    for I := 1 to FModelFiles.Count - 1 do
      Bench.ModelFiles.Add(FModelFiles[I]);
    FLock.Acquire;
    try
      FBench := Bench;
      if FCancel then
        Bench.Cancel;
    finally
      FLock.Release;
    end;
    Bench.Params := FParams;
    Bench.ContextParams := FContextParams;
    Bench.MaxSeconds := FMaxSeconds;
    Bench.OnStart := BenchDevice;
    Bench.OnResult := BenchResult;
    Results := Bench.Run(FDevices);
  except
    on E: Exception do
    begin
      M := TWhisperQueuedMessage.Create;
      M.FKind := wmkLog;
      M.FLevel := wllError;
      M.FText := 'Benchmark failed: ' + E.Message;
      FOwner.Post(M);
    end;
  end;
  M := TWhisperQueuedMessage.Create;
  M.FKind := wmkBenchComplete;
  M.FBenchResults := Results;
  M.FBest := TWhisperBenchmark.Best(Results);
  FOwner.Post(M);
end;

{ TCustomWhisper }

constructor TCustomWhisper.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUseGPU := True;
  FFlashAttention := True;
  FCheckLayout := True;
  FLanguage := WHISPER_LANGUAGE_AUTO;
  FStrategy := wssGreedy;
  FBeamSize := 5;
  FLogLevel := wllInfo;
  FPending := TList.Create;
  FPendingLock := TCriticalSection.Create;
end;

destructor TCustomWhisper.Destroy;
begin
  // First stop delivery: waiting for a worker below runs CheckSynchronize,
  // which would otherwise call the owner's handlers (a form part-destroyed).
  OrphanPending;
  if FBenchWorker <> nil then
  begin
    FBenchWorker.Cancel;
    FBenchWorker.WaitFor;   // only queued calls: no deadlock
    FreeAndNil(FBenchWorker);
  end;
  if not (csDesigning in ComponentState) then
    DoDeactivate;
  OrphanPending;   // anything posted while waiting
  FreeAndNil(FParams);
  FreeAndNil(FPending);
  FreeAndNil(FPendingLock);
  inherited;
end;

procedure TCustomWhisper.OrphanPending;
var
  I: Integer;
begin
  if FPendingLock = nil then
    Exit;
  FPendingLock.Acquire;
  try
    FClosing := True;
    // Messages still in the main thread's queue free themselves without
    // calling us.
    for I := 0 to FPending.Count - 1 do
      TWhisperQueuedMessage(FPending[I]).FOwner := nil;
    FPending.Clear;
  finally
    FPendingLock.Release;
  end;
end;

procedure TCustomWhisper.Loaded;
begin
  inherited;
  if csDesigning in ComponentState then
    FActive := FStreamedActive
  else if FStreamedActive then
    SetActive(True);   // a failure is shown, never raised (see SetActive)
  FStreamedActive := False;
end;

procedure TCustomWhisper.ShowHandlerException(E: Exception);
begin
  // framework units override this
end;

procedure TCustomWhisper.SetActive(const AValue: Boolean);
begin
  if csLoading in ComponentState then
  begin
    FStreamedActive := AValue;
    Exit;
  end;
  if csDesigning in ComponentState then
  begin
    FActive := AValue;   // never load the library inside the IDE
    Exit;
  end;
  if AValue = FActive then
    Exit;
  if AValue then
    DoActivate
  else
    DoDeactivate;
end;

procedure TCustomWhisper.DoActivate;
var
  Lib: TWhisperLib;
  Report: TStringList;
  P: TWhisperContextParams;
  I: Integer;
  Msg: string;
  E: EWhisperError;
  DeviceUsed: string;
begin
  Msg := '';
  try
    Lib := TWhisperLib.Load(FLibraryPath);
    if not FLogHooked then
    begin
      Lib.AddLogListener(LibLog);
      FLogHooked := True;
    end;
    for I := 0 to Lib.LoadLog.Count - 1 do
      Log(wllInfo, Lib.LoadLog[I]);
    Log(wllInfo, Format('whisper.cpp %s from %s', [Lib.Version, Lib.FileName]));
    Log(wllInfo, 'System info: ' + Lib.SystemInfo);
    if FCheckLayout then
    begin
      Report := TStringList.Create;
      try
        if not Lib.CheckLayout(Report) then
          raise EWhisperError.Create(Report.Text);
        for I := 0 to Report.Count - 1 do
          Log(wllInfo, Report[I]);
      finally
        Report.Free;
      end;
    end;
    if FModelFile = '' then
      raise EWhisperError.Create('No ModelFile set');
    P := BuildContextParams(Lib, DeviceUsed);
    FModel := TWhisperModel.Create(FModelFile, P);
    FActiveDevice := DeviceUsed;
    Log(wllInfo, Format('Model %s loaded on %s: %s', [FModelFile, DeviceUsed, FModel.Description]));
    FActive := True;
  except
    on Ex: Exception do
      Msg := Ex.Message;
  end;
  if FActive then
  begin
    if Assigned(FOnLoaded) then
      try
        FOnLoaded(Self);
      except
        on Ex: Exception do
          ShowHandlerException(Ex);
      end;
  end
  else
  begin
    Log(wllError, 'Activation failed: ' + Msg);
    if Assigned(FOnLoadFailed) then
      try
        FOnLoadFailed(Self, Msg);
      except
        on Ex: Exception do
          ShowHandlerException(Ex);
      end
    else
    begin
      // No silent failure, but no exception either: raised from Loaded it
      // would end the program before the form is shown.
      E := EWhisperError.Create(Msg);
      try
        ShowHandlerException(E);
      finally
        E.Free;
      end;
    end;
  end;
end;

procedure TCustomWhisper.DoDeactivate;
var
  WasActive: Boolean;
begin
  WasActive := FActive;
  if FWorker <> nil then
  begin
    FWorker.Cancel;
    FWorker.WaitFor;     // only queued (never synchronised) calls: no deadlock
    FreeAndNil(FWorker);
  end;
  if FSyncRun <> nil then
    FSyncRun.Cancel;
  FreeAndNil(FModel);
  FActiveDevice := '';
  if FLogHooked and TWhisperLib.IsLoaded then
    TWhisperLib.Instance.RemoveLogListener(LibLog);
  FLogHooked := False;
  FActive := False;
  if WasActive and Assigned(FOnUnloaded) and not (csDestroying in ComponentState) then
    try
      FOnUnloaded(Self);
    except
      on E: Exception do
        ShowHandlerException(E);
    end;
end;

function TCustomWhisper.GetBusy: Boolean;
begin
  Result := (FWorker <> nil) or (FSyncRun <> nil) or (FBenchWorker <> nil);
end;

function TCustomWhisper.GetParams: TWhisperParams;
begin
  if FParams = nil then
  begin
    TWhisperLib.Load(FLibraryPath);
    FParams := TWhisperParams.Create(FStrategy);
  end;
  Result := FParams;
end;

function TCustomWhisper.BuildRunParams: TWhisperParams;
begin
  Result := TWhisperParams.Create(FStrategy);
  try
    if FParams <> nil then
      Result.Assign(FParams);
    Result.Strategy := FStrategy;
    if FThreads > 0 then
      Result.Threads := FThreads;
    Result.Language := FLanguage;
    Result.Translate := FTranslate;
    Result.BeamSize := FBeamSize;
    Result.TokenTimestamps := FTokenTimestamps or (FMaxSegmentLength > 0);
    Result.MaxSegmentLength := FMaxSegmentLength;
    Result.SplitOnWord := FSplitOnWord;
    Result.InitialPrompt := FInitialPrompt;
    Result.NoContext := FNoContext;
    Result.SuppressNonSpeech := FSuppressNonSpeech;
    Result.Vad := FVad;
    Result.VadModelFile := FVadModelFile;
    if Assigned(FOnBeforeRun) then
      FOnBeforeRun(Self, Result);
  except
    Result.Free;
    raise;
  end;
end;

procedure TCustomWhisper.StartWorker(const ASamples: TWhisperSamples; const AFileName: string);
var
  P: TWhisperParams;
begin
  if not FActive then
    raise EWhisperError.Create('TWhisperAPI is not active: set ModelFile and Active first');
  if Busy then
    raise EWhisperError.Create('A transcription or benchmark is already running');
  P := BuildRunParams;
  try
    FWorker := TWhisperWorker.Create(Self, P, ASamples, AFileName);
  except
    P.Free;
    raise;
  end;
  Log(wllInfo, Format('Transcription started (%s, language %s, %s)',
    [FModel.ModelType, P.Language, IfThen(P.Translate, 'translate', 'transcribe')]));
  FWorker.Start;
end;

procedure TCustomWhisper.TranscribeAsync(const ASamples: TWhisperSamples);
begin
  if Length(ASamples) = 0 then
    raise EWhisperError.Create('No audio to transcribe');
  StartWorker(ASamples, '');
end;

procedure TCustomWhisper.TranscribeFileAsync(const AFileName: string);
begin
  if AFileName = '' then
    raise EWhisperError.Create('No audio file given');
  StartWorker(nil, AFileName);
end;

function TCustomWhisper.Transcribe(const ASamples: TWhisperSamples): TWhisperTranscription;
var
  P: TWhisperParams;
begin
  if not FActive then
    raise EWhisperError.Create('TWhisperAPI is not active: set ModelFile and Active first');
  if Busy then
    raise EWhisperError.Create('A transcription or benchmark is already running');
  P := BuildRunParams;
  try
    FSyncRun := TWhisperRun.Create(FModel, P);
    try
      FSyncRun.IncludeTokens := FIncludeTokens;
      FSyncRun.OnSegment := SyncSegment;
      FSyncRun.OnProgress := SyncProgress;
      Result := FSyncRun.Execute(ASamples);
    finally
      FreeAndNil(FSyncRun);
    end;
  finally
    P.Free;
  end;
  if Assigned(FOnComplete) then
    FOnComplete(Self, Result);
end;

function TCustomWhisper.TranscribeFile(const AFileName: string): TWhisperTranscription;
begin
  Result := Transcribe(WhisperLoadWav(AFileName));
end;

procedure TCustomWhisper.Cancel;
begin
  if FWorker <> nil then
    FWorker.Cancel;
  if FSyncRun <> nil then
    FSyncRun.Cancel;
  if FBenchWorker <> nil then
    FBenchWorker.Cancel;
end;

function TCustomWhisper.BuildContextParams(ALib: TWhisperLib; out ADeviceUsed: string): TWhisperContextParams;
var
  Devs: TWhisperDeviceArray;
  Names: string;
  I: Integer;
begin
  Result := ALib.DefaultContextParams;
  Result.use_gpu := FUseGPU;
  Result.flash_attn := FFlashAttention;
  Result.gpu_device := FGPUDevice;
  Result.dtw_token_timestamps := FDtwPreset <> wahNone;
  Result.dtw_aheads_preset := FDtwPreset;
  if (FDevice <> '') and not ALib.ContextParamsFor(FDevice, Result) then
  begin
    Devs := ALib.SelectableDevices;
    Names := '';
    for I := 0 to High(Devs) do
      Names := Names + IfThen(Names = '', '', ', ') + Devs[I].Name;
    Log(wllWarn, Format('Device %s is not available (available: %s) - using the default', [FDevice, Names]));
  end;
  // the device these params select, as whisper_backend_init_gpu picks it
  ADeviceUsed := WHISPER_DEVICE_CPU;
  if Result.use_gpu then
  begin
    Devs := ALib.Devices;
    for I := 0 to High(Devs) do
      if Devs[I].GpuIndex = Result.gpu_device then
        ADeviceUsed := Devs[I].Name;
  end;
end;

function TCustomWhisper.Devices: TWhisperDeviceArray;
begin
  Result := nil;
  try
    Result := TWhisperLib.Load(FLibraryPath).Devices;
  except
    on E: EWhisperError do
      Log(wllWarn, 'Device list unavailable: ' + E.Message);
  end;
end;

function TCustomWhisper.SelectableDevices: TWhisperDeviceArray;
begin
  Result := nil;
  try
    Result := TWhisperLib.Load(FLibraryPath).SelectableDevices;
  except
    on E: EWhisperError do
      Log(wllWarn, 'Device list unavailable: ' + E.Message);
  end;
end;

procedure TCustomWhisper.StartBenchmark(const ASamples: TWhisperSamples; const AFileName: string;
  AMaxSeconds: Double; const ADevices: TWhisperDeviceArray; AModelFiles: TStrings);
var
  Models: TStringList;
begin
  if Busy then
    raise EWhisperError.Create('A transcription or benchmark is already running');
  Models := TStringList.Create;
  try
    if (AModelFiles <> nil) and (AModelFiles.Count > 0) then
      Models.Assign(AModelFiles)
    else if FModelFile <> '' then
      Models.Add(FModelFile)
    else
      raise EWhisperError.Create('No model to benchmark: set ModelFile or pass model files');
    StartBenchmarkWorker(ASamples, AFileName, AMaxSeconds, ADevices, Models);
  finally
    Models.Free;
  end;
end;

procedure TCustomWhisper.StartBenchmarkWorker(const ASamples: TWhisperSamples; const AFileName: string;
  AMaxSeconds: Double; const ADevices: TWhisperDeviceArray; AModels: TStringList);
var
  Lib: TWhisperLib;
  P: TWhisperParams;
  CP: TWhisperContextParams;
  Ignored: string;
begin
  Lib := TWhisperLib.Load(FLibraryPath);
  if not FLogHooked then
  begin
    Lib.AddLogListener(LibLog);
    FLogHooked := True;
  end;
  CP := BuildContextParams(Lib, Ignored);
  P := BuildRunParams;
  try
    FBenchWorker := TWhisperBenchmarkWorker.Create(Self, P, CP, AModels, ASamples, AFileName,
      AMaxSeconds, ADevices);
  except
    P.Free;
    raise;
  end;
  Log(wllInfo, Format('Benchmark started: %d model(s), %.0f s of audio per model and device',
    [AModels.Count, AMaxSeconds]));
  FBenchWorker.Start;
end;

procedure TCustomWhisper.BenchmarkAsync(const ASamples: TWhisperSamples; AMaxSeconds: Double;
  const ADevices: TWhisperDeviceArray; AModelFiles: TStrings);
begin
  if Length(ASamples) = 0 then
    raise EWhisperError.Create('A benchmark needs audio');
  StartBenchmark(ASamples, '', AMaxSeconds, ADevices, AModelFiles);
end;

procedure TCustomWhisper.BenchmarkFileAsync(const AFileName: string; AMaxSeconds: Double;
  const ADevices: TWhisperDeviceArray; AModelFiles: TStrings);
begin
  if AFileName = '' then
    raise EWhisperError.Create('No audio file given');
  StartBenchmark(nil, AFileName, AMaxSeconds, ADevices, AModelFiles);
end;

procedure TCustomWhisper.SyncSegment(Sender: TObject; const ASegment: TWhisperSegment);
begin
  if Assigned(FOnSegment) then
    FOnSegment(Self, ASegment);
end;

procedure TCustomWhisper.SyncProgress(Sender: TObject; AProgress: Integer);
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, AProgress);
end;

function TCustomWhisper.LanguageCodes: TStringList;
var
  Lib: TWhisperLib;
  I: Integer;
begin
  Result := TStringList.Create;
  try
    Lib := TWhisperLib.Load(FLibraryPath);
    for I := 0 to Lib.LanguageCount - 1 do
      Result.Add(Lib.LanguageCode(I));
  except
    on E: EWhisperError do
      Log(wllWarn, 'Language list unavailable: ' + E.Message);
  end;
end;

procedure TCustomWhisper.LibLog(Sender: TObject; ALevel: TWhisperLogLevel; const AText: string);
var
  M: TWhisperQueuedMessage;
begin
  if (FLogLevel <> wllNone) and (ALevel < FLogLevel) and (ALevel <> wllNone) then
    Exit;
  if TThread.CurrentThread.ThreadID = MainThreadID then
    FireLog(ALevel, AText)
  else
  begin
    M := TWhisperQueuedMessage.Create;
    M.FKind := wmkLog;
    M.FLevel := ALevel;
    M.FText := AText;
    Post(M);
  end;
end;

procedure TCustomWhisper.Log(ALevel: TWhisperLogLevel; const AText: string);
begin
  LibLog(Self, ALevel, AText);
end;

procedure TCustomWhisper.FireLog(ALevel: TWhisperLogLevel; const AText: string);
begin
  if Assigned(FOnLog) then
    try
      FOnLog(Self, ALevel, AText);
    except
      on E: Exception do
        ShowHandlerException(E);
    end;
end;

procedure TCustomWhisper.Post(AMessage: TWhisperQueuedMessage);
begin
  FPendingLock.Acquire;
  try
    if FClosing then
      AMessage.FOwner := nil   // Deliver only frees it
    else
    begin
      AMessage.FOwner := Self;
      FPending.Add(AMessage);
    end;
  finally
    FPendingLock.Release;
  end;
  TThread.Queue(nil, AMessage.Deliver);
end;

procedure TCustomWhisper.DeliverMessage(AMessage: TWhisperQueuedMessage);
var
  W: TWhisperWorker;
  BW: TWhisperBenchmarkWorker;
begin
  FPendingLock.Acquire;
  try
    FPending.Remove(AMessage);
  finally
    FPendingLock.Release;
  end;
  try
    case AMessage.FKind of
      wmkSegment:
        if Assigned(FOnSegment) then
          FOnSegment(Self, AMessage.FSegment);
      wmkProgress:
        if Assigned(FOnProgress) then
          FOnProgress(Self, AMessage.FProgress);
      wmkLog:
        FireLog(AMessage.FLevel, AMessage.FText);
      wmkComplete:
        begin
          // The worker posted this as its last action: it is ending.
          W := FWorker;
          FWorker := nil;
          if W <> nil then
          begin
            W.WaitFor;
            W.Free;
          end;
          if AMessage.FResult.ErrorMessage <> '' then
            Log(wllError, 'Transcription failed: ' + AMessage.FResult.ErrorMessage)
          else
            Log(wllInfo, Format('Transcription %s: %d segment(s), language %s, %.2f s of audio in %d ms',
              [IfThen(AMessage.FResult.Cancelled, 'cancelled', 'finished'),
               Length(AMessage.FResult.Segments), AMessage.FResult.LanguageCode,
               AMessage.FResult.AudioSeconds, AMessage.FResult.ElapsedMs]));
          if Assigned(FOnComplete) then
            FOnComplete(Self, AMessage.FResult);
        end;
      wmkBenchDevice:
        begin
          Log(wllInfo, Format('Benchmark: timing %s on %s', [ExtractFileName(AMessage.FModelFile),
            WhisperDeviceText(AMessage.FDevice)]));
          if Assigned(FOnBenchmarkStart) then
            FOnBenchmarkStart(Self, AMessage.FModelFile, AMessage.FDevice);
        end;
      wmkBenchResult:
        begin
          if AMessage.FBench.Ok then
            Log(wllInfo, Format('Benchmark: %s on %s: load %d ms, warm-up %d ms, %.1f s of audio in %d ms = %.2fx real time',
              [ExtractFileName(AMessage.FBench.ModelFile), AMessage.FBench.Device.Name, AMessage.FBench.LoadMs, AMessage.FBench.WarmupMs,
               AMessage.FBench.AudioSeconds, AMessage.FBench.RunMs, AMessage.FBench.Speed]))
          else
            Log(wllWarn, Format('Benchmark: %s on %s failed: %s', [ExtractFileName(AMessage.FBench.ModelFile),
              AMessage.FBench.Device.Name, AMessage.FBench.ErrorMessage]));
          if Assigned(FOnBenchmarkResult) then
            FOnBenchmarkResult(Self, AMessage.FBench);
        end;
      wmkBenchComplete:
        begin
          BW := FBenchWorker;
          FBenchWorker := nil;
          if BW <> nil then
          begin
            BW.WaitFor;
            BW.Free;
          end;
          if AMessage.FBest >= 0 then
            Log(wllInfo, Format('Benchmark finished: fastest is %s on %s (%.2fx real time)',
              [ExtractFileName(AMessage.FBenchResults[AMessage.FBest].ModelFile),
               AMessage.FBenchResults[AMessage.FBest].Device.Name, AMessage.FBenchResults[AMessage.FBest].Speed]))
          else
            Log(wllWarn, Format('Benchmark finished: no device succeeded (%d timed)',
              [Length(AMessage.FBenchResults)]));
          if Assigned(FOnBenchmarkComplete) then
            FOnBenchmarkComplete(Self, AMessage.FBenchResults, AMessage.FBest);
        end;
    end;
  except
    on E: Exception do
      ShowHandlerException(E);
  end;
end;

end.
