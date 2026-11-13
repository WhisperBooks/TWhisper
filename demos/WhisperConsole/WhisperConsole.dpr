{ WhisperConsole - console demo and smoke test of the whisper.cpp binding,
  without the component (TWhisperLib, TWhisperModel, TWhisperParams,
  TWhisperRun directly).

  Usage:
    WhisperConsole <model.bin> <audio.wav> [language] [--translate] [--device NAME] [--tokens]
    WhisperConsole --check            (library + layout check, device list)
    WhisperConsole --bench <model.bin> <audio.wav> [language] [--seconds N|all]
                   [--devices CUDA0,Vulkan0] [--runs N] [--threads N] [--also <model2.bin>]...
                                      (time every model on every device, report the fastest)
  --device / --devices take names from the device list ('CPU', 'CUDA0', 'Vulkan0', ...).
  --seconds: audio per timed run (default 30; 0 or all = the whole file).
  --threads: CPU threads (benchmark CPU device default: every logical processor;
             transcription default: whisper.cpp's, at most 4).
  --runs: timed runs per model and device; the median counts.

  It logs every step with its values: library file and version, system info,
  the layout check, the model, the audio as read, each segment as it
  arrives, and the result. Run it first on a new platform: a wrong record
  layout or calling convention shows up here before any GUI is involved.

  Like any user project it lists only its own sources: the library comes
  from the runtime package WhisperAPI (Delphi's Dcp folder) - build it first. }
program WhisperConsole;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  StrUtils,
  DateUtils,
  // the library: DCUs of the runtime package WhisperAPI (Delphi's Dcp folder)
  Whisper.Types,
  Whisper.API,
  Whisper.Audio,
  Whisper.Core;

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
    { Prints the model and device a benchmark is about to time. }
    procedure BenchDevice(Sender: TObject; const AModelFile: string; const ADevice: TWhisperDevice);
    { Prints one benchmark result. }
    procedure BenchResult(Sender: TObject; const AResult: TWhisperBenchmarkResult);
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

procedure TConsoleHandler.BenchDevice(Sender: TObject; const AModelFile: string;
  const ADevice: TWhisperDevice);
begin
  WriteLn('Timing ', ExtractFileName(AModelFile), ' on ', WhisperDeviceText(ADevice), ' ...');
end;

procedure TConsoleHandler.BenchResult(Sender: TObject; const AResult: TWhisperBenchmarkResult);
begin
  if AResult.Ok then
    WriteLn(Format('  %s on %s: %.2fx real time (load %d ms, warm-up %d ms, %.1f s of audio in %d ms%s, %d threads)',
      [ExtractFileName(AResult.ModelFile), AResult.Device.Name, AResult.Speed, AResult.LoadMs, AResult.WarmupMs,
       AResult.AudioSeconds, AResult.RunMs, IfThen(AResult.Runs > 1, Format(' - median of %d runs', [AResult.Runs]), ''),
       AResult.Threads]), sLineBreak, '    "', Copy(AResult.Text, 1, 100), '"')
  else
    WriteLn(Format('  %s on %s FAILED: %s', [ExtractFileName(AResult.ModelFile), AResult.Device.Name,
      AResult.ErrorMessage]));
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
  ModelFile, AudioFile, Lang, Arg, DeviceName: string;
  CheckOnly, Translate, Tokens, LayoutOk, Bench: Boolean;
  BenchSeconds: Double;
  BenchDevices, Threads, Runs: Integer;
  DeviceList: string;
  Picked: TWhisperDeviceArray;
  Names: TStringList;
  Devs: TWhisperDeviceArray;
  Benchmark: TWhisperBenchmark;
  BenchResults: TWhisperBenchmarkArray;
  Best: Integer;
  ExtraModels: TStringList;
  ReadStart: TDateTime;
  I: Integer;
begin
  ExitCode := 1;
  ExtraModels := nil;
  Handler := TConsoleHandler.Create;
  try
    try
      CheckOnly := False;
      Translate := False;
      Tokens := False;
      Bench := False;
      BenchSeconds := WHISPER_CHUNK_SIZE;
      DeviceName := '';
      DeviceList := '';
      Threads := 0;
      Runs := 1;
      ExtraModels := TStringList.Create;
      ModelFile := '';
      AudioFile := '';
      Lang := WHISPER_LANGUAGE_AUTO;
      I := 1;
      while I <= ParamCount do
      begin
        Arg := ParamStr(I);
        Inc(I);
        if Arg = '--check' then
          CheckOnly := True
        else if Arg = '--translate' then
          Translate := True
        else if Arg = '--bench' then
          Bench := True
        else if (Arg = '--device') and (I <= ParamCount) then
        begin
          DeviceName := ParamStr(I);
          Inc(I);
        end
        else if (Arg = '--also') and (I <= ParamCount) then
        begin
          ExtraModels.Add(ParamStr(I));
          Inc(I);
        end
        else if (Arg = '--seconds') and (I <= ParamCount) then
        begin
          if SameText(ParamStr(I), 'all') then
            BenchSeconds := 0
          else
            BenchSeconds := StrToFloat(ParamStr(I));
          Inc(I);
        end
        else if (Arg = '--devices') and (I <= ParamCount) then
        begin
          DeviceList := ParamStr(I);
          Inc(I);
        end
        else if (Arg = '--threads') and (I <= ParamCount) then
        begin
          Threads := StrToInt(ParamStr(I));
          Inc(I);
        end
        else if (Arg = '--runs') and (I <= ParamCount) then
        begin
          Runs := StrToInt(ParamStr(I));
          Inc(I);
        end
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
        WriteLn('Usage: WhisperConsole <model.bin> <audio.wav> [language] [--translate] [--device NAME] [--tokens]');
        WriteLn('       WhisperConsole --check');
        WriteLn('       WhisperConsole --bench <model.bin> <audio.wav> [language] [--seconds N|all] [--devices A,B]');
        WriteLn('                      [--runs N] [--threads N] [--also <model2.bin>]...');
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
      Devs := Lib.SelectableDevices;
      WriteLn(Format('Selectable devices: %d', [Length(Devs)]));
      for I := 0 to High(Devs) do
        WriteLn(Format('  %s  (whisper gpu_device %d)', [WhisperDeviceText(Devs[I]), Devs[I].GpuIndex]));
      if not LayoutOk then
        Exit;
      if Bench then
      begin
        Lib.AddLogListener(Handler.Log);
        ReadStart := Now;
        Samples := WhisperLoadWav(AudioFile, Info);
        WriteLn(Format('Audio %s: %d channel(s), %d Hz, %d bits -> %d samples at %d Hz, read in %d ms',
          [AudioFile, Info.Channels, Info.SampleRate, Info.BitsPerSample, Length(Samples), WHISPER_SAMPLE_RATE,
           MilliSecondsBetween(Now, ReadStart)]));
        Benchmark := TWhisperBenchmark.Create(ModelFile, Samples);
        Params := TWhisperParams.Create;
        try
          Params.Language := Lang;
          Benchmark.Params := Params;
          Benchmark.ModelFiles.AddStrings(ExtraModels);
          Benchmark.MaxSeconds := BenchSeconds;
          Benchmark.CpuThreads := Threads;
          Benchmark.Runs := Runs;
          // --devices: only the named ones, in the order given
          Picked := nil;
          if DeviceList <> '' then
          begin
            Names := TStringList.Create;
            try
              Names.CommaText := DeviceList;
              for BenchDevices := 0 to Names.Count - 1 do
              begin
                SetLength(Picked, Length(Picked) + 1);
                if not Lib.FindDevice(Trim(Names[BenchDevices]), Picked[High(Picked)]) then
                begin
                  WriteLn(ErrOutput, 'Unknown device ', Names[BenchDevices], ' (see the device list above)');
                  Exit;
                end;
              end;
            finally
              Names.Free;
            end;
          end;
          WriteLn(Format('Audio %s: %.1f s; timing %s per model and device', [AudioFile,
            WhisperSamplesSeconds(Samples), IfThen(BenchSeconds <= 0, 'all of it',
            Format('the first %.0f s', [BenchSeconds]))]));
          Benchmark.OnStart := Handler.BenchDevice;
          Benchmark.OnResult := Handler.BenchResult;
          BenchResults := Benchmark.Run(Picked);
          Best := TWhisperBenchmark.Best(BenchResults);
          for I := 0 to Benchmark.ModelFiles.Count - 1 do
            if TWhisperBenchmark.Best(BenchResults, Benchmark.ModelFiles[I]) >= 0 then
              WriteLn(Format('Fastest for %s: %s', [ExtractFileName(Benchmark.ModelFiles[I]),
                BenchResults[TWhisperBenchmark.Best(BenchResults, Benchmark.ModelFiles[I])].Device.Name]));
          if Best >= 0 then
          begin
            WriteLn(Format('Fastest overall: %s on %s (%.2fx real time) - use --device %s',
              [ExtractFileName(BenchResults[Best].ModelFile), BenchResults[Best].Device.Name,
               BenchResults[Best].Speed, BenchResults[Best].Device.Name]));
            ExitCode := 0;
          end
          else
            WriteLn('No device succeeded');
        finally
          Params.Free;
          Benchmark.Free;
        end;
        Exit;
      end;
      if CheckOnly then
      begin
        ExitCode := 0;
        Exit;
      end;
      Lib.AddLogListener(Handler.Log);

      CP := Lib.DefaultContextParams;
      if not Lib.ContextParamsFor(DeviceName, CP) then
      begin
        WriteLn(ErrOutput, 'Unknown device ', DeviceName, ' (see the device list above)');
        Exit;
      end;
      Model := TWhisperModel.Create(ModelFile, CP);
      try
        WriteLn(Format('Model %s on %s: %s', [ModelFile, IfThen(DeviceName = '', 'the default device',
          DeviceName), Model.Description]));
        ReadStart := Now;
        Samples := WhisperLoadWav(AudioFile, Info);
        WriteLn(Format('Audio %s: %d channel(s), %d Hz, %d bits, %d frames -> %d samples (%.2f s), read in %d ms',
          [AudioFile, Info.Channels, Info.SampleRate, Info.BitsPerSample, Info.Frames,
           Length(Samples), WhisperSamplesSeconds(Samples), MilliSecondsBetween(Now, ReadStart)]));
        Params := TWhisperParams.Create;
        Run := TWhisperRun.Create(Model, Params);
        try
          Params.Language := Lang;
          Params.Translate := Translate;
          if Threads > 0 then
            Params.Threads := Threads;
          Params.TokenTimestamps := Tokens;
          Run.IncludeTokens := Tokens;
          Run.OnSegment := Handler.Segment;
          Run.OnProgress := Handler.Progress;
          WriteLn(Format('Transcribing: language %s, %d threads, %s', [Params.Language, Params.Threads,
            IfThen(Translate, 'translate to English', 'transcribe')]));
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
    ExtraModels.Free;
    if TWhisperLib.IsLoaded then
      TWhisperLib.Instance.RemoveLogListener(Handler.Log);
    Handler.Free;
  end;
end.
