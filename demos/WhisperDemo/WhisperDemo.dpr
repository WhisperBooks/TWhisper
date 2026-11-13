program WhisperDemo;

{ FireMonkey demo of the whisper.cpp binding: choose a model and a compute
  device, benchmark the devices, transcribe a WAV file on a worker thread,
  watch the segments arrive, save them as text / SubRip / WebVTT.

  Like any user project it lists only its own sources: the library (Whisper.*
  units) comes from the runtime packages WhisperAPI and WhisperAPIFMX, whose DCUs
  are in Delphi's Dcp folder - build them first (WhisperAPI.groupproj does).
  The whisper.cpp libraries go next to the executable (README.md). }

uses
  System.StartUpCopy,
  FMX.Forms,
  uMain in 'src\uMain.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
