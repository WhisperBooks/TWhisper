(* @abstract(Audio input for whisper.cpp: WAV files to 16 kHz mono float,
  sample conversion and resampling.)

  whisper.cpp takes mono 32-bit float samples at
  @code(WHISPER_SAMPLE_RATE) (16 kHz). @link(WhisperLoadWav) reads RIFF WAVE
  files in every common encoding (PCM 8 / 16 / 24 / 32-bit, IEEE float
  32 / 64-bit, WAVE_FORMAT_EXTENSIBLE), any channel count and any sample
  rate, mixes down to mono and resamples with a windowed-sinc filter.
  Compressed formats (MP3, AAC, Opus, ...) are not decoded: convert them first,
  e.g. @code(ffmpeg -i in.mp3 -ar 16000 -ac 1 -c:a pcm_s16le out.wav).

  Framework-free; compiles with Delphi and FPC. *)
unit Whisper.Audio;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes, Math,
  Whisper.Types;

type
  { Encoding of the samples in a WAV file. }
  TWhisperWavEncoding = (
    { Integer PCM (WAVE_FORMAT_PCM): 8-bit unsigned, 16 / 24 / 32-bit signed. }
    wweInteger,
    { IEEE float (WAVE_FORMAT_IEEE_FLOAT): 32 or 64-bit. }
    wweFloat
  );

  { What a WAV file holds (from its fmt chunk). }
  TWhisperWavInfo = record
    { Sample encoding. }
    Encoding: TWhisperWavEncoding;
    { Channels. }
    Channels: Integer;
    { Frames per second. }
    SampleRate: Integer;
    { Bits per sample (container size). }
    BitsPerSample: Integer;
    { Frames in the data chunk. }
    Frames: Int64;
  end;

{ Reads a WAV file and converts it for whisper.cpp.
  @param(AFileName  The .wav file.)
  @param(AInfo  Receives what the file held.)
  @returns(Mono samples at WHISPER_SAMPLE_RATE.)
  @raises(EWhisperError when the file is not a WAV file or uses an
    unsupported encoding.) }
function WhisperLoadWav(const AFileName: string; out AInfo: TWhisperWavInfo): TWhisperSamples; overload;

{ Reads a WAV file and converts it for whisper.cpp (see the other overload). }
function WhisperLoadWav(const AFileName: string): TWhisperSamples; overload;

{ Reads WAV data from a stream (from its current position) and converts it
  for whisper.cpp.
  @raises(EWhisperError when the data is not WAV or unsupported.) }
function WhisperLoadWavStream(AStream: TStream; out AInfo: TWhisperWavInfo): TWhisperSamples;

{ Converts interleaved 16-bit PCM to mono float (channels averaged), at the
  same rate. Handy for audio captured from a device.
  @param(AData  First sample.)
  @param(AFrames  Frames (samples per channel).)
  @param(AChannels  Interleaved channels.) }
function WhisperPcm16ToMono(AData: PSmallInt; AFrames: Integer; AChannels: Integer): TWhisperSamples;

{ Resamples mono audio with a windowed-sinc filter (low-pass when the
  rate goes down, so no aliasing).
  @param(ASamples  Input samples.)
  @param(ASourceRate  Rate of ASamples, Hz.)
  @param(ATargetRate  Wanted rate, Hz (default WHISPER_SAMPLE_RATE).)
  @returns(The resampled audio; a copy when the rates are equal.) }
function WhisperResample(const ASamples: TWhisperSamples; ASourceRate: Integer;
  ATargetRate: Integer = WHISPER_SAMPLE_RATE): TWhisperSamples;

{ Length of whisper.cpp audio in seconds. }
function WhisperSamplesSeconds(const ASamples: TWhisperSamples): Double;

implementation

const
  { WAVE_FORMAT_PCM. }
  WAVE_FORMAT_PCM = 1;
  { WAVE_FORMAT_IEEE_FLOAT. }
  WAVE_FORMAT_IEEE_FLOAT = 3;
  { WAVE_FORMAT_EXTENSIBLE: the real format is in the sub-format GUID. }
  WAVE_FORMAT_EXTENSIBLE = $FFFE;
  { Zero crossings of the sinc on each side of the resampling filter. }
  SINC_ZERO_CROSSINGS = 16;
  { Fractional positions the resampling filter is tabulated for. }
  RESAMPLE_PHASES = 1024;

function ReadTag(AStream: TStream): AnsiString;
begin
  SetLength(Result, 4);
  if AStream.Read(Result[1], 4) <> 4 then
    raise EWhisperError.Create('Unexpected end of WAV data');
end;

function ReadU32(AStream: TStream): UInt32;
begin
  if AStream.Read(Result, 4) <> 4 then
    raise EWhisperError.Create('Unexpected end of WAV data');
end;

function ReadU16(AStream: TStream): UInt16;
begin
  if AStream.Read(Result, 2) <> 2 then
    raise EWhisperError.Create('Unexpected end of WAV data');
end;

function WhisperSamplesSeconds(const ASamples: TWhisperSamples): Double;
begin
  Result := Length(ASamples) / WHISPER_SAMPLE_RATE;
end;

function WhisperPcm16ToMono(AData: PSmallInt; AFrames: Integer; AChannels: Integer): TWhisperSamples;
var
  I, C: Integer;
  Sum: Single;
begin
  Result := nil;
  if (AData = nil) or (AFrames <= 0) or (AChannels <= 0) then
    Exit;
  SetLength(Result, AFrames);
  for I := 0 to AFrames - 1 do
  begin
    Sum := 0;
    for C := 0 to AChannels - 1 do
    begin
      Sum := Sum + AData^ / 32768.0;
      Inc(AData);
    end;
    Result[I] := Sum / AChannels;
  end;
end;

{ Decodes one sample of AInfo's encoding at P to -1..1. }
function DecodeSample(P: PByte; const AInfo: TWhisperWavInfo): Single;
var
  I32: Int32;
begin
  if AInfo.Encoding = wweFloat then
  begin
    if AInfo.BitsPerSample = 64 then
      Result := PDouble(P)^
    else
      Result := PSingle(P)^;
    Exit;
  end;
  case AInfo.BitsPerSample of
    8:
      Result := (Integer(P^) - 128) / 128.0;
    16:
      Result := PSmallInt(P)^ / 32768.0;
    24:
      begin
        // little-endian 24-bit, sign-extended through the top byte
        I32 := Int32(UInt32(P[0]) shl 8 or UInt32(P[1]) shl 16 or UInt32(P[2]) shl 24);
        Result := (I32 div 256) / 8388608.0;
      end;
  else
    Result := PInteger(P)^ / 2147483648.0;
  end;
end;

function WhisperLoadWavStream(AStream: TStream; out AInfo: TWhisperWavInfo): TWhisperSamples;
var
  Tag: AnsiString;
  ChunkSize, DataSize: UInt32;
  FormatTag, BlockAlign: UInt16;
  HaveFmt, HaveData: Boolean;
  ExtSize: UInt16;
  SubFormat: UInt16;
  Data: TBytes;
  Mono: TWhisperSamples;
  BytesPerSample, Frame, C: Integer;
  P: PByte;
  Sum: Single;
  Next: Int64;
begin
  Result := nil;
  FillChar(AInfo, SizeOf(AInfo), 0);
  if ReadTag(AStream) <> 'RIFF' then
    raise EWhisperError.Create('Not a WAV file (no RIFF header)');
  ReadU32(AStream);
  if ReadTag(AStream) <> 'WAVE' then
    raise EWhisperError.Create('Not a WAV file (RIFF type is not WAVE)');
  HaveFmt := False;
  HaveData := False;
  DataSize := 0;
  BlockAlign := 0;
  FormatTag := 0;
  while not HaveData do
  begin
    if AStream.Position + 8 > AStream.Size then
      Break;
    Tag := ReadTag(AStream);
    ChunkSize := ReadU32(AStream);
    Next := AStream.Position + ChunkSize + (ChunkSize and 1);   // chunks are word-aligned
    if Tag = 'fmt ' then
    begin
      FormatTag := ReadU16(AStream);
      AInfo.Channels := ReadU16(AStream);
      AInfo.SampleRate := Integer(ReadU32(AStream));
      ReadU32(AStream);                    // byte rate
      BlockAlign := ReadU16(AStream);
      AInfo.BitsPerSample := ReadU16(AStream);
      if (FormatTag = WAVE_FORMAT_EXTENSIBLE) and (ChunkSize >= 26) then
      begin
        ExtSize := ReadU16(AStream);
        if ExtSize >= 10 then
        begin
          ReadU16(AStream);                // valid bits per sample
          ReadU32(AStream);                // channel mask
          SubFormat := ReadU16(AStream);   // first two bytes of the sub-format GUID
          FormatTag := SubFormat;
        end;
      end;
      HaveFmt := True;
      AStream.Position := Next;
    end
    else if Tag = 'data' then
    begin
      if not HaveFmt then
        raise EWhisperError.Create('WAV data chunk before the fmt chunk');
      DataSize := ChunkSize;
      // A streamed WAV may have a size of 0 or more than is there: read what is.
      if (DataSize = 0) or (Int64(DataSize) > AStream.Size - AStream.Position) then
        DataSize := UInt32(AStream.Size - AStream.Position);
      HaveData := True;
    end
    else
      AStream.Position := Next;
  end;
  if not HaveFmt then
    raise EWhisperError.Create('WAV file has no fmt chunk');
  if not HaveData then
    raise EWhisperError.Create('WAV file has no data chunk');
  case FormatTag of
    WAVE_FORMAT_PCM:
      AInfo.Encoding := wweInteger;
    WAVE_FORMAT_IEEE_FLOAT:
      AInfo.Encoding := wweFloat;
  else
    raise EWhisperError.CreateFmt('Unsupported WAV encoding (format tag %d): only PCM and IEEE float ' +
      'are read - convert the file first', [FormatTag]);
  end;
  if (AInfo.Channels <= 0) or (AInfo.SampleRate <= 0) then
    raise EWhisperError.CreateFmt('Invalid WAV format: %d channel(s), %d Hz',
      [AInfo.Channels, AInfo.SampleRate]);
  if ((AInfo.Encoding = wweInteger) and not (AInfo.BitsPerSample in [8, 16, 24, 32])) or
    ((AInfo.Encoding = wweFloat) and not (AInfo.BitsPerSample in [32, 64])) then
    raise EWhisperError.CreateFmt('Unsupported WAV sample size: %d bits', [AInfo.BitsPerSample]);
  BytesPerSample := AInfo.BitsPerSample div 8;
  if BlockAlign < BytesPerSample * AInfo.Channels then
    BlockAlign := BytesPerSample * AInfo.Channels;
  AInfo.Frames := DataSize div BlockAlign;
  if AInfo.Frames = 0 then
    Exit;
  SetLength(Data, AInfo.Frames * BlockAlign);
  AStream.ReadBuffer(Data[0], Length(Data));
  Mono := nil;
  SetLength(Mono, AInfo.Frames);
  for Frame := 0 to Integer(AInfo.Frames) - 1 do
  begin
    P := @Data[Frame * BlockAlign];
    Sum := 0;
    for C := 0 to AInfo.Channels - 1 do
    begin
      Sum := Sum + DecodeSample(P, AInfo);
      Inc(P, BytesPerSample);
    end;
    Mono[Frame] := Sum / AInfo.Channels;
  end;
  Result := WhisperResample(Mono, AInfo.SampleRate, WHISPER_SAMPLE_RATE);
end;

function WhisperLoadWav(const AFileName: string; out AInfo: TWhisperWavInfo): TWhisperSamples;
var
  S: TFileStream;
begin
  S := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    try
      Result := WhisperLoadWavStream(S, AInfo);
    except
      on E: EWhisperError do
        raise EWhisperError.CreateFmt('%s: %s', [AFileName, E.Message]);
    end;
  finally
    S.Free;
  end;
end;

function WhisperLoadWav(const AFileName: string): TWhisperSamples;
var
  Info: TWhisperWavInfo;
begin
  Result := WhisperLoadWav(AFileName, Info);
end;

function WhisperResample(const ASamples: TWhisperSamples; ASourceRate: Integer;
  ATargetRate: Integer): TWhisperSamples;
var
  Ratio, Cutoff, Pos, D, X, H, Sum, WSum: Double;
  HalfWidth, Taps, N, I, J, K, K0, Center, Last, Q: Integer;
  Table: array of Double;   // (RESAMPLE_PHASES + 1) rows of Taps coefficients
  Row: Integer;
begin
  Result := nil;
  if Length(ASamples) = 0 then
    Exit;
  if (ASourceRate <= 0) or (ATargetRate <= 0) then
    raise EWhisperError.CreateFmt('Invalid sample rates %d -> %d', [ASourceRate, ATargetRate]);
  if ASourceRate = ATargetRate then
  begin
    Result := Copy(ASamples, 0, Length(ASamples));
    Exit;
  end;
  Ratio := ATargetRate / ASourceRate;
  Cutoff := Min(1.0, Ratio);                         // low-pass at the lower Nyquist
  HalfWidth := Ceil(SINC_ZERO_CROSSINGS / Cutoff);   // filter half-width in source samples
  Taps := 2 * HalfWidth;
  // The Hann-windowed sinc for every fractional position, quantised to
  // RESAMPLE_PHASES steps: computing Sin / Cos per tap and output sample
  // took ~50 s for a 35-minute book; the table makes it a multiply-add.
  // (Exact for ratios whose positions fall on the steps, e.g. 8 -> 16 kHz.)
  SetLength(Table, (RESAMPLE_PHASES + 1) * Taps);
  for Q := 0 to RESAMPLE_PHASES do
    for J := 0 to Taps - 1 do
    begin
      D := Q / RESAMPLE_PHASES - (J - HalfWidth + 1);   // = Pos - K
      X := D * Cutoff;
      if Abs(X) < 1e-9 then
        H := 1
      else
        H := Sin(Pi * X) / (Pi * X);
      Table[Q * Taps + J] := H * (0.5 + 0.5 * Cos(Pi * D / HalfWidth));
    end;
  N := Trunc(Length(ASamples) * Ratio);
  Last := High(ASamples);
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    Pos := I / Ratio;
    Center := Floor(Pos);
    Row := Round((Pos - Center) * RESAMPLE_PHASES) * Taps;
    K0 := Center - HalfWidth + 1;
    Sum := 0;
    WSum := 0;
    if (K0 >= 0) and (K0 + Taps - 1 <= Last) then
      for J := 0 to Taps - 1 do
      begin
        H := Table[Row + J];
        Sum := Sum + ASamples[K0 + J] * H;
        WSum := WSum + H;
      end
    else
      for J := 0 to Taps - 1 do
      begin
        K := K0 + J;
        if (K < 0) or (K > Last) then
          Continue;
        H := Table[Row + J];
        Sum := Sum + ASamples[K] * H;
        WSum := WSum + H;
      end;
    if Abs(WSum) > 1e-9 then
      Result[I] := Sum / WSum     // unity gain, also at the edges
    else
      Result[I] := 0;
  end;
end;

end.
