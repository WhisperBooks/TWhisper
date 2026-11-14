(* @abstract(Audio input through FFmpeg: any format FFmpeg reads (M4B, M4A,
  MP3, FLAC, Ogg, WAV, ...), its chapters, decoded a range at a time to
  16 kHz mono float for whisper.cpp.)

  The FFmpeg binding itself is the FFmpegAPI submodule (folder FFmpegAPI,
  units FFmpeg.API and FFmpeg.Media; runtime package FFmpegAPI): FFmpeg's
  shared libraries are loaded at run time by name, version-, layout- and
  licence-checked there. This unit only puts whisper.cpp's terms on it -
  16 kHz mono, @code(TWhisperSamples), @code(EWhisperError) for every
  failure.

  @link(TWhisperAudioFile) opens a file, lists its chapters (an M4B
  audiobook's are its chapters) and decodes any time range - one chapter at
  a time keeps memory small however long the book is. Copy-protected files
  are refused (FFmpeg.Media checks the MPEG-4 header).

  Framework-free; compiles with Delphi and FPC. *)
unit Whisper.FFmpeg;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes,
  Whisper.Types, FFmpeg.API, FFmpeg.Media;

type
  { FFmpeg's libraries (TFFmpegLibrary), raising @code(EWhisperError) when
    they cannot be loaded. }
  TWhisperFFmpeg = class(TFFmpegLibrary)
  public
    { Loads the libraries from AFolder ('' = the executable's folder, then
      the system search path), accepting the builds APolicy allows.
      @raises(EWhisperError when a library is missing, has the wrong
        version or licence, or a function is missing.) }
    constructor Create(const AFolder: string = ''; APolicy: TFFmpegLicencePolicy = flpAny);
  end;

  { A chapter of an audio file: title, start and end in seconds. }
  TWhisperAudioChapter = TFFmpegChapter;
  { Chapters of an audio file, in time order. }
  TWhisperAudioChapterArray = TFFmpegChapterArray;

  { An audio file opened through FFmpeg; reads ranges as 16 kHz mono. }
  TWhisperAudioFile = class
  private
    { The open file. }
    FMedia: TFFmpegMediaFile;
    { The 16 kHz mono decoder of the best audio stream. }
    FDecoder: TFFmpegAudioDecoder;
    { Backing field of @link(Title). }
    FTitle: string;
    { Backing field of @link(CodecName). }
    FCodecName: string;
    { Backing field of @link(SampleRate). }
    FSampleRate: Integer;
    { Backing field of @link(Channels). }
    FChannels: Integer;
    { The file's name. }
    function GetFileName: string;
    { Length, s. }
    function GetDuration: Double;
    { The chapters. }
    function GetChapters: TWhisperAudioChapterArray;
    { Packets the decoder rejected so far. }
    function GetDecodeErrors: Integer;
  public
    { Opens AFileName with AFFmpeg (not owned; must outlive the file).
      @raises(EWhisperError when the file is copy protected, cannot be
        opened, has no audio or no decoder for it.) }
    constructor Create(AFFmpeg: TWhisperFFmpeg; const AFileName: string);
    { Closes the file. }
    destructor Destroy; override;
    { Decodes AStart..AEnd seconds (AEnd <= 0: to the end) to 16 kHz mono.
      @raises(EWhisperError when decoding fails.) }
    function Read(AStart: Double = 0; AEnd: Double = 0): TWhisperSamples;
    { Asks a Read running on another thread to stop (it returns what was
      decoded so far). }
    procedure Cancel;
    { The FFmpegAPI media file (streams, tags, cover art). }
    property Media: TFFmpegMediaFile read FMedia;
    { The file's name. }
    property FileName: string read GetFileName;
    { Length, s. }
    property Duration: Double read GetDuration;
    { The chapters (none for most files that are not audiobooks). }
    property Chapters: TWhisperAudioChapterArray read GetChapters;
    { The title tag ('' when none). }
    property Title: string read FTitle;
    { Codec of the audio stream (aac, mp3, ...). }
    property CodecName: string read FCodecName;
    { Sample rate of the audio stream, Hz (before resampling). }
    property SampleRate: Integer read FSampleRate;
    { Channels of the audio stream (before mixing down). }
    property Channels: Integer read FChannels;
    { Packets the decoder rejected (damaged data is skipped). }
    property DecodeErrors: Integer read GetDecodeErrors;
  end;

{ The copy protection of an MPEG-4 file ('' when none); see
  @code(FFmpegMp4Protection). }
function WhisperMp4Protection(const AFileName: string): string;

implementation

function WhisperMp4Protection(const AFileName: string): string;
begin
  Result := FFmpegMp4Protection(AFileName);
end;

{ TWhisperFFmpeg }

constructor TWhisperFFmpeg.Create(const AFolder: string; APolicy: TFFmpegLicencePolicy);
begin
  try
    inherited Create(AFolder, APolicy, False);
  except
    on E: EFFmpegError do
      raise EWhisperError.Create(E.Message);
  end;
end;

{ TWhisperAudioFile }

constructor TWhisperAudioFile.Create(AFFmpeg: TWhisperFFmpeg; const AFileName: string);
var
  S: Integer;
begin
  inherited Create;
  if AFFmpeg = nil then
    raise EWhisperError.Create('TWhisperAudioFile needs a loaded TWhisperFFmpeg');
  try
    FMedia := TFFmpegMediaFile.Create(AFFmpeg, AFileName);
    FDecoder := TFFmpegAudioDecoder.Create(FMedia, -1, WHISPER_SAMPLE_RATE, 1);
  except
    on E: EFFmpegError do
      raise EWhisperError.Create(E.Message);
  end;
  FTitle := FMedia.Tag('title');
  S := FDecoder.Stream;
  FCodecName := FMedia.Streams[S].CodecName;
  FSampleRate := FMedia.Streams[S].SampleRate;
  FChannels := FMedia.Streams[S].Channels;
end;

destructor TWhisperAudioFile.Destroy;
begin
  FDecoder.Free;
  FMedia.Free;
  inherited;
end;

function TWhisperAudioFile.Read(AStart, AEnd: Double): TWhisperSamples;
begin
  try
    // same layout (array of Single); the cast shares the array
    Result := TWhisperSamples(FDecoder.Read(AStart, AEnd));
  except
    on E: EFFmpegError do
      raise EWhisperError.Create(E.Message);
  end;
end;

procedure TWhisperAudioFile.Cancel;
begin
  FDecoder.Cancel;
end;

function TWhisperAudioFile.GetFileName: string;
begin
  Result := FMedia.FileName;
end;

function TWhisperAudioFile.GetDuration: Double;
begin
  Result := FMedia.Duration;
end;

function TWhisperAudioFile.GetChapters: TWhisperAudioChapterArray;
begin
  Result := FMedia.Chapters;
end;

function TWhisperAudioFile.GetDecodeErrors: Integer;
begin
  Result := FDecoder.DecodeErrors;
end;

end.
