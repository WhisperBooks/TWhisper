(* @abstract(Audio input through FFmpeg: any format FFmpeg reads (M4B, M4A,
  MP3, FLAC, Ogg, WAV, ...), its chapters, decoded a range at a time to
  16 kHz mono float for whisper.cpp.)

  FFmpeg's shared libraries (avutil, swresample, avcodec, avformat) are
  loaded at run time by name, as whisper.cpp's are: nothing is linked in and
  a program runs without them until audio other than WAV is opened.
  Windows: avutil-60.dll, swresample-6.dll, avcodec-62.dll, avformat-62.dll
  (FFmpeg 8, a "shared" build); Linux: libavutil.so.60 ...; macOS:
  libavutil.60.dylib ... . The major versions must be the ones
  Whisper.FFmpegLayout.inc was generated for, because a few fields of
  FFmpeg's structs are read at fixed offsets; @link(TWhisperFFmpeg.Create)
  checks them.

  @link(TWhisperAudioFile) opens a file, lists its chapters (an M4B
  audiobook's are its chapters) and decodes any time range - one chapter at
  a time keeps memory small however long the book is.

  Framework-free; compiles with Delphi and FPC. *)
unit Whisper.FFmpeg;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes,
  Whisper.Types, Whisper.DynLib;

const
  {$I Whisper.FFmpegLayout.inc}

type
  { FFmpeg's AVRational: a fraction (time bases). }
  TAVRational = record
    { Numerator. }
    num: Int32;
    { Denominator. }
    den: Int32;
  end;

  { FFmpeg's AVChannelLayout. }
  TAVChannelLayout = record
    { enum AVChannelOrder. }
    order: Int32;
    { Number of channels. }
    nb_channels: Int32;
    { Union: channel mask (native order) or a map pointer. }
    u: UInt64;
    { User data. }
    opaque: Pointer;
  end;
  { Pointer to a @link(TAVChannelLayout). }
  PAVChannelLayout = ^TAVChannelLayout;

  { FFmpeg's AVChapter. }
  TAVChapter = record
    { Unique id. }
    id: Int64;
    { Time base of start and end_. }
    time_base: TAVRational;
    { Start, in time_base units. }
    start: Int64;
    { End, in time_base units (C name "end"). }
    end_: Int64;
    { AVDictionary of the chapter's metadata (title). }
    metadata: Pointer;
  end;
  { Pointer to a @link(TAVChapter). }
  PAVChapter = ^TAVChapter;

  { FFmpeg's AVDictionaryEntry. }
  TAVDictionaryEntry = record
    { Key (UTF-8). }
    key: PAnsiChar;
    { Value (UTF-8). }
    value: PAnsiChar;
  end;
  { Pointer to a @link(TAVDictionaryEntry). }
  PAVDictionaryEntry = ^TAVDictionaryEntry;

  { The FFmpeg functions Whisper.FFmpeg uses, bound by name. Opaque
    structs are plain pointers. }
  TWhisperFFmpegFlat = record
    { avutil: packed version (major shl 16). }
    avutil_version: function: UInt32; cdecl;
    { avutil: licence text. }
    avutil_license: function: PAnsiChar; cdecl;
    { avutil: sets the log level. }
    av_log_set_level: procedure(level: Int32); cdecl;
    { avutil: allocates a frame. }
    av_frame_alloc: function: Pointer; cdecl;
    { avutil: frees a frame and clears the pointer. }
    av_frame_free: procedure(var frame: Pointer); cdecl;
    { avutil: dictionary lookup. }
    av_dict_get: function(m: Pointer; key: PAnsiChar; prev: PAVDictionaryEntry;
      flags: Int32): PAVDictionaryEntry; cdecl;
    { avutil: error code to text. }
    av_strerror: function(errnum: Int32; errbuf: PAnsiChar; errbuf_size: NativeUInt): Int32; cdecl;
    { avutil: default layout for a channel count. }
    av_channel_layout_default: procedure(ch_layout: PAVChannelLayout; nb_channels: Int32); cdecl;
    { avutil: frees what a layout owns. }
    av_channel_layout_uninit: procedure(channel_layout: PAVChannelLayout); cdecl;
    { swresample: packed version. }
    swresample_version: function: UInt32; cdecl;
    { swresample: allocates and sets a resampler. }
    swr_alloc_set_opts2: function(var ps: Pointer; out_ch_layout: PAVChannelLayout;
      out_sample_fmt, out_sample_rate: Int32; in_ch_layout: PAVChannelLayout;
      in_sample_fmt, in_sample_rate, log_offset: Int32; log_ctx: Pointer): Int32; cdecl;
    { swresample: initialises a resampler. }
    swr_init: function(s: Pointer): Int32; cdecl;
    { swresample: frees a resampler and clears the pointer. }
    swr_free: procedure(var s: Pointer); cdecl;
    { swresample: converts; in_ nil = flush. Returns samples out. }
    swr_convert: function(s: Pointer; out_: Pointer; out_count: Int32; in_: Pointer;
      in_count: Int32): Int32; cdecl;
    { swresample: upper bound of samples out for in_samples in. }
    swr_get_out_samples: function(s: Pointer; in_samples: Int32): Int32; cdecl;
    { avcodec: packed version. }
    avcodec_version: function: UInt32; cdecl;
    { avcodec: decoder of a codec id. }
    avcodec_find_decoder: function(id: Int32): Pointer; cdecl;
    { avcodec: name of a codec id. }
    avcodec_get_name: function(id: Int32): PAnsiChar; cdecl;
    { avcodec: allocates a codec context. }
    avcodec_alloc_context3: function(codec: Pointer): Pointer; cdecl;
    { avcodec: frees a codec context and clears the pointer. }
    avcodec_free_context: procedure(var avctx: Pointer); cdecl;
    { avcodec: copies stream parameters into a context. }
    avcodec_parameters_to_context: function(codec: Pointer; par: Pointer): Int32; cdecl;
    { avcodec: opens a codec context. }
    avcodec_open2: function(avctx: Pointer; codec: Pointer; options: Pointer): Int32; cdecl;
    { avcodec: gives the decoder a packet (nil = end). }
    avcodec_send_packet: function(avctx: Pointer; avpkt: Pointer): Int32; cdecl;
    { avcodec: takes a decoded frame. }
    avcodec_receive_frame: function(avctx: Pointer; frame: Pointer): Int32; cdecl;
    { avcodec: drops buffered data (after a seek). }
    avcodec_flush_buffers: procedure(avctx: Pointer); cdecl;
    { avcodec: allocates a packet. }
    av_packet_alloc: function: Pointer; cdecl;
    { avcodec: frees a packet and clears the pointer. }
    av_packet_free: procedure(var pkt: Pointer); cdecl;
    { avcodec: releases a packet's data. }
    av_packet_unref: procedure(pkt: Pointer); cdecl;
    { avformat: packed version. }
    avformat_version: function: UInt32; cdecl;
    { avformat: opens a file (url in UTF-8). }
    avformat_open_input: function(var ps: Pointer; url: PAnsiChar; fmt: Pointer;
      options: Pointer): Int32; cdecl;
    { avformat: reads stream information. }
    avformat_find_stream_info: function(ic: Pointer; options: Pointer): Int32; cdecl;
    { avformat: closes a file and clears the pointer. }
    avformat_close_input: procedure(var s: Pointer); cdecl;
    { avformat: the best stream of a media type. }
    av_find_best_stream: function(ic: Pointer; type_, wanted_stream_nb, related_stream: Int32;
      decoder_ret: Pointer; flags: Int32): Int32; cdecl;
    { avformat: reads the next packet. }
    av_read_frame: function(s: Pointer; pkt: Pointer): Int32; cdecl;
    { avformat: seeks a stream to a time stamp. }
    av_seek_frame: function(s: Pointer; stream_index: Int32; timestamp: Int64;
      flags: Int32): Int32; cdecl;
  end;

  { The loaded FFmpeg libraries. One object serves any number of
    @link(TWhisperAudioFile)s (not at the same time from several threads). }
  TWhisperFFmpeg = class
  private
    { The four libraries, in load order. }
    FLibs: array[0..3] of TWhisperDynLib;
    { Backing field of @link(Flat). }
    FFlat: TWhisperFFmpegFlat;
    { Backing field of @link(Description). }
    FDescription: string;
    { Backing field of @link(Folder). }
    FFolder: string;
    { Loads library AIndex (0 avutil, 1 swresample, 2 avcodec, 3 avformat)
      from AFolder ('' = the executable's folder, then the system search). }
    procedure LoadLib(AIndex: Integer; const AFolder: string);
    { Binds every function of @link(Flat). }
    procedure BindAll;
    { Checks the major versions against the layout include. }
    procedure CheckVersions;
  public
    { Loads FFmpeg from AFolder, or ('') the executable's folder and then
      the system search path.
      @raises(EWhisperError when a library is missing, a function is
        missing, the major versions differ from the ones the offsets were
        generated for, or the record layout differs.) }
    constructor Create(const AFolder: string = '');
    { Unloads the libraries. }
    destructor Destroy; override;
    { FFmpeg's text for an error code. }
    function ErrorText(ACode: Integer): string;
    { The bound functions. }
    property Flat: TWhisperFFmpegFlat read FFlat;
    { "FFmpeg avutil 60.26.100, ..., licence ..." for logs. }
    property Description: string read FDescription;
    { Folder the libraries were loaded from. }
    property Folder: string read FFolder;
  end;

  { One chapter of an audio file. Times in seconds from the start of the
    audio. }
  TWhisperAudioChapter = record
    { Title (metadata "title"; '' if none). }
    Title: string;
    { Start, s. }
    StartTime: Double;
    { End, s. }
    EndTime: Double;
  end;
  { The chapters of an audio file, in order. }
  TWhisperAudioChapterArray = array of TWhisperAudioChapter;

  { An open audio file (or the audio of a video file). }
  TWhisperAudioFile = class
  private
    { Libraries. }
    FFFmpeg: TWhisperFFmpeg;
    { AVFormatContext. }
    FFormat: Pointer;
    { AVCodecContext. }
    FCodec: Pointer;
    { AVPacket. }
    FPacket: Pointer;
    { AVFrame. }
    FFrame: Pointer;
    { Audio stream index. }
    FStream: Integer;
    { Time base of the audio stream. }
    FTimeBase: TAVRational;
    { Start of the file's time line, s (subtracted from every time). }
    FStartOffset: Double;
    { True once something was read (the next read seeks). }
    FUsed: Boolean;
    { Backing field of @link(FileName). }
    FFileName: string;
    { Backing field of @link(Duration). }
    FDuration: Double;
    { Backing field of @link(Chapters). }
    FChapters: TWhisperAudioChapterArray;
    { Backing field of @link(Title). }
    FTitle: string;
    { Backing field of @link(CodecName). }
    FCodecName: string;
    { Backing field of @link(SampleRate). }
    FSampleRate: Integer;
    { Backing field of @link(Channels). }
    FChannels: Integer;
    { Backing field of @link(DecodeErrors). }
    FDecodeErrors: Integer;
    { Raises EWhisperError for a negative FFmpeg result. }
    procedure Check(ACode: Integer; const AWhat: string);
    { Reads the chapters and the title. }
    procedure ReadChapters;
  public
    { Opens AFileName and its best audio stream.
      @raises(EWhisperError when the file cannot be opened, has no audio
        stream, or its codec is not in this FFmpeg build.) }
    constructor Create(AFFmpeg: TWhisperFFmpeg; const AFileName: string);
    { Closes the file. }
    destructor Destroy; override;
    { Decodes AStart..AEnd seconds (AEnd <= 0: to the end) to mono float at
      WHISPER_SAMPLE_RATE. Seeks, so any order of ranges works; reading
      chapters in order is the fast path.
      @raises(EWhisperError when reading fails.) }
    function Read(AStart: Double = 0; AEnd: Double = 0): TWhisperSamples;
    { The file. }
    property FileName: string read FFileName;
    { Length, s (0 if FFmpeg does not know). }
    property Duration: Double read FDuration;
    { Chapters (none for most files that are not audiobooks). }
    property Chapters: TWhisperAudioChapterArray read FChapters;
    { Metadata title ('' if none). }
    property Title: string read FTitle;
    { Codec, e.g. "aac". }
    property CodecName: string read FCodecName;
    { Sample rate of the stream, Hz. }
    property SampleRate: Integer read FSampleRate;
    { Channels of the stream. }
    property Channels: Integer read FChannels;
    { Packets the decoder rejected so far (damaged data is skipped). }
    property DecodeErrors: Integer read FDecodeErrors;
  end;

{ Compares the Pascal records above with the C layout from
  Whisper.FFmpegLayout.inc; '' when they agree, else what differs. }
function WhisperFFmpegCheckLayout: string;

{ The copy protection of an MPEG-4 file (.m4b, .m4a, .mp4, .aax, ...), read
  from its header (the moov box), without FFmpeg: 'Audible DRM (adrm)',
  'FairPlay DRM (drms)' or 'encrypted (sinf / enca)'; '' when there is
  none, or the file is not MPEG-4. A file a tool has decrypted has none,
  whatever its extension. }
function WhisperMp4Protection(const AFileName: string): string;

implementation

const
  { AVMEDIA_TYPE_AUDIO. }
  AVMEDIA_TYPE_AUDIO = 1;
  { AV_SAMPLE_FMT_FLT (packed float). }
  AV_SAMPLE_FMT_FLT = 3;
  { AVSEEK_FLAG_BACKWARD. }
  AVSEEK_FLAG_BACKWARD = 1;
  { AV_LOG_ERROR. }
  AV_LOG_ERROR = 16;
  { AV_NOPTS_VALUE. }
  AV_NOPTS_VALUE = Low(Int64);
  { AV_TIME_BASE (format durations are in microseconds). }
  AV_TIME_BASE = 1000000;
  { AVERROR_EOF = -MKTAG('E','O','F',' '). }
  AVERROR_EOF = -541478725;
  { AVERROR(EAGAIN): EAGAIN is 35 on macOS, 11 elsewhere. }
  {$ifdef WHISPER_MACOS}
  AVERROR_EAGAIN = -35;
  {$else}
  AVERROR_EAGAIN = -11;
  {$endif}
  { Library stems in load order (each needs the ones before it). }
  FFMPEG_STEMS: array[0..3] of string = ('avutil', 'swresample', 'avcodec', 'avformat');

{ Pointer AOffset bytes into AP. }
function At(AP: Pointer; AOffset: Integer): Pointer;
begin
  Result := Pointer(NativeUInt(AP) + NativeUInt(AOffset));
end;

{ Int32 at AOffset in AP. }
function I32At(AP: Pointer; AOffset: Integer): Int32;
begin
  Result := PInteger(At(AP, AOffset))^;
end;

{ Int64 at AOffset in AP. }
function I64At(AP: Pointer; AOffset: Integer): Int64;
begin
  Result := PInt64(At(AP, AOffset))^;
end;

{ Pointer at AOffset in AP. }
function PtrAt(AP: Pointer; AOffset: Integer): Pointer;
begin
  Result := PPointer(At(AP, AOffset))^;
end;

{ A C string (UTF-8) as a string. }
function Utf8Text(AP: PAnsiChar): string;
begin
  if AP = nil then
    Result := ''
  else
    Result := string(UTF8String(AP));
end;

{ File name of library stem AStem, major AMajor, on this platform. }
function LibFileName(const AStem: string; AMajor: Integer): string;
begin
  {$if defined(WHISPER_WINDOWS)}
  Result := Format('%s-%d.dll', [AStem, AMajor]);
  {$elseif defined(WHISPER_MACOS)}
  Result := Format('lib%s.%d.dylib', [AStem, AMajor]);
  {$else}
  Result := Format('lib%s.so.%d', [AStem, AMajor]);
  {$endif}
end;

{ Major version AStem must have. }
function ExpectedMajor(AIndex: Integer): Integer;
begin
  case AIndex of
    0: Result := FFMPEG_AVUTIL_MAJOR;
    1: Result := FFMPEG_SWRESAMPLE_MAJOR;
    2: Result := FFMPEG_AVCODEC_MAJOR;
  else
    Result := FFMPEG_AVFORMAT_MAJOR;
  end;
end;

{ "major.minor.micro" of a packed version. }
function VersionText(V: UInt32): string;
begin
  Result := Format('%d.%d.%d', [V shr 16, (V shr 8) and $FF, V and $FF]);
end;

function WhisperFFmpegCheckLayout: string;
{$ifndef WHISPER_NO_FFMPEG_LAYOUT}
var
  Got: array of Integer;
  I: Integer;
  R: TAVRational;
  L: TAVChannelLayout;
  C: TAVChapter;
  E: TAVDictionaryEntry;

  procedure Add(AValue: NativeUInt);
  begin
    SetLength(Got, Length(Got) + 1);
    Got[High(Got)] := Integer(AValue);
  end;

{$endif}
begin
  Result := '';
  {$ifndef WHISPER_NO_FFMPEG_LAYOUT}
  Got := nil;
  Add(SizeOf(TAVRational)); Add(FFMPEG_C_LAYOUT[1]);
  Add(NativeUInt(@R.num) - NativeUInt(@R)); Add(NativeUInt(@R.den) - NativeUInt(@R));
  Add(SizeOf(TAVChannelLayout)); Add(FFMPEG_C_LAYOUT[5]);
  Add(NativeUInt(@L.order) - NativeUInt(@L)); Add(NativeUInt(@L.nb_channels) - NativeUInt(@L));
  Add(NativeUInt(@L.u) - NativeUInt(@L)); Add(NativeUInt(@L.opaque) - NativeUInt(@L));
  Add(SizeOf(TAVChapter)); Add(FFMPEG_C_LAYOUT[11]);
  Add(NativeUInt(@C.id) - NativeUInt(@C)); Add(NativeUInt(@C.time_base) - NativeUInt(@C));
  Add(NativeUInt(@C.start) - NativeUInt(@C)); Add(NativeUInt(@C.end_) - NativeUInt(@C));
  Add(NativeUInt(@C.metadata) - NativeUInt(@C));
  Add(SizeOf(TAVDictionaryEntry)); Add(FFMPEG_C_LAYOUT[18]);
  Add(NativeUInt(@E.key) - NativeUInt(@E)); Add(NativeUInt(@E.value) - NativeUInt(@E));
  // Alignments (indexes 1, 5, 11, 18) are copied from the table: Pascal has
  // no portable way to ask for them; sizes and offsets cover the layout.
  if Length(Got) <> Length(FFMPEG_C_LAYOUT) then
    Result := Format(' %d values, C table %d;', [Length(Got), Length(FFMPEG_C_LAYOUT)])
  else
    for I := 0 to High(FFMPEG_C_LAYOUT) do
      if Got[I] <> FFMPEG_C_LAYOUT[I] then
        Result := Result + Format(' [%d] C %d, Pascal %d;', [I, FFMPEG_C_LAYOUT[I], Got[I]]);
  if Result <> '' then
    Result := 'FFmpeg record layout differs from C:' + Result;
  {$endif}
end;

function WhisperMp4Protection(const AFileName: string): string;
const
  { Largest moov box read (it holds the index of the whole file). }
  MAX_MOOV = 64 * 1024 * 1024;
  { Box types that mean protection, and what they are. }
  MARKS: array[0..3] of AnsiString = ('adrm', 'drms', 'sinf', 'enca');
  NAMES: array[0..3] of string = ('Audible DRM (adrm)', 'FairPlay DRM (drms)', 'encrypted (sinf)',
    'encrypted (enca)');
var
  F: TFileStream;
  Head: array[0..7] of Byte;
  Big: array[0..7] of Byte;
  Size, Pos, Len: Int64;
  Kind: AnsiString;
  Moov: array of Byte;
  I, K, M: Integer;
  BoxSize: Int64;

  function BE32(const A: array of Byte; AAt: Integer): Int64;
  begin
    Result := (Int64(A[AAt]) shl 24) or (A[AAt + 1] shl 16) or (A[AAt + 2] shl 8) or A[AAt + 3];
  end;

begin
  Result := '';
  if not FileExists(AFileName) then
    Exit;
  F := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Len := F.Size;
    Pos := 0;
    Moov := nil;
    while Pos + 8 <= Len do
    begin
      F.Position := Pos;
      F.ReadBuffer(Head, 8);
      Size := BE32(Head, 0);
      SetLength(Kind, 4);
      Move(Head[4], Kind[1], 4);
      if (Pos = 0) and (Kind <> 'ftyp') then
        Exit;   // not MPEG-4
      if Size = 1 then
      begin
        F.ReadBuffer(Big, 8);
        Size := (BE32(Big, 0) shl 32) or BE32(Big, 4);
      end
      else if Size = 0 then
        Size := Len - Pos;
      if Size < 8 then
        Exit;
      if Kind = 'moov' then
      begin
        if Size > MAX_MOOV then
          Size := MAX_MOOV;
        if Pos + Size > Len then
          Size := Len - Pos;
        SetLength(Moov, Size);
        F.Position := Pos;
        F.ReadBuffer(Moov[0], Size);
        Break;
      end;
      Pos := Pos + Size;
    end;
  finally
    F.Free;
  end;
  // a mark counts where it is a box type: a plausible size in front of it
  for I := 4 to Length(Moov) - 4 do
    for K := Low(MARKS) to High(MARKS) do
    begin
      M := 1;
      while (M <= 4) and (Moov[I + M - 1] = Ord(MARKS[K][M])) do
        Inc(M);
      if M <= 4 then
        Continue;
      BoxSize := BE32(Moov, I - 4);
      if (BoxSize >= 8) and (I - 4 + BoxSize <= Length(Moov)) then
        Exit(NAMES[K]);
    end;
end;

{ TWhisperFFmpeg }

constructor TWhisperFFmpeg.Create(const AFolder: string);
var
  I: Integer;
  Layout: string;
begin
  inherited Create;
  Layout := WhisperFFmpegCheckLayout;
  if Layout <> '' then
    raise EWhisperError.Create(Layout);
  for I := 0 to High(FLibs) do
    LoadLib(I, AFolder);
  FFolder := ExtractFilePath(FLibs[High(FLibs)].FileName);
  BindAll;
  CheckVersions;
  FFlat.av_log_set_level(AV_LOG_ERROR);
  FDescription := Format('FFmpeg avutil %s, swresample %s, avcodec %s, avformat %s (%s) from %s',
    [VersionText(FFlat.avutil_version), VersionText(FFlat.swresample_version),
     VersionText(FFlat.avcodec_version), VersionText(FFlat.avformat_version),
     Utf8Text(FFlat.avutil_license), FFolder]);
end;

destructor TWhisperFFmpeg.Destroy;
var
  I: Integer;
begin
  FillChar(FFlat, SizeOf(FFlat), 0);
  for I := High(FLibs) downto 0 do
    FreeAndNil(FLibs[I]);
  inherited;
end;

procedure TWhisperFFmpeg.LoadLib(AIndex: Integer; const AFolder: string);
var
  Name: string;
begin
  Name := LibFileName(FFMPEG_STEMS[AIndex], ExpectedMajor(AIndex));
  if AFolder <> '' then
    Name := IncludeTrailingPathDelimiter(AFolder) + Name;
  try
    FLibs[AIndex] := TWhisperDynLib.Load(Name, True);
  except
    on E: EWhisperDynLibError do
      raise EWhisperError.CreateFmt('FFmpeg''s shared libraries (%s, %s, %s, %s) are needed for ' +
        'this audio file: %s', [LibFileName(FFMPEG_STEMS[0], ExpectedMajor(0)),
        LibFileName(FFMPEG_STEMS[1], ExpectedMajor(1)), LibFileName(FFMPEG_STEMS[2], ExpectedMajor(2)),
        LibFileName(FFMPEG_STEMS[3], ExpectedMajor(3)), E.Message]);
  end;
end;

procedure TWhisperFFmpeg.BindAll;
var
  U, S, C, F: TWhisperDynLib;
begin
  U := FLibs[0];
  S := FLibs[1];
  C := FLibs[2];
  F := FLibs[3];
  try
    U.Bind(FFlat.avutil_version, 'avutil_version');
    U.Bind(FFlat.avutil_license, 'avutil_license');
    U.Bind(FFlat.av_log_set_level, 'av_log_set_level');
    U.Bind(FFlat.av_frame_alloc, 'av_frame_alloc');
    U.Bind(FFlat.av_frame_free, 'av_frame_free');
    U.Bind(FFlat.av_dict_get, 'av_dict_get');
    U.Bind(FFlat.av_strerror, 'av_strerror');
    U.Bind(FFlat.av_channel_layout_default, 'av_channel_layout_default');
    U.Bind(FFlat.av_channel_layout_uninit, 'av_channel_layout_uninit');
    S.Bind(FFlat.swresample_version, 'swresample_version');
    S.Bind(FFlat.swr_alloc_set_opts2, 'swr_alloc_set_opts2');
    S.Bind(FFlat.swr_init, 'swr_init');
    S.Bind(FFlat.swr_free, 'swr_free');
    S.Bind(FFlat.swr_convert, 'swr_convert');
    S.Bind(FFlat.swr_get_out_samples, 'swr_get_out_samples');
    C.Bind(FFlat.avcodec_version, 'avcodec_version');
    C.Bind(FFlat.avcodec_find_decoder, 'avcodec_find_decoder');
    C.Bind(FFlat.avcodec_get_name, 'avcodec_get_name');
    C.Bind(FFlat.avcodec_alloc_context3, 'avcodec_alloc_context3');
    C.Bind(FFlat.avcodec_free_context, 'avcodec_free_context');
    C.Bind(FFlat.avcodec_parameters_to_context, 'avcodec_parameters_to_context');
    C.Bind(FFlat.avcodec_open2, 'avcodec_open2');
    C.Bind(FFlat.avcodec_send_packet, 'avcodec_send_packet');
    C.Bind(FFlat.avcodec_receive_frame, 'avcodec_receive_frame');
    C.Bind(FFlat.avcodec_flush_buffers, 'avcodec_flush_buffers');
    C.Bind(FFlat.av_packet_alloc, 'av_packet_alloc');
    C.Bind(FFlat.av_packet_free, 'av_packet_free');
    C.Bind(FFlat.av_packet_unref, 'av_packet_unref');
    F.Bind(FFlat.avformat_version, 'avformat_version');
    F.Bind(FFlat.avformat_open_input, 'avformat_open_input');
    F.Bind(FFlat.avformat_find_stream_info, 'avformat_find_stream_info');
    F.Bind(FFlat.avformat_close_input, 'avformat_close_input');
    F.Bind(FFlat.av_find_best_stream, 'av_find_best_stream');
    F.Bind(FFlat.av_read_frame, 'av_read_frame');
    F.Bind(FFlat.av_seek_frame, 'av_seek_frame');
  except
    on E: EWhisperDynLibError do
      raise EWhisperError.Create('FFmpeg: ' + E.Message);
  end;
end;

procedure TWhisperFFmpeg.CheckVersions;
var
  Got: array[0..3] of UInt32;
  I: Integer;
begin
  Got[0] := FFlat.avutil_version;
  Got[1] := FFlat.swresample_version;
  Got[2] := FFlat.avcodec_version;
  Got[3] := FFlat.avformat_version;
  for I := 0 to 3 do
    if Integer(Got[I] shr 16) <> ExpectedMajor(I) then
      raise EWhisperError.CreateFmt('FFmpeg %s is version %s; the binding was made for major %d ' +
        '(rerun tools/ffmpeg_layout.py for another FFmpeg)', [FFMPEG_STEMS[I], VersionText(Got[I]),
        ExpectedMajor(I)]);
end;

function TWhisperFFmpeg.ErrorText(ACode: Integer): string;
var
  Buf: array[0..255] of AnsiChar;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  if FFlat.av_strerror(ACode, @Buf[0], SizeOf(Buf)) = 0 then
    Result := Utf8Text(@Buf[0])
  else
    Result := Format('FFmpeg error %d', [ACode]);
end;

{ TWhisperAudioFile }

constructor TWhisperAudioFile.Create(AFFmpeg: TWhisperFFmpeg; const AFileName: string);
var
  Name: UTF8String;
  Stream, Par, Decoder: Pointer;
  Start: Int64;
  Protection: string;
begin
  inherited Create;
  if AFFmpeg = nil then
    raise EWhisperError.Create('TWhisperAudioFile needs a loaded TWhisperFFmpeg');
  FFFmpeg := AFFmpeg;
  FFileName := AFileName;
  Protection := WhisperMp4Protection(AFileName);
  if Protection <> '' then
    raise EWhisperError.CreateFmt('%s is copy protected (%s): its audio cannot be read. An .aax file ' +
      'straight from Audible is protected; a DRM-free copy of the book is needed.', [AFileName, Protection]);
  Name := UTF8String(AFileName);
  Check(FFFmpeg.Flat.avformat_open_input(FFormat, PAnsiChar(Name), nil, nil), 'open');
  Check(FFFmpeg.Flat.avformat_find_stream_info(FFormat, nil), 'read the stream information of');
  FStream := FFFmpeg.Flat.av_find_best_stream(FFormat, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0);
  if FStream < 0 then
    raise EWhisperError.CreateFmt('%s: no audio stream', [AFileName]);
  Stream := PPointer(At(PtrAt(FFormat, FFOFS_FMT_STREAMS), FStream * SizeOf(Pointer)))^;
  FTimeBase := TAVRational(At(Stream, FFOFS_STREAM_TIME_BASE)^);
  Par := PtrAt(Stream, FFOFS_STREAM_CODECPAR);
  FSampleRate := I32At(Par, FFOFS_PAR_SAMPLE_RATE);
  FChannels := PAVChannelLayout(At(Par, FFOFS_PAR_CH_LAYOUT))^.nb_channels;
  FCodecName := Utf8Text(FFFmpeg.Flat.avcodec_get_name(I32At(Par, FFOFS_PAR_CODEC_ID)));
  Decoder := FFFmpeg.Flat.avcodec_find_decoder(I32At(Par, FFOFS_PAR_CODEC_ID));
  if Decoder = nil then
    raise EWhisperError.CreateFmt('%s: this FFmpeg build has no decoder for %s', [AFileName, FCodecName]);
  FCodec := FFFmpeg.Flat.avcodec_alloc_context3(Decoder);
  if FCodec = nil then
    raise EWhisperError.Create('FFmpeg: out of memory');
  Check(FFFmpeg.Flat.avcodec_parameters_to_context(FCodec, Par), 'set up the decoder for');
  Check(FFFmpeg.Flat.avcodec_open2(FCodec, Decoder, nil), 'open the decoder for');
  FPacket := FFFmpeg.Flat.av_packet_alloc;
  FFrame := FFFmpeg.Flat.av_frame_alloc;
  if (FPacket = nil) or (FFrame = nil) then
    raise EWhisperError.Create('FFmpeg: out of memory');
  Start := I64At(FFormat, FFOFS_FMT_START_TIME);
  if Start <> AV_NOPTS_VALUE then
    FStartOffset := Start / AV_TIME_BASE;
  if I64At(FFormat, FFOFS_FMT_DURATION) > 0 then
    FDuration := I64At(FFormat, FFOFS_FMT_DURATION) / AV_TIME_BASE;
  ReadChapters;
end;

destructor TWhisperAudioFile.Destroy;
begin
  if FFFmpeg <> nil then
  begin
    if FFrame <> nil then
      FFFmpeg.Flat.av_frame_free(FFrame);
    if FPacket <> nil then
      FFFmpeg.Flat.av_packet_free(FPacket);
    if FCodec <> nil then
      FFFmpeg.Flat.avcodec_free_context(FCodec);
    if FFormat <> nil then
      FFFmpeg.Flat.avformat_close_input(FFormat);
  end;
  inherited;
end;

procedure TWhisperAudioFile.Check(ACode: Integer; const AWhat: string);
begin
  if ACode < 0 then
    raise EWhisperError.CreateFmt('FFmpeg could not %s %s: %s', [AWhat, FFileName,
      FFFmpeg.ErrorText(ACode)]);
end;

procedure TWhisperAudioFile.ReadChapters;
var
  N, I: Integer;
  List: Pointer;
  Ch: PAVChapter;
  E: PAVDictionaryEntry;
  Tb: Double;
begin
  E := FFFmpeg.Flat.av_dict_get(PtrAt(FFormat, FFOFS_FMT_METADATA), 'title', nil, 0);
  if E <> nil then
    FTitle := Utf8Text(E^.value);
  N := I32At(FFormat, FFOFS_FMT_NB_CHAPTERS);
  List := PtrAt(FFormat, FFOFS_FMT_CHAPTERS);
  SetLength(FChapters, N);
  for I := 0 to N - 1 do
  begin
    Ch := PPointer(At(List, I * SizeOf(Pointer)))^;
    Tb := Ch^.time_base.num / Ch^.time_base.den;
    FChapters[I].StartTime := Ch^.start * Tb - FStartOffset;
    FChapters[I].EndTime := Ch^.end_ * Tb - FStartOffset;
    E := FFFmpeg.Flat.av_dict_get(Ch^.metadata, 'title', nil, 0);
    if E <> nil then
      FChapters[I].Title := Utf8Text(E^.value)
    else
      FChapters[I].Title := '';
  end;
end;

function TWhisperAudioFile.Read(AStart, AEnd: Double): TWhisperSamples;
var
  Swr: Pointer;
  OutLayout: TAVChannelLayout;
  Buf: TWhisperSamples;
  Count: Int64;
  BufStart: Double;
  HaveStart, Done, AtEof: Boolean;
  Tb: Double;
  R: Integer;
  First, Last: Int64;

  procedure Grow(ANeed: Int64);
  var
    NewLen: Int64;
  begin
    if ANeed <= Length(Buf) then
      Exit;
    NewLen := Length(Buf) * 2;
    if NewLen < ANeed then
      NewLen := ANeed + WHISPER_SAMPLE_RATE * 60;
    if NewLen > High(Integer) then
      raise EWhisperError.CreateFmt('%s: range too long to decode at once (read it in parts, e.g. ' +
        'by chapter)', [FFileName]);
    SetLength(Buf, NewLen);
  end;

  // Resamples one frame (or flushes, AFrame = nil) into Buf.
  procedure Convert(AFrame: Pointer);
  var
    Room, Got, InCount: Integer;
    OutPtr: Pointer;
    InData: Pointer;
  begin
    if AFrame <> nil then
    begin
      InCount := I32At(AFrame, FFOFS_FRAME_NB_SAMPLES);
      InData := PtrAt(AFrame, FFOFS_FRAME_EXTENDED_DATA);
    end
    else
    begin
      InCount := 0;
      InData := nil;
    end;
    Room := FFFmpeg.Flat.swr_get_out_samples(Swr, InCount) + 32;
    Grow(Count + Room);
    OutPtr := @Buf[Count];
    Got := FFFmpeg.Flat.swr_convert(Swr, @OutPtr, Room, InData, InCount);
    if Got < 0 then
      raise EWhisperError.CreateFmt('FFmpeg could not resample %s: %s', [FFileName,
        FFFmpeg.ErrorText(Got)]);
    Inc(Count, Got);
  end;

  // Takes every frame the decoder has ready.
  procedure Drain;
  var
    Pts: Int64;
    T: Double;
  begin
    repeat
      R := FFFmpeg.Flat.avcodec_receive_frame(FCodec, FFrame);
      if (R = AVERROR_EAGAIN) or (R = AVERROR_EOF) then
        Exit;
      if R < 0 then
      begin
        Inc(FDecodeErrors);
        Exit;
      end;
      Pts := I64At(FFrame, FFOFS_FRAME_PTS);
      if Pts <> AV_NOPTS_VALUE then
        T := Pts * Tb - FStartOffset
      else
        T := BufStart + Count / WHISPER_SAMPLE_RATE;
      if (AEnd > 0) and (T >= AEnd) then
      begin
        Done := True;
        Exit;
      end;
      if Swr = nil then
      begin
        Check(FFFmpeg.Flat.swr_alloc_set_opts2(Swr, @OutLayout, AV_SAMPLE_FMT_FLT, WHISPER_SAMPLE_RATE,
          PAVChannelLayout(At(FFrame, FFOFS_FRAME_CH_LAYOUT)), I32At(FFrame, FFOFS_FRAME_FORMAT),
          I32At(FFrame, FFOFS_FRAME_SAMPLE_RATE), 0, nil), 'set up resampling for');
        Check(FFFmpeg.Flat.swr_init(Swr), 'start resampling for');
      end;
      if not HaveStart then
      begin
        BufStart := T;
        HaveStart := True;
      end;
      Convert(FFrame);
    until Done;
  end;

begin
  Result := nil;
  if AStart < 0 then
    AStart := 0;
  Tb := FTimeBase.num / FTimeBase.den;
  Swr := nil;
  Buf := nil;
  Count := 0;
  BufStart := AStart;
  HaveStart := False;
  Done := False;
  AtEof := False;
  FillChar(OutLayout, SizeOf(OutLayout), 0);
  FFFmpeg.Flat.av_channel_layout_default(@OutLayout, 1);
  try
    if FUsed or (AStart > 0) then
    begin
      R := FFFmpeg.Flat.av_seek_frame(FFormat, FStream, Round((AStart + FStartOffset) / Tb),
        AVSEEK_FLAG_BACKWARD);
      Check(R, 'seek in');
      FFFmpeg.Flat.avcodec_flush_buffers(FCodec);
    end;
    FUsed := True;
    while not Done do
    begin
      R := FFFmpeg.Flat.av_read_frame(FFormat, FPacket);
      if R < 0 then
      begin
        // End of file (or a read error: decode what there is).
        FFFmpeg.Flat.avcodec_send_packet(FCodec, nil);
        Drain;
        AtEof := True;
        Break;
      end;
      if I32At(FPacket, FFOFS_PACKET_STREAM_INDEX) = FStream then
      begin
        if FFFmpeg.Flat.avcodec_send_packet(FCodec, FPacket) < 0 then
          Inc(FDecodeErrors);
        FFFmpeg.Flat.av_packet_unref(FPacket);
        Drain;
      end
      else
        FFFmpeg.Flat.av_packet_unref(FPacket);
    end;
    if AtEof and (Swr <> nil) then
      Convert(nil);
    // The decoder starts at a packet boundary at or before AStart: cut to
    // the range asked for.
    First := Round((AStart - BufStart) * WHISPER_SAMPLE_RATE);
    if First < 0 then
      First := 0;
    Last := Count;
    if AEnd > 0 then
    begin
      Last := Round((AEnd - BufStart) * WHISPER_SAMPLE_RATE);
      if Last > Count then
        Last := Count;
    end;
    if Last > First then
      Result := Copy(Buf, Integer(First), Integer(Last - First));
  finally
    if Swr <> nil then
      FFFmpeg.Flat.swr_free(Swr);
    FFFmpeg.Flat.av_channel_layout_uninit(@OutLayout);
  end;
end;

end.
