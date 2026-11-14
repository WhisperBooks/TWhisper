{ WhisperConsole - console demo and smoke test of the whisper.cpp binding,
  without the component (TWhisperLib, TWhisperModel, TWhisperParams,
  TWhisperRun directly).

  Usage:
    WhisperConsole <model.bin> <audio> [language] [--translate] [--device NAME] [--tokens]
                   [--words] [--labels FILE] [--json FILE] [--no-dtw] [--no-flash] [--no-context]
                   [--prompt TEXT] [--carry-prompt] [--align BOOK.txt] [--align-labels FILE]
                   [--chapters] [--ffmpeg FOLDER] [--no-fill-gaps]
    WhisperConsole --check            (library + layout check, device list)
    WhisperConsole --bench <model.bin> <audio.wav> [language] [--seconds N|all]
                   [--devices CUDA0,Vulkan0] [--runs N] [--threads N] [--also <model2.bin>]...
                                      (time every model on every device, report the fastest)
  --device / --devices take names from the device list ('CPU', 'CUDA0', 'Vulkan0', ...).
  --seconds: audio per timed run (default 30; 0 or all = the whole file).
  --threads: CPU threads (benchmark CPU device default: every logical processor;
             transcription default: whisper.cpp's, at most 4).
  --runs: timed runs per model and device; the median counts.
  --words: word timings - the model is loaded with DTW (alignment heads from
           the model file, flash attention off) and the words are printed.
  --labels FILE: write the words as an Audacity label track (implies --words):
           in Audacity (3: File > Import > Labels; 4: File > Import), to check by ear.
  --json FILE: write segments and words as JSON (implies --words).
  --no-dtw: word times from whisper.cpp's token time stamps instead of DTW
           (to compare the two).
  --no-flash: flash attention off (DTW turns it off anyway): to tell a
           difference caused by DTW from one caused by the other arithmetic.
  --no-context: do not condition each 30 s window on the text before it
           (OpenAI's condition_on_previous_text = False): stops a mistake
           from repeating window after window, at some cost in consistency.
  --prompt TEXT: initial prompt (vocabulary, names, and the style of the
           text: a punctuated, capitalised prompt keeps the punctuation).
  --carry-prompt: repeat the prompt in every 30 s window (with --no-context
           it keeps the punctuation the windows would otherwise lose).
  --align BOOK.txt: align the words with the text of record (a UTF-8 plain
           text, e.g. a Project Gutenberg .txt; implies --words) and report
           the stretches not spoken, not heard clearly (interpolated) and not heard
           at all (the transcript is silent there: check by ear).
  --align-labels FILE: Audacity labels of the BOOK's words with their times
           (interpolated ones marked '?') and a label at every stretch not
           spoken - to check them by ear (proof-listening).
  <audio>: a file, a folder (every audio file in it, in natural order:
           chapter2 before chapter10) or a playlist (.m3u, .m3u8, .txt).
           .wav files are read directly; anything else (.m4b, .m4a, .mp3,
           .flac, .ogg, .opus, ...) through FFmpeg's shared libraries.
           Several files are transcribed one at a time on one joined time
           line; --json then lists the parts (file, title, offset) and
           --labels writes one label track per file (NAME-01.txt, ...).
  --chapters: also split files with chapters (an M4B) into their chapters:
           one chapter in memory at a time.
  --ffmpeg FOLDER: where FFmpeg's libraries are (default: next to the
           executable, the system search path, then whisper.dll's folder).
  --no-fill-gaps: skip the second pass. By default segments that loop
           (a phrase three times or more) or only repeat the prompt are
           taken out and words stretched over 4 s cut, then every stretch
           of 3 s or more without words that has sound in it (whisper.cpp
           sometimes ends a 30 s window early and skips the rest) is
           transcribed again and put in place; each one is logged.
  An argument starting with '-' that is not an option above is an error (it
  used to be taken as the language).

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
  Whisper.Words,
  Whisper.Align,
  Whisper.FFmpeg,
  Whisper.Core,
  Whisper.AudioSet;

type
  { Event handlers of the run and the library log. }
  TConsoleHandler = class
  public
    { Print the tokens of each segment (--tokens). }
    ShowTokens: Boolean;
    { Added to printed segment times (10 ms units): the start of the
      chapter being transcribed. }
    Offset: Int64;
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
  { Shortest stretch reported by --align, words. }
  ALIGN_REPORT_MIN_WORDS = 3;
  { Most book words quoted per reported stretch. }
  ALIGN_QUOTE_WORDS = 12;
  { The delivery this console comes from (zip number): printed first, so a
    log shows which build made it. Bumped with every zip that changes the
    library or the console. }
  CONSOLE_DELIVERY = 12;
  { Learned habits listed by --align. }
  ALIGN_LEARNED_SHOWN = 20;
  { Marks an interpolated book word in the --align-labels file. }
  INTERPOLATED_MARK = ' ?';

{ Aligns the words of R with the text of ABookFile, prints the figures and
  the stretches not spoken / not heard clearly, and writes the book's words
  as Audacity labels to ALabelsFile (when not ''). }
procedure ReportAlignment(const ABookFile, ALabelsFile: string; const R: TWhisperTranscription);
var
  Book: TWhisperStringArray;
  Aligned: TWhisperAlignedWordArray;
  Stats: TWhisperAlignStats;
  Regions: TWhisperAlignRegionArray;
  Labels: TWhisperWordArray;
  I, K, N: Integer;
  Quote, Where: string;
begin
  Book := WhisperSplitText(WhisperLoadTextFile(ABookFile));
  Aligned := WhisperAlignText(Book, R.Words, Stats);
  WriteLn(Format('Aligned with %s: %d book words - %d exact, %d similar, %d interpolated, %d not spoken, ' +
    '%d not heard, %d moved (reading speed %.2f words/s, %d anchors, %d pass(es), %d stray match(es) dropped)',
    [ABookFile, Stats.BookWords, Stats.Exact, Stats.Similar, Stats.Interpolated, Stats.NotSpoken,
     Stats.NotHeard, Stats.Moved, Stats.WordsPerSecond, Stats.Anchors, Stats.Passes, Stats.Isolated]));
  if Length(Stats.Learned) > 0 then
  begin
    Quote := '';
    for I := 0 to High(Stats.Learned) do
      if I < ALIGN_LEARNED_SHOWN then
        Quote := Quote + IfThen(I > 0, ', ', '') + Stats.Learned[I];
    if Length(Stats.Learned) > ALIGN_LEARNED_SHOWN then
      Quote := Quote + ', ...';
    WriteLn(Format('  learned %d habit(s) of the recogniser (book=heard), %d word(s) paired through them: %s',
      [Length(Stats.Learned), Stats.LearnedWords, Quote]));
  end;
  Regions := WhisperAlignRegions(Aligned, ALIGN_REPORT_MIN_WORDS);
  for I := 0 to High(Regions) do
  begin
    Quote := '';
    for K := Regions[I].First to Regions[I].Last do
      if K - Regions[I].First < ALIGN_QUOTE_WORDS then
        Quote := Quote + ' ' + Book[K];
    if Regions[I].Last - Regions[I].First >= ALIGN_QUOTE_WORDS then
      Quote := Quote + ' ...';
    if Regions[I].Time < 0 then
      Where := 'start'
    else
      Where := WhisperTimeToStr(Regions[I].Time);
    WriteLn(Format('  %s  %s, book words %d-%d:%s', [Where, WhisperAlignMatchName(Regions[I].Match),
      Regions[I].First, Regions[I].Last, Quote]));
  end;
  if ALabelsFile = '' then
    Exit;
  Labels := nil;
  SetLength(Labels, Length(Book) + Length(Regions));
  N := 0;
  for I := 0 to High(Book) do
    if Aligned[I].T0 >= 0 then
    begin
      Labels[N].Text := Book[I];
      if Aligned[I].Match in [wamInterpolated, wamNotHeard] then
        Labels[N].Text := Labels[N].Text + INTERPOLATED_MARK;
      Labels[N].T0 := Aligned[I].T0;
      Labels[N].T1 := Aligned[I].T1;
      Inc(N);
    end;
  for I := 0 to High(Regions) do
    if (Regions[I].Match = wamNotSpoken) and (Regions[I].Time >= 0) then
    begin
      Labels[N].Text := Format('NOT SPOKEN: book words %d-%d', [Regions[I].First, Regions[I].Last]);
      Labels[N].T0 := Regions[I].Time;
      Labels[N].T1 := Regions[I].Time;
      Inc(N);
    end
    else if Regions[I].Match = wamNotHeard then
    begin
      Labels[N].Text := Format('NOT HEARD (check by ear): book words %d-%d', [Regions[I].First,
        Regions[I].Last]);
      Labels[N].T0 := Regions[I].Time;
      Labels[N].T1 := Regions[I].Time;
      Inc(N);
    end;
  SetLength(Labels, N);
  WhisperSaveTextFile(ALabelsFile, WhisperWordsToLabels(Labels));
  WriteLn('Book word labels written to ', ALabelsFile);
end;

{ Loads FFmpeg from AFolder; with AFolder = '' from the executable's folder
  or the system search path, then from whisper.dll's folder AFallback. }
function OpenFFmpeg(const AFolder, AFallback: string): TWhisperFFmpeg;
var
  First: string;
begin
  if AFolder <> '' then
    Exit(TWhisperFFmpeg.Create(AFolder));
  try
    Result := TWhisperFFmpeg.Create('');
  except
    on E: EWhisperError do
    begin
      if AFallback = '' then
        raise;
      First := E.Message;
      try
        Result := TWhisperFFmpeg.Create(AFallback);
      except
        on E2: EWhisperError do
          raise EWhisperError.Create(First + sLineBreak + E2.Message);
      end;
    end;
  end;
end;

{ Takes out loops, prompt echoes and stretched words, runs the second pass
  over the gaps of AResult (ASamples, which start at AOffset s of the
  file) and logs what it did. }
procedure FillAndReport(ARun: TWhisperRun; const ASamples: TWhisperSamples;
  var AResult: TWhisperTranscription; AOffset: Double; const APrompt: string);
var
  Gaps: TWhisperGapArray;
  Clean: TWhisperCleanStats;
  I, Again, Added: Integer;
  Ofs: Int64;
begin
  Clean := WhisperCleanTranscription(AResult, APrompt);
  if Clean.Loops + Clean.PromptEchoes + Clean.LongWords > 0 then
    WriteLn(Format('Cleaned: %d looping segment(s), %d prompt echo(es) taken out, %d stretched word(s) cut',
      [Clean.Loops, Clean.PromptEchoes, Clean.LongWords]));
  Gaps := ARun.FillGaps(ASamples, AResult);
  Ofs := Round(AOffset * WHISPER_TICKS_PER_SECOND);
  Again := 0;
  Added := 0;
  for I := 0 to High(Gaps) do
    if Gaps[I].Transcribed then
    begin
      Inc(Again);
      Inc(Added, Gaps[I].Words);
      WriteLn(Format('  gap %s --> %s (%.1f s, %.0f%% sound): %d word(s) found%s', [WhisperTimeToStr(Gaps[I].T0 + Ofs),
        WhisperTimeToStr(Gaps[I].T1 + Ofs), (Gaps[I].T1 - Gaps[I].T0) / WHISPER_TICKS_PER_SECOND,
        Gaps[I].Voiced * 100, Gaps[I].Words, IfThen(Gaps[I].Retried, ' (tried again without the prompt)', '')]));
    end;
  WriteLn(Format('Second pass: %d gap(s) of 3 s or more, %d with sound transcribed again, %d word(s) added',
    [Length(Gaps), Again, Added]));
end;

{ AJson (WhisperWordsToJson) with the parts of the recording added as
  "parts" (file, title, start and end in the file, offset on the joined
  time line of the words). }
function JsonWithParts(const AJson: string; const AParts: TWhisperAudioPartArray): string;
var
  P: Integer;
begin
  P := LastDelimiter('}', AJson);
  Result := TrimRight(Copy(AJson, 1, P - 1)) + ',' + sLineBreak + '  "parts": ' +
    WhisperAudioPartsToJson(AParts) + sLineBreak + Copy(AJson, P, MaxInt);
end;

{ Writes an Audacity label track per audio file (ABase-01.txt, ...), the
  words' times moved from the joined time line to that file's. }
procedure WriteFileLabels(const ABase: string; ASet: TWhisperAudioSet; const AWords: TWhisperWordArray);
var
  F, I, P, N: Integer;
  Own: TWhisperWordArray;
  Shift: Int64;
  Name: string;
begin
  for F := 0 to ASet.Files.Count - 1 do
  begin
    Own := nil;
    N := 0;
    for I := 0 to High(AWords) do
    begin
      // the part the word starts in
      P := High(ASet.Parts);
      while (P > 0) and (AWords[I].T0 < Round(ASet.Parts[P].Offset * WHISPER_TICKS_PER_SECOND)) do
        Dec(P);
      if ASet.Parts[P].FileName <> ASet.Files[F] then
        Continue;
      Shift := Round((ASet.Parts[P].Start - ASet.Parts[P].Offset) * WHISPER_TICKS_PER_SECOND);
      SetLength(Own, N + 1);
      Own[N] := AWords[I];
      Inc(Own[N].T0, Shift);
      Inc(Own[N].T1, Shift);
      Inc(N);
    end;
    Name := ChangeFileExt(ABase, '') + Format('-%.2d', [F + 1]) + ExtractFileExt(ABase);
    WhisperSaveTextFile(Name, WhisperWordsToLabels(Own));
    WriteLn(Format('Audacity labels of %s written to %s', [ExtractFileName(ASet.Files[F]), Name]));
  end;
end;

{ True when AFileName is read without FFmpeg. }
function IsWav(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.wav');
end;

procedure TConsoleHandler.Segment(Sender: TObject; const ASegment: TWhisperSegment);
var
  I: Integer;
begin
  WriteLn(Format('[%s --> %s] %s', [WhisperTimeToStr(ASegment.T0 + Offset),
    WhisperTimeToStr(ASegment.T1 + Offset), Trim(ASegment.Text)]));
  if ShowTokens then
    for I := 0 to High(ASegment.Tokens) do
      if not ASegment.Tokens[I].Special then
        WriteLn(Format('    token %d %-16s p=%.3f t0=%d t1=%d dtw=%d', [ASegment.Tokens[I].Id,
          '"' + ASegment.Tokens[I].Text + '"', ASegment.Tokens[I].Probability,
          ASegment.Tokens[I].T0, ASegment.Tokens[I].T1, ASegment.Tokens[I].TDtw]));
end;

procedure TConsoleHandler.Progress(Sender: TObject; AProgress: Integer);
begin
  if AProgress mod PROGRESS_STEP = 0 then
  begin
    // both streams are buffered when redirected: flush them so a log of
    // both keeps the order
    Flush(Output);
    WriteLn(ErrOutput, Format('progress %d%%', [AProgress]));
    Flush(ErrOutput);
  end;
end;

procedure TConsoleHandler.Log(Sender: TObject; ALevel: TWhisperLogLevel; const AText: string);
begin
  if ALevel in [wllWarn, wllError] then
  begin
    Flush(Output);
    WriteLn(ErrOutput, 'whisper: ' + AText);
    Flush(ErrOutput);
  end;
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
  ModelFile, AudioFile, Lang, Arg, DeviceName, LabelsFile, JsonFile: string;
  AlignFile, AlignLabels, Prompt: string;
  CheckOnly, Translate, Tokens, LayoutOk, Bench, WantWords, NoDtw, NoFlash, NoContext: Boolean;
  CarryPrompt: Boolean;
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
  FFmpegFolder: string;
  ByChapter, FillGaps: Boolean;
  FF: TWhisperFFmpeg;
  AudioIn: TWhisperAudioSet;
  AudioFiles: TStringList;
  NeedFF: Boolean;
  PartTitle: string;
  Part: TWhisperTranscription;
begin
  ExitCode := 1;
  WriteLn(Format('WhisperConsole, TWhisper delivery %d', [CONSOLE_DELIVERY]));
  ExtraModels := nil;
  Handler := TConsoleHandler.Create;
  try
    try
      CheckOnly := False;
      Translate := False;
      Tokens := False;
      WantWords := False;
      NoDtw := False;
      NoFlash := False;
      NoContext := False;
      CarryPrompt := False;
      AlignFile := '';
      AlignLabels := '';
      Prompt := '';
      LabelsFile := '';
      JsonFile := '';
      Bench := False;
      BenchSeconds := WHISPER_CHUNK_SIZE;
      DeviceName := '';
      DeviceList := '';
      Threads := 0;
      Runs := 1;
      ExtraModels := TStringList.Create;
      FFmpegFolder := '';
      ByChapter := False;
      FillGaps := True;
      FF := nil;
      AudioIn := nil;
      AudioFiles := nil;
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
        else if Arg = '--words' then
          WantWords := True
        else if Arg = '--no-dtw' then
          NoDtw := True
        else if Arg = '--no-flash' then
          NoFlash := True
        else if Arg = '--no-context' then
          NoContext := True
        else if Arg = '--carry-prompt' then
          CarryPrompt := True
        else if Arg = '--chapters' then
          ByChapter := True
        else if Arg = '--no-fill-gaps' then
          FillGaps := False
        else if (Arg = '--ffmpeg') and (I <= ParamCount) then
        begin
          FFmpegFolder := ParamStr(I);
          Inc(I);
        end
        else if (Arg = '--prompt') and (I <= ParamCount) then
        begin
          Prompt := ParamStr(I);
          Inc(I);
        end
        else if (Arg = '--align') and (I <= ParamCount) then
        begin
          AlignFile := ParamStr(I);
          WantWords := True;
          Inc(I);
        end
        else if (Arg = '--align-labels') and (I <= ParamCount) then
        begin
          AlignLabels := ParamStr(I);
          Inc(I);
        end
        else if (Arg = '--labels') and (I <= ParamCount) then
        begin
          LabelsFile := ParamStr(I);
          WantWords := True;
          Inc(I);
        end
        else if (Arg = '--json') and (I <= ParamCount) then
        begin
          JsonFile := ParamStr(I);
          WantWords := True;
          Inc(I);
        end
        else if (Length(Arg) > 1) and (Arg[1] = '-') then
        begin
          WriteLn(ErrOutput, 'Unknown option ', Arg, ' (run without arguments for the usage)');
          Exit;
        end
        else if ModelFile = '' then
          ModelFile := Arg
        else if AudioFile = '' then
          AudioFile := Arg
        else
          Lang := Arg;
      end;
      if not CheckOnly and ((ModelFile = '') or (AudioFile = '')) then
      begin
        WriteLn('Usage: WhisperConsole <model.bin> <audio> [language] [--translate] [--device NAME] [--tokens]');
        WriteLn('                      [--words] [--labels FILE] [--json FILE] [--no-dtw] [--no-flash] [--no-context]');
        WriteLn('                      [--prompt TEXT] [--carry-prompt] [--align BOOK.txt] [--align-labels FILE]');
        WriteLn('                      [--chapters] [--ffmpeg FOLDER] [--no-fill-gaps]');
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
      if not CheckOnly then
      begin
        // a file, a folder of files or a playlist
        AudioFiles := WhisperListAudioFiles(AudioFile);
        NeedFF := ByChapter or (FFmpegFolder <> '');
        for I := 0 to AudioFiles.Count - 1 do
          if not IsWav(AudioFiles[I]) then
            NeedFF := True;
        if NeedFF or (AudioFiles.Count > 1) then
        begin
          if NeedFF then
          begin
            FF := OpenFFmpeg(FFmpegFolder, Lib.LibraryFolder);
            WriteLn(FF.Description);
          end;
          // one part per file, or per chapter of a file with --chapters
          AudioIn := TWhisperAudioSet.Create(FF, AudioFiles, ByChapter);
          WriteLn(Format('Audio %s: %d file(s), %d part(s), about %.2f s', [AudioFile, AudioFiles.Count,
            Length(AudioIn.Parts), AudioIn.Parts[High(AudioIn.Parts)].Offset +
            AudioIn.Parts[High(AudioIn.Parts)].Duration]));
          for I := 0 to High(AudioIn.Parts) do
            WriteLn(Format('  part %d  %s --> %s  %s  (%s)', [I + 1,
              WhisperTimeToStr(Round(AudioIn.Parts[I].Offset * 100)),
              WhisperTimeToStr(Round((AudioIn.Parts[I].Offset + AudioIn.Parts[I].Duration) * 100)),
              AudioIn.Parts[I].Title, ExtractFileName(AudioIn.Parts[I].FileName)]));
        end;
      end;
      if Bench then
      begin
        Lib.AddLogListener(Handler.Log);
        ReadStart := Now;
        if AudioIn <> nil then
        begin
          Samples := AudioIn.Read(0);
          WriteLn(Format('Audio %s, part 1: %d samples at %d Hz, decoded in %d ms', [AudioFile, Length(Samples),
            WHISPER_SAMPLE_RATE, MilliSecondsBetween(Now, ReadStart)]));
        end
        else
        begin
          Samples := WhisperLoadWav(AudioFiles[0], Info);
          WriteLn(Format('Audio %s: %d channel(s), %d Hz, %d bits -> %d samples at %d Hz, read in %d ms',
            [AudioFile, Info.Channels, Info.SampleRate, Info.BitsPerSample, Length(Samples), WHISPER_SAMPLE_RATE,
             MilliSecondsBetween(Now, ReadStart)]));
        end;
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
      if NoFlash then
        CP.flash_attn := False;
      if WantWords and not NoDtw and not WhisperEnableDtw(ModelFile, CP) then
        WriteLn(ErrOutput, 'Cannot read the model header for the DTW alignment heads: ',
          'word times come from token time stamps');
      Model := TWhisperModel.Create(ModelFile, CP);
      try
        WriteLn(Format('Model %s on %s: %s', [ModelFile, IfThen(DeviceName = '', 'the default device',
          DeviceName), Model.Description]));
        Samples := nil;
        if AudioIn = nil then
        begin
          // one WAV file: read directly
          ReadStart := Now;
          Samples := WhisperLoadWav(AudioFiles[0], Info);
          WriteLn(Format('Audio %s: %d channel(s), %d Hz, %d bits, %d frames -> %d samples (%.2f s), read in %d ms',
            [AudioFiles[0], Info.Channels, Info.SampleRate, Info.BitsPerSample, Info.Frames,
             Length(Samples), WhisperSamplesSeconds(Samples), MilliSecondsBetween(Now, ReadStart)]));
        end;
        Params := TWhisperParams.Create;
        Run := TWhisperRun.Create(Model, Params);
        try
          Params.Language := Lang;
          Params.Translate := Translate;
          if Threads > 0 then
            Params.Threads := Threads;
          Params.TokenTimestamps := Tokens;
          Params.NoContext := NoContext;
          Params.InitialPrompt := Prompt;
          Params.CarryInitialPrompt := CarryPrompt;
          if NoContext then
            Params.MaxTextContext := 0;   // no_context alone only drops an earlier run's text
          Run.IncludeTokens := Tokens;
          Run.IncludeWords := WantWords;
          Handler.ShowTokens := Tokens;
          Run.OnSegment := Handler.Segment;
          Run.OnProgress := Handler.Progress;
          WriteLn(Format('Transcribing: language %s, %d threads, %s, flash attention %s, ' +
            'previous text as context %s', [Params.Language, Params.Threads,
            IfThen(Translate, 'translate to English', 'transcribe'), BoolToStr(CP.flash_attn, True),
            BoolToStr(Params.MaxTextContext > 0, True) +
            IfThen((Params.MaxTextContext = 0) and CarryPrompt and (Prompt <> ''), ', initial prompt in every window', '')]));
          if AudioIn <> nil then
          begin
            // part by part, on the joined time line
            R := Default(TWhisperTranscription);
            for I := 0 to High(AudioIn.Parts) do
            begin
              PartTitle := AudioIn.Parts[I].Title;
              ReadStart := Now;
              Samples := AudioIn.Read(I);
              WriteLn(Format('Part %d of %d "%s" (%s at %s): %.2f s decoded in %d ms', [I + 1,
                Length(AudioIn.Parts), PartTitle, ExtractFileName(AudioIn.Parts[I].FileName),
                WhisperTimeToStr(Round(AudioIn.Parts[I].Offset * 100)), WhisperSamplesSeconds(Samples),
                MilliSecondsBetween(Now, ReadStart)]));
              if Length(Samples) = 0 then
                Continue;
              Handler.Offset := Round(AudioIn.Parts[I].Offset * 100);
              Part := Run.Execute(Samples);
              if FillGaps and (Part.ResultCode = 0) and not Part.Cancelled then
                FillAndReport(Run, Samples, Part, AudioIn.Parts[I].Offset, Prompt);
              WhisperAppendTranscription(R, Part, AudioIn.Parts[I].Offset);
              // Keep the language the first chapter was heard in.
              if SameText(Params.Language, WHISPER_LANGUAGE_AUTO) and (Part.LanguageCode <> '') then
                Params.Language := Part.LanguageCode;
              if (Part.ResultCode <> 0) or Part.Cancelled then
                Break;
            end;
            Handler.Offset := 0;
          end
          else
          begin
            R := Run.Execute(Samples);
            if FillGaps and (R.ResultCode = 0) and not R.Cancelled then
              FillAndReport(Run, Samples, R, 0, Prompt);
          end;
          WriteLn(Format('Result %d (%s): %d segment(s), language %s (%s), %.2f s of audio in %d ms',
            [R.ResultCode, WhisperResultText(R.ResultCode), Length(R.Segments), R.LanguageCode,
             R.LanguageName, R.AudioSeconds, R.ElapsedMs]));
          if WantWords then
          begin
            WriteLn(Format('%d word(s), timing: %s', [Length(R.Words), WhisperWordTimingName(R.WordTiming)]));
            if (LabelsFile = '') and (JsonFile = '') and (AlignFile = '') then
              for I := 0 to High(R.Words) do
                WriteLn(Format('  [%s --> %s] p=%.3f  %s', [WhisperTimeToStr(R.Words[I].T0),
                  WhisperTimeToStr(R.Words[I].T1), R.Words[I].Probability, R.Words[I].Text]));
            if LabelsFile <> '' then
            begin
              if (AudioIn <> nil) and (AudioIn.Files.Count > 1) then
                WriteFileLabels(LabelsFile, AudioIn, R.Words)
              else
              begin
                // one file: its own time line (a chapter's start included)
                WhisperSaveTextFile(LabelsFile, WhisperWordsToLabels(R.Words));
                WriteLn('Audacity labels written to ', LabelsFile);
              end;
            end;
            if JsonFile <> '' then
            begin
              if AudioIn <> nil then
                WhisperSaveTextFile(JsonFile, JsonWithParts(WhisperWordsToJson(R), AudioIn.Parts))
              else
                WhisperSaveTextFile(JsonFile, WhisperWordsToJson(R));
              WriteLn('JSON written to ', JsonFile);
            end;
            if AlignFile <> '' then
              ReportAlignment(AlignFile, AlignLabels, R);
          end;
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
    AudioIn.Free;
    AudioFiles.Free;
    FF.Free;
    ExtraModels.Free;
    if TWhisperLib.IsLoaded then
      TWhisperLib.Instance.RemoveLogListener(Handler.Log);
    Handler.Free;
  end;
end.
