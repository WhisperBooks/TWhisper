(* @abstract(@link(TWhisper) for FireMonkey - the non-visual component that
  transcribes speech with whisper.cpp.)

  Drop one on a form (palette page "Whisper"), set
  @link(TWhisper.ModelFile) and @link(TWhisper.Active), then call
  TranscribeFileAsync or TranscribeAsync. Every event arrives on the main
  thread. Everything except the exception display lives in the
  framework-free @code(TCustomWhisper) (Whisper.Components); a VCL or LCL
  unit would declare a TWhisper of the same name and behaviour.

  @longCode(#
  procedure TfrmMain.FormCreate(Sender: TObject);
  begin
    Whisper1.ModelFile := TPath.Combine(ModelFolder, 'ggml-base.bin');
    Whisper1.Active := True;          // OnLoaded / OnLoadFailed follow
  end;

  procedure TfrmMain.btnGoClick(Sender: TObject);
  begin
    Whisper1.TranscribeFileAsync(edAudio.Text);
  end;

  procedure TfrmMain.Whisper1Segment(Sender: TObject; const ASegment: TWhisperSegment);
  begin
    memText.Lines.Add(ASegment.Text);
  end;
  #) *)
unit Whisper.FMX;

{$I ..\lib\Whisper.inc}

interface

uses
  SysUtils, Classes, FMX.Types, FMX.Forms,
  Whisper.Types, Whisper.Components;

type
  { FireMonkey TWhisper: @code(TCustomWhisper) with its properties
    published and handler exceptions shown by Application.ShowException. }
  [ComponentPlatformsAttribute(WHISPER_COMPONENT_PLATFORMS)]
  TWhisper = class(TCustomWhisper)
  protected
    { Application.ShowException (Application.HandleException would show
      ExceptObject, which is nil outside an except block). }
    procedure ShowHandlerException(E: Exception); override;
  published
    { Loads the library and the model. At design time the value is only stored. }
    property Active;
    { whisper.cpp library: '' = next to the executable, a folder or a file. }
    property LibraryPath;
    { ggml model file. }
    property ModelFile;
    { Use the GPU backend. }
    property UseGPU;
    { Flash attention. }
    property FlashAttention;
    { GPU device index. }
    property GPUDevice;
    { DTW token time stamps preset (wahNone = off). }
    property DtwPreset;
    { Check the record layout against whisper.h on activation. }
    property CheckLayout;
    { Language code or 'auto'. }
    property Language;
    { Translate to English. }
    property Translate;
    { CPU threads (0 = default). }
    property Threads;
    { Greedy or beam search. }
    property Strategy;
    { Beams of the beam search. }
    property BeamSize;
    { Token-level time stamps. }
    property TokenTimestamps;
    { Max segment length in characters (0 = no limit). }
    property MaxSegmentLength;
    { Split on words (with MaxSegmentLength). }
    property SplitOnWord;
    { Initial prompt. }
    property InitialPrompt;
    { Do not use earlier text as prompt. }
    property NoContext;
    { Suppress non-speech tokens. }
    property SuppressNonSpeech;
    { Voice activity detection. }
    property Vad;
    { Silero VAD model file. }
    property VadModelFile;
    { Fill the tokens of each segment. }
    property IncludeTokens;
    { Lowest library log level passed to OnLog. }
    property LogLevel;
    { The model is loaded. }
    property OnLoaded;
    { The library or the model could not be loaded. }
    property OnLoadFailed;
    { The model was unloaded. }
    property OnUnloaded;
    { Change the settings of a run before it starts. }
    property OnBeforeRun;
    { A new segment (main thread). }
    property OnSegment;
    { Progress 0..100 (main thread). }
    property OnProgress;
    { The run finished (main thread). }
    property OnComplete;
    { Log lines (main thread). }
    property OnLog;
  end;

implementation

{ TWhisper }

procedure TWhisper.ShowHandlerException(E: Exception);
begin
  Application.ShowException(E);
end;

end.
