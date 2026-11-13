{ WhisperConsole - console demo and smoke test of the whisper.cpp binding,
  without the component (TWhisperLib, TWhisperModel, TWhisperParams,
  TWhisperRun directly).

  Usage:
    WhisperConsole <model.bin> <audio.wav> [language] [--translate] [--cpu] [--tokens]
    WhisperConsole --check            (library + layout check only)

  It logs every step with its values: library file and version, system info,
  the layout check, the model, the audio as read, each segment as it
  arrives, and the result. Run it first on a new platform: a wrong record
  layout or calling convention shows up here before any GUI is involved. }
program WhisperConsole;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  Whisper.Types in '..\..\lib\Whisper.Types.pas',
  Whisper.DynLib in '..\..\lib\Whisper.DynLib.pas',
  Whisper.API in '..\..\lib\Whisper.API.pas',
  Whisper.Audio in '..\..\lib\Whisper.Audio.pas',
  Whisper.Core in '..\..\lib\Whisper.Core.pas';

type
  { Event handlers of the run and the library log. }
  TConsoleHandler = class
  public
    { Prints a segment as it arrives. }
    procedure Segment(Sender: TObject; const ASegment: TWhisperSegment);
    { Prints the progress in steps. }
    procedure Progress(Sender: TObject; AProgress: Integer);
    { Prints warnings and errors of the library. }
    procedure Log(Sender: TObject; ALevel: TWhisperLogLevel; const AText: string);
  end;

const
  { Progress is printed every this many percent. }
  PROGRESS_STEP = 10;

procedure TConsoleHandler.Segment(Sender: TObject; const ASegment: TWhisperSegment);
var
  I: Integer;
begin
  WriteLn(Format('[%s --> %s] %s', [WhisperTimeToStr(ASegment.T0), WhisperTimeToStr(ASegment.T1),
    Trim(ASegment.Text)]));
  for I := 0 to High(ASegment.Tokens) do
    if not ASegment.Tokens[I].Special then
      WriteLn(Format('    token %d %-16s p=%.3f t0=%d t1=%d dtw=%d', [ASegment.Tokens[I].Id,
        '"' + ASegment.Tokens[I].Text + '"', ASegment.Tokens[I].Probability,
        ASegment.Tokens[I].T0, ASegment.Tokens[I].T1, ASegment.Tokens[I].TDtw]));
end;

procedure TConsoleHandler.Progress(Sender: TObject; AProgress: Integer);
begin
  if AProgress mod PROGRESS_STEP = 0 then
    WriteLn(ErrOutput, Format('progress %d%%', [AProgress]));
end;

procedure TConsoleHandler.Log(Sender: TObject; ALevel: TWhisperLogLevel; const AText: string);
begin
  if ALevel in [wllWarn, wllError] then
    WriteLn(ErrOutput, 'whisper: ' + AText);
end;

var
  Handler: TConsoleHandler;
  Lib: TWhisperLib;
  Report: TStringList;
  Model: TWhisperModel;
  Params: TWhisperParams;
  Run: TWhisperRun;
  CP: TWhisperContextParams;
  Info: TWhisperWavInfo;
  Samples: TWhisperSamples;
  R: TWhisperTranscription;
  ModelFile, AudioFile, Lang, Arg: string;
  CheckOnly, Translate, UseGPU, Tokens, LayoutOk: Boolean;
  I: Integer;
begin
  ExitCode := 1;
  Handler := TConsoleHandler.Create;
  try
    try
      CheckOnly := False;
      Translate := False;
      UseGPU := True;
      Tokens := False;
      ModelFile := '';
      AudioFile := '';
      Lang := WHISPER_LANGUAGE_AUTO;
      for I := 1 to ParamCount do
      begin
        Arg := ParamStr(I);
        if Arg = '--check' then
          CheckOnly := True
        else if Arg = '--translate' then
          Translate := True
        else if Arg = '--cpu' then
          UseGPU := False
        else if Arg = '--tokens' then
          Tokens := True
        else if ModelFile = '' then
          ModelFile := Arg
        else if AudioFile = '' then
          AudioFile := Arg
        else
          Lang := Arg;
      end;
      if not CheckOnly and ((ModelFile = '') or (AudioFile = '')) then
      begin
        WriteLn('Usage: WhisperConsole <model.bin> <audio.wav> [language] [--translate] [--cpu] [--tokens]');
        WriteLn('       WhisperConsole --check');
        Exit;
      end;

      Lib := TWhisperLib.Load;
      for I := 0 to Lib.LoadLog.Count - 1 do
        WriteLn(Lib.LoadLog[I]);
      WriteLn(Format('whisper.cpp %s (binding checked against %s)', [Lib.Version, WHISPER_BINDING_VERSION]));
      WriteLn('System info: ', Lib.SystemInfo);
      WriteLn(Format('Languages: %d (%s ... %s)', [Lib.LanguageCount, Lib.LanguageCode(0),
        Lib.LanguageCode(Lib.LanguageCount - 1)]));
      Report := TStringList.Create;
      try
        LayoutOk := Lib.CheckLayout(Report);
        for I := 0 to Report.Count - 1 do
          WriteLn(Report[I]);
      finally
        Report.Free;
      end;
      if not LayoutOk then
        Exit;
      if CheckOnly then
      begin
        ExitCode := 0;
        Exit;
      end;
      Lib.AddLogListener(Handler.Log);

      CP := Lib.DefaultContextParams;
      CP.use_gpu := UseGPU;
      Model := TWhisperModel.Create(ModelFile, CP);
      try
        WriteLn(Format('Model %s: %s', [ModelFile, Model.Description]));
        Samples := WhisperLoadWav(AudioFile, Info);
        WriteLn(Format('Audio %s: %d channel(s), %d Hz, %d bits, %d frames -> %d samples (%.2f s)',
          [AudioFile, Info.Channels, Info.SampleRate, Info.BitsPerSample, Info.Frames,
           Length(Samples), WhisperSamplesSeconds(Samples)]));
        Params := TWhisperParams.Create;
        Run := TWhisperRun.Create(Model, Params);
        try
          Params.Language := Lang;
          Params.Translate := Translate;
          Params.TokenTimestamps := Tokens;
          Run.IncludeTokens := Tokens;
          Run.OnSegment := Handler.Segment;
          Run.OnProgress := Handler.Progress;
          WriteLn(Format('Transcribing: language %s, %d threads, %s', [Params.Language, Params.Threads,
            BoolToStr(Translate, True)]));
          R := Run.Execute(Samples);
          WriteLn(Format('Result %d (%s): %d segment(s), language %s (%s), %.2f s of audio in %d ms',
            [R.ResultCode, WhisperResultText(R.ResultCode), Length(R.Segments), R.LanguageCode,
             R.LanguageName, R.AudioSeconds, R.ElapsedMs]));
          Lib.RemoveLogListener(Handler.Log);   // timings go to stderr
          if Assigned(Lib.Flat.whisper_print_timings) then
            Lib.Flat.whisper_print_timings(Model.Handle);
          if R.ResultCode = 0 then
            ExitCode := 0;
        finally
          Run.Free;
          Params.Free;
        end;
      finally
        Model.Free;
      end;
    except
      on E: Exception do
        WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
    end;
  finally
    if TWhisperLib.IsLoaded then
      TWhisperLib.Instance.RemoveLogListener(Handler.Log);
    Handler.Free;
  end;
end.
