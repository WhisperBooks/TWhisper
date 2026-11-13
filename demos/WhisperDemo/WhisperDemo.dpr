{ WhisperDemo - FireMonkey demo of the whisper.cpp binding: load a model,
  transcribe a WAV file on a worker thread, watch the segments arrive, save
  them as text / SubRip / WebVTT. }
program WhisperDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  Whisper.Types in '..\..\lib\Whisper.Types.pas',
  Whisper.DynLib in '..\..\lib\Whisper.DynLib.pas',
  Whisper.API in '..\..\lib\Whisper.API.pas',
  Whisper.Audio in '..\..\lib\Whisper.Audio.pas',
  Whisper.Core in '..\..\lib\Whisper.Core.pas',
  Whisper.Components in '..\..\lib\Whisper.Components.pas',
  Whisper.FMX in '..\..\fmx\Whisper.FMX.pas',
  uMain in 'src\uMain.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
