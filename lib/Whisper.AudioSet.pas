(* @abstract(A recording made of many files: an audiobook as one file per
  chapter, several files per chapter, or one file with chapters - read a
  part at a time on one time line.)

  @link(WhisperListAudioFiles) turns what the user names into files: one
  audio file, a folder (every audio file in it, in natural order, so
  "chapter2" comes before "chapter10") or a playlist (.m3u, .m3u8 or a
  plain .txt list; relative paths are relative to the list).

  @link(TWhisperAudioSet) makes the parts: one per file, or one per
  chapter of a file that has chapters (an M4B), and reads them one at a
  time - so memory holds one part, however long the book. WAV files are
  read by Whisper.Audio; everything else through the FFmpegAPI submodule
  (FFmpeg.API, FFmpeg.Media), decoded to 16 kHz mono. Each
  part's place on the joined time line (@link(TWhisperAudioPart.Offset))
  is the sum of the lengths actually decoded before it, so the times of a
  transcription of all parts in order map back exactly to a file and a
  time in that file (what an EPUB's media overlays need).

  Framework-free; compiles with Delphi and FPC. *)
unit Whisper.AudioSet;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes,
  Whisper.Types, Whisper.Audio, Whisper.Core,
  FFmpeg.API, FFmpeg.Media;

type
  { One part of a recording. Times in seconds. }
  TWhisperAudioPart = record
    { The file. }
    FileName: string;
    { The chapter's title, or the file name without folder and extension. }
    Title: string;
    { Start in the file (0 for a whole file). }
    Start: Double;
    { End in the file (0 = to the end of the file). }
    EndTime: Double;
    { Start on the joined time line: the sum of the lengths of the parts
      before it. Exact once the parts before it were read (in order);
      until then estimated from the lengths FFmpeg reports. }
    Offset: Double;
    { Length (estimated until read, then what was decoded). }
    Duration: Double;
    { @true once read. }
    Read: Boolean;
  end;
  { The parts, in order. }
  TWhisperAudioPartArray = array of TWhisperAudioPart;

  { The parts of a recording, read one at a time. }
  TWhisperAudioSet = class
  private
    { FFmpeg (not owned; nil when every file is a WAV). }
    FFFmpeg: TFFmpegLibrary;
    { Backing field of @link(Parts). }
    FParts: TWhisperAudioPartArray;
    { Open FFmpeg file of the part last read (kept while the next part is
      in the same file). }
    FOpen: TFFmpegMediaFile;
    { 16 kHz mono decoder of FOpen. }
    FDecoder: TFFmpegAudioDecoder;
    { Backing field of @link(Files). }
    FFiles: TStringList;
    { Recomputes the offsets of the parts from APart on. }
    procedure Reflow(APart: Integer);
    { Opens AFileName with FFmpeg (EFFmpegError becomes EWhisperError). }
    function OpenMedia(const AFileName: string): TFFmpegMediaFile;
    { Closes the open file and its decoder. }
    procedure CloseMedia;
  public
    { The parts of AFiles, in that order. A file with chapters gives one
      part per chapter when ASplitChapters, else one part.
      @param(AFFmpeg  FFmpeg's libraries (FFmpeg.API), needed for any file
        that is not a .wav (not owned; must outlive the set).)
      @raises(EWhisperError when a file other than a WAV comes with no
        FFmpeg, or cannot be opened.) }
    constructor Create(AFFmpeg: TFFmpegLibrary; AFiles: TStrings; ASplitChapters: Boolean);
    { Closes the open file. }
    destructor Destroy; override;
    { Decodes part AIndex to mono float at WHISPER_SAMPLE_RATE and fixes its
      length and the offsets of the parts after it. }
    function Read(AIndex: Integer): TWhisperSamples;
    { The parts. }
    property Parts: TWhisperAudioPartArray read FParts;
    { The files, in order. }
    property Files: TStringList read FFiles;
  end;

{ The files AName stands for: AName itself when it is an audio file; every
  audio file in it, in natural order, when it is a folder; the files listed
  in it when it is a playlist (.m3u, .m3u8, .txt: one path per line, lines
  starting with '#' ignored, relative paths relative to the list's folder).
  @raises(EWhisperError when AName does not exist or names no audio.) }
function WhisperListAudioFiles(const AName: string): TStringList;

{ True for the extensions read as audio in a folder (.wav, .flac, .ogg,
  .oga, .opus, .mp3, .m4a, .m4b, .aac, .wma, .aif, .aiff, .mka, .webm,
  .aax - read when a tool has decrypted it; a protected one is refused
  with a clear message). }
function WhisperIsAudioFileName(const AFileName: string): Boolean;

{ Compares two file names as people read them, without case: runs of
  digits by value ('chapter2' before 'chapter10'), and English number
  words and Roman numerals as their numbers ('chapterOne', 'ChapterTwo',
  'chapter_three', 'chapter4', 'Part IV', 'Twenty-First') where a word
  starts and ends - 'stone', 'often' and 'oneself' stay words. }
function WhisperNaturalCompare(const A, B: string): Integer;

{ The parts as a JSON array, for "parts" in a transcription's JSON:
  file, title, start and end in the file, offset on the joined time line,
  length (seconds). }
function WhisperAudioPartsToJson(const AParts: TWhisperAudioPartArray): string;

implementation

const
  { Extensions read as audio in a folder. }
  AUDIO_EXTENSIONS: array[0..14] of string = ('.wav', '.flac', '.ogg', '.oga', '.opus', '.mp3', '.m4a',
    '.m4b', '.aac', '.wma', '.aif', '.aiff', '.mka', '.webm', '.aax');

function WhisperIsAudioFileName(const AFileName: string): Boolean;
var
  Ext: string;
  I: Integer;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  for I := Low(AUDIO_EXTENSIONS) to High(AUDIO_EXTENSIONS) do
    if Ext = AUDIO_EXTENSIONS[I] then
      Exit(True);
  Result := False;
end;

{ True for '0'..'9'. }
function IsDigit(C: Char): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

{ True for 'a'..'z' and 'A'..'Z'. }
function IsLetter(C: Char): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'));
end;

{ True for 'A'..'Z'. }
function IsUpper(C: Char): Boolean;
begin
  Result := (C >= 'A') and (C <= 'Z');
end;

const
  { Number words 0..19, for file names like "chapterOne". }
  NUM_UNITS: array[0..19] of string = ('zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
    'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen',
    'eighteen', 'nineteen');
  { Ordinals 0..19 ("Part-First"). }
  NUM_UNIT_ORDINALS: array[0..19] of string = ('zeroth', 'first', 'second', 'third', 'fourth', 'fifth',
    'sixth', 'seventh', 'eighth', 'ninth', 'tenth', 'eleventh', 'twelfth', 'thirteenth', 'fourteenth',
    'fifteenth', 'sixteenth', 'seventeenth', 'eighteenth', 'nineteenth');
  { Tens 20..90. }
  NUM_TENS: array[2..9] of string = ('twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty',
    'ninety');
  { Ordinals of the tens. }
  NUM_TEN_ORDINALS: array[2..9] of string = ('twentieth', 'thirtieth', 'fortieth', 'fiftieth', 'sixtieth',
    'seventieth', 'eightieth', 'ninetieth');

{ Length of the longest of AWords that S has at position AAt (lower case);
  AValue gets its index in AWords (from 0). 0 when none. }
function MatchWord(const S: string; AAt: Integer; const AWords: array of string; out AValue: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  AValue := -1;
  for I := 0 to High(AWords) do
    if (Length(AWords[I]) > Result) and (Copy(S, AAt, Length(AWords[I])) = AWords[I]) then
    begin
      Result := Length(AWords[I]);
      AValue := I;
    end;
end;

{ A number 0..99 in words at position AAt of S (lower case; tens and units
  joined directly or by '-', '_' or ' '): its length, value in AValue; 0
  when there is none. }
function MatchNumber(const S: string; AAt: Integer; out AValue: Integer): Integer;
var
  N, V, P: Integer;
begin
  Result := 0;
  AValue := 0;
  N := MatchWord(S, AAt, NUM_TEN_ORDINALS, V);
  if N > 0 then
  begin
    AValue := (V + 2) * 10;
    Exit(N);
  end;
  N := MatchWord(S, AAt, NUM_TENS, V);
  if N > 0 then
  begin
    AValue := (V + 2) * 10;
    Result := N;
    P := AAt + N;
    if (P <= Length(S)) and CharInSet(S[P], ['-', '_', ' ']) then
      Inc(P);
    N := MatchWord(S, P, NUM_UNIT_ORDINALS, V);
    if N = 0 then
      N := MatchWord(S, P, NUM_UNITS, V);
    if (N > 0) and (V > 0) and (V < 10) then
    begin
      Inc(AValue, V);
      Result := P + N - AAt;
    end;
    Exit;
  end;
  N := MatchWord(S, AAt, NUM_UNIT_ORDINALS, V);
  if N = 0 then
    N := MatchWord(S, AAt, NUM_UNITS, V);
  if N > 0 then
  begin
    AValue := V;
    Result := N;
  end;
end;

{ Value of a Roman numeral made of I, V, X, L and C, 0 if S is not one. }
function RomanValue(const S: string): Integer;
var
  I, V, Next: Integer;

  function Digit(C: Char): Integer;
  begin
    case C of
      'I': Result := 1;
      'V': Result := 5;
      'X': Result := 10;
      'L': Result := 50;
      'C': Result := 100;
    else
      Result := 0;
    end;
  end;

begin
  Result := 0;
  for I := 1 to Length(S) do
  begin
    V := Digit(S[I]);
    if V = 0 then
      Exit(0);
    if I < Length(S) then
      Next := Digit(S[I + 1])
    else
      Next := 0;
    if V < Next then
      Dec(Result, V)
    else
      Inc(Result, V);
  end;
end;

{ The sort key of a file name (without extension): lower case, letters
  and digits only, with numbers written as words
  ("chapterOne", "Chapter_Twenty-One", "part-third") or as an upper-case
  Roman numeral standing alone ("Part IV") turned into digits. A number
  word only counts where a word starts and ends: after a character that is
  not a letter or at a capital in the middle of a word, and before one
  ("stone", "often" and "oneself" stay words). }
function NaturalKey(const AName: string): string;
var
  Lower: string;
  I, N, V, J: Integer;
  AtStart: Boolean;
begin
  Lower := LowerCase(AName);
  Result := '';
  I := 1;
  while I <= Length(AName) do
  begin
    AtStart := IsLetter(AName[I]) and ((I = 1) or not IsLetter(AName[I - 1]) or
      (IsUpper(AName[I]) and not IsUpper(AName[I - 1])));
    if AtStart then
    begin
      // a Roman numeral standing alone
      J := I;
      while (J <= Length(AName)) and IsLetter(AName[J]) do
        Inc(J);
      if (I = 1) or not IsLetter(AName[I - 1]) then
      begin
        V := RomanValue(Copy(AName, I, J - I));
        if V > 0 then
        begin
          Result := Result + IntToStr(V);
          I := J;
          Continue;
        end;
      end;
      N := MatchNumber(Lower, I, V);
      if (N > 0) and ((I + N > Length(AName)) or not IsLetter(AName[I + N]) or IsUpper(AName[I + N])) then
      begin
        Result := Result + IntToStr(V);
        Inc(I, N);
        Continue;
      end;
    end;
    // separators (' ', '_', '-', '.') do not count: "chapter 20" and
    // "chapter20" are the same
    if IsLetter(AName[I]) or IsDigit(AName[I]) or (Ord(AName[I]) > 127) then
      Result := Result + Lower[I];
    Inc(I);
  end;
end;

{ Compares two keys of NaturalKey: runs of digits by value. }
function CompareKeys(const A, B: string): Integer;
var
  I, J, I0, J0: Integer;
  NA, NB: string;
begin
  I := 1;
  J := 1;
  while (I <= Length(A)) and (J <= Length(B)) do
  begin
    if IsDigit(A[I]) and IsDigit(B[J]) then
    begin
      I0 := I;
      while (I <= Length(A)) and IsDigit(A[I]) do
        Inc(I);
      J0 := J;
      while (J <= Length(B)) and IsDigit(B[J]) do
        Inc(J);
      NA := Copy(A, I0, I - I0);
      NB := Copy(B, J0, J - J0);
      while (Length(NA) > 1) and (NA[1] = '0') do
        Delete(NA, 1, 1);
      while (Length(NB) > 1) and (NB[1] = '0') do
        Delete(NB, 1, 1);
      if Length(NA) <> Length(NB) then
        Exit(Length(NA) - Length(NB));
      Result := CompareStr(NA, NB);
      if Result <> 0 then
        Exit;
    end
    else
    begin
      if A[I] <> B[J] then
        Exit(Ord(A[I]) - Ord(B[J]));
      Inc(I);
      Inc(J);
    end;
  end;
  Result := (Length(A) - I) - (Length(B) - J);
end;

function WhisperNaturalCompare(const A, B: string): Integer;
begin
  Result := CompareKeys(NaturalKey(ChangeFileExt(A, '')), NaturalKey(ChangeFileExt(B, '')));
  if Result = 0 then
    Result := CompareStr(A, B);
end;

{ Natural order for TStringList.CustomSort. }
function NaturalListCompare(AList: TStringList; AIndex1, AIndex2: Integer): Integer;
begin
  Result := WhisperNaturalCompare(ExtractFileName(AList[AIndex1]), ExtractFileName(AList[AIndex2]));
end;

function WhisperListAudioFiles(const AName: string): TStringList;
var
  SR: TSearchRec;
  Dir, Line, Ext: string;
  Lines: TStringList;
  I: Integer;
begin
  Result := TStringList.Create;
  try
    if DirectoryExists(AName) then
    begin
      Dir := IncludeTrailingPathDelimiter(AName);
      if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
        try
          repeat
            if (SR.Attr and faDirectory = 0) and WhisperIsAudioFileName(SR.Name) then
              Result.Add(Dir + SR.Name);
          until FindNext(SR) <> 0;
        finally
          FindClose(SR);
        end;
      Result.CustomSort(NaturalListCompare);
    end
    else if not FileExists(AName) then
      raise EWhisperError.CreateFmt('%s: no such file or folder', [AName])
    else
    begin
      Ext := LowerCase(ExtractFileExt(AName));
      if (Ext = '.m3u') or (Ext = '.m3u8') or (Ext = '.txt') then
      begin
        Dir := ExtractFilePath(ExpandFileName(AName));
        Lines := TStringList.Create;
        try
          Lines.Text := WhisperLoadTextFile(AName);
          for I := 0 to Lines.Count - 1 do
          begin
            Line := Trim(Lines[I]);
            if (Line = '') or (Line[1] = '#') then
              Continue;
            if ExtractFileDrive(Line) = '' then
              if (Line[1] <> '/') and (Line[1] <> '\') then
                Line := Dir + Line;
            Result.Add(Line);
          end;
        finally
          Lines.Free;
        end;
      end
      else
        Result.Add(AName);
    end;
    if Result.Count = 0 then
      raise EWhisperError.CreateFmt('%s: no audio files', [AName]);
  except
    Result.Free;
    raise;
  end;
end;

{ JSON string literal of S. }
function JsonText(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '"';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + Format('\u%.4x', [Ord(C)])
      else
        Result := Result + C;
    end;
  end;
  Result := Result + '"';
end;

{ Seconds with three decimals and a full stop, whatever the locale. }
function SecondsText(AValue: Double): string;
begin
  Result := IntToStr(Round(AValue * 1000));
  while Length(Result) < 4 do
    Result := '0' + Result;
  Insert('.', Result, Length(Result) - 2);
end;

function WhisperAudioPartsToJson(const AParts: TWhisperAudioPartArray): string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to High(AParts) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + sLineBreak + Format('    {"file": %s, "title": %s, "start": %s, "end": %s, ' +
      '"offset": %s, "duration": %s}', [JsonText(AParts[I].FileName), JsonText(AParts[I].Title),
      SecondsText(AParts[I].Start), SecondsText(AParts[I].Start + AParts[I].Duration),
      SecondsText(AParts[I].Offset), SecondsText(AParts[I].Duration)]);
  end;
  Result := Result + sLineBreak + '  ]';
end;

{ TWhisperAudioSet }

function TWhisperAudioSet.OpenMedia(const AFileName: string): TFFmpegMediaFile;
begin
  try
    Result := TFFmpegMediaFile.Create(FFFmpeg, AFileName);
  except
    on E: EFFmpegError do
      raise EWhisperError.Create(E.Message);
  end;
end;

procedure TWhisperAudioSet.CloseMedia;
begin
  FreeAndNil(FDecoder);
  FreeAndNil(FOpen);
end;

constructor TWhisperAudioSet.Create(AFFmpeg: TFFmpegLibrary; AFiles: TStrings; ASplitChapters: Boolean);
var
  I, K, N: Integer;
  F: TFFmpegMediaFile;
  IsWav: Boolean;
begin
  inherited Create;
  FFFmpeg := AFFmpeg;
  FFiles := TStringList.Create;
  FFiles.AddStrings(AFiles);
  N := 0;
  for I := 0 to FFiles.Count - 1 do
  begin
    IsWav := SameText(ExtractFileExt(FFiles[I]), '.wav');
    F := nil;
    if (FFFmpeg <> nil) then
      F := OpenMedia(FFiles[I])
    else if not IsWav then
      raise EWhisperError.CreateFmt('%s: FFmpeg is needed for this format', [FFiles[I]]);
    try
      if (F <> nil) and ASplitChapters and (Length(F.Chapters) > 0) then
        for K := 0 to High(F.Chapters) do
        begin
          SetLength(FParts, N + 1);
          FParts[N] := Default(TWhisperAudioPart);
          FParts[N].FileName := FFiles[I];
          FParts[N].Title := F.Chapters[K].Title;
          FParts[N].Start := F.Chapters[K].StartTime;
          FParts[N].EndTime := F.Chapters[K].EndTime;
          FParts[N].Duration := F.Chapters[K].EndTime - F.Chapters[K].StartTime;
          Inc(N);
        end
      else
      begin
        SetLength(FParts, N + 1);
        FParts[N] := Default(TWhisperAudioPart);
        FParts[N].FileName := FFiles[I];
        FParts[N].Title := ChangeFileExt(ExtractFileName(FFiles[I]), '');
        if F <> nil then
          FParts[N].Duration := F.Duration;
        Inc(N);
      end;
    finally
      F.Free;
    end;
  end;
  Reflow(0);
end;

destructor TWhisperAudioSet.Destroy;
begin
  CloseMedia;
  FFiles.Free;
  inherited;
end;

procedure TWhisperAudioSet.Reflow(APart: Integer);
var
  I: Integer;
begin
  for I := APart to High(FParts) do
    if I = 0 then
      FParts[I].Offset := 0
    else
      FParts[I].Offset := FParts[I - 1].Offset + FParts[I - 1].Duration;
end;

function TWhisperAudioSet.Read(AIndex: Integer): TWhisperSamples;
var
  P: TWhisperAudioPart;
begin
  if (AIndex < 0) or (AIndex > High(FParts)) then
    raise EWhisperError.CreateFmt('No audio part %d', [AIndex]);
  P := FParts[AIndex];
  if (FFFmpeg = nil) or (SameText(ExtractFileExt(P.FileName), '.wav') and (P.Start = 0) and (P.EndTime = 0)) then
  begin
    CloseMedia;
    Result := WhisperLoadWav(P.FileName);
  end
  else
  begin
    if (FOpen = nil) or (FOpen.FileName <> P.FileName) then
    begin
      CloseMedia;
      FOpen := OpenMedia(P.FileName);
      try
        FDecoder := TFFmpegAudioDecoder.Create(FOpen, -1, WHISPER_SAMPLE_RATE, 1);
      except
        on E: EFFmpegError do
        begin
          CloseMedia;
          raise EWhisperError.Create(E.Message);
        end;
      end;
    end;
    try
      // TFFmpegSamples and TWhisperSamples are both array of Single
      Result := TWhisperSamples(FDecoder.Read(P.Start, P.EndTime));
    except
      on E: EFFmpegError do
        raise EWhisperError.Create(E.Message);
    end;
  end;
  FParts[AIndex].Duration := WhisperSamplesSeconds(Result);
  FParts[AIndex].Read := True;
  Reflow(AIndex + 1);
end;

end.
