{ @abstract(Main form of WhisperDemo: model and WAV selection, transcription
  on a worker thread with live segments, progress and the library log, and
  export as text / SubRip / WebVTT.)

  The TWhisper component (Whisper1) and its events are set up in
  uMain.fmx; only the settings file and the language list are handled in
  FormCreate. Settings (model, audio file, language, options) are kept per
  user in SettingsFolder + WhisperDemo.ini, never next to the executable. }
unit uMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.IOUtils,
  System.IniFiles, System.StrUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Edit, FMX.ListBox, FMX.Memo, FMX.Memo.Types, FMX.Layouts,
  FMX.Controls.Presentation, FMX.ScrollBox,
  Whisper.Types, Whisper.API, Whisper.Core, Whisper.Components, Whisper.FMX;

type
  { The demo's main form. }
  TfrmMain = class(TForm)
    { The whisper.cpp component. }
    Whisper1: TWhisper;
    { Top panel with the settings and buttons. }
    layTop: TLayout;
    { Caption of edModel. }
    lblModel: TLabel;
    { ggml model file. }
    edModel: TEdit;
    { Browses for the model. }
    btnModel: TButton;
    { Caption of edAudio. }
    lblAudio: TLabel;
    { WAV file to transcribe. }
    edAudio: TEdit;
    { Browses for the WAV file. }
    btnAudio: TButton;
    { Caption of cbLanguage. }
    lblLanguage: TLabel;
    { Spoken language ('auto' = detect). }
    cbLanguage: TComboBox;
    { Translate to English. }
    chkTranslate: TCheckBox;
    { Use the GPU backend (applies when the model is loaded). }
    chkGPU: TCheckBox;
    { Loads / unloads the model. }
    btnLoad: TButton;
    { Starts the transcription. }
    btnTranscribe: TButton;
    { Cancels the transcription. }
    btnCancel: TButton;
    { Saves the segments. }
    btnSave: TButton;
    { State of the run. }
    lblStatus: TLabel;
    { Progress of the run. }
    ProgressBar1: TProgressBar;
    { Transcribed segments. }
    memText: TMemo;
    { Splits text and log. }
    Splitter1: TSplitter;
    { Log of the demo, the component and whisper.cpp. }
    memLog: TMemo;
    { Model / audio file selection. }
    OpenDialog1: TOpenDialog;
    { Export file selection. }
    SaveDialog1: TSaveDialog;
    { Loads the settings, fills the language list, builds the title. }
    procedure FormCreate(Sender: TObject);
    { Saves the settings and cancels a run. }
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    { Browses for the model. }
    procedure btnModelClick(Sender: TObject);
    { Browses for the WAV file. }
    procedure btnAudioClick(Sender: TObject);
    { Loads or unloads the model. }
    procedure btnLoadClick(Sender: TObject);
    { Starts transcribing the WAV file. }
    procedure btnTranscribeClick(Sender: TObject);
    { Cancels the run. }
    procedure btnCancelClick(Sender: TObject);
    { Saves the segments as .txt, .srt or .vtt. }
    procedure btnSaveClick(Sender: TObject);
    { The model is loaded. }
    procedure Whisper1Loaded(Sender: TObject);
    { The library or the model could not be loaded. }
    procedure Whisper1LoadFailed(Sender: TObject; const AMessage: string);
    { The model was unloaded. }
    procedure Whisper1Unloaded(Sender: TObject);
    { A new segment. }
    procedure Whisper1Segment(Sender: TObject; const ASegment: TWhisperSegment);
    { Progress of the run. }
    procedure Whisper1Progress(Sender: TObject; AProgress: Integer);
    { The run finished. }
    procedure Whisper1Complete(Sender: TObject; const AResult: TWhisperTranscription);
    { A log line. }
    procedure Whisper1Log(Sender: TObject; ALevel: TWhisperLogLevel; const AText: string);
  private
    { Segments of the last run (for Save). }
    FSegments: TWhisperSegmentArray;
    { Writes a line to memLog. }
    procedure AddLog(const AText: string);
    { Enables the buttons that fit the state. }
    procedure UpdateControls;
    { Per-user folder of the settings file. }
    function SettingsFolder: string;
    { Full name of the settings file. }
    function SettingsFile: string;
    { Reads the settings. }
    procedure LoadSettings;
    { Writes the settings. }
    procedure SaveSettings;
  end;

var
  { The main form. }
  frmMain: TfrmMain;

implementation

{$R *.fmx}

const
  { Settings file name. }
  SETTINGS_NAME = 'WhisperDemo.ini';
  { Section of the settings file. }
  SETTINGS_SECTION = 'Whisper';
  { Company folder of the settings. }
  SETTINGS_COMPANY = 'G3DGames';
  { Application folder of the settings. }
  SETTINGS_APP = 'WhisperDemo';
  { Names of the log levels. }
  LEVEL_NAMES: array[TWhisperLogLevel] of string = ('', 'debug', 'info', 'warn', 'ERROR', '');
  { Progress bar maximum (percent). }
  PROGRESS_MAX = 100;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  Codes: TStringList;
  I: Integer;
begin
  Caption := Format('Whisper demo - whisper.cpp binding for Delphi (whisper.h %s)',
    [WHISPER_BINDING_VERSION]);
  ProgressBar1.Max := PROGRESS_MAX;
  cbLanguage.Items.Add(WHISPER_LANGUAGE_AUTO);
  Codes := Whisper1.LanguageCodes;   // loads the library; a failure is logged
  try
    for I := 0 to Codes.Count - 1 do
      cbLanguage.Items.Add(Codes[I]);
    if Codes.Count > 0 then
      AddLog(Format('Library %s loaded from %s: %d languages', [TWhisperLib.Instance.Version,
        TWhisperLib.Instance.FileName, Codes.Count]));
  finally
    Codes.Free;
  end;
  cbLanguage.ItemIndex := 0;
  LoadSettings;
  UpdateControls;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveSettings;
  Whisper1.Cancel;
end;

procedure TfrmMain.AddLog(const AText: string);
begin
  memLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + AText);
  memLog.GoToTextEnd;
end;

procedure TfrmMain.UpdateControls;
begin
  btnLoad.Text := IfThen(Whisper1.Active, 'Unload model', 'Load model');
  btnLoad.Enabled := not Whisper1.Busy;
  edModel.Enabled := not Whisper1.Active;
  btnModel.Enabled := not Whisper1.Active;
  chkGPU.Enabled := not Whisper1.Active;
  btnTranscribe.Enabled := Whisper1.Active and not Whisper1.Busy;
  btnCancel.Enabled := Whisper1.Busy;
  btnSave.Enabled := (Length(FSegments) > 0) and not Whisper1.Busy;
end;

function TfrmMain.SettingsFolder: string;
begin
  {$if defined(MSWINDOWS)}
  Result := TPath.Combine(TPath.GetHomePath, SETTINGS_COMPANY);       // roaming AppData
  {$elseif defined(MACOS)}
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'Library/Application Support'), SETTINGS_COMPANY);
  {$elseif defined(ANDROID)}
  Result := TPath.Combine(TPath.GetDocumentsPath, SETTINGS_COMPANY);
  {$else}
  Result := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Result = '' then
    Result := TPath.Combine(TPath.GetHomePath, '.config');
  Result := TPath.Combine(Result, SETTINGS_COMPANY);
  {$endif}
  Result := TPath.Combine(Result, SETTINGS_APP);
end;

function TfrmMain.SettingsFile: string;
begin
  Result := TPath.Combine(SettingsFolder, SETTINGS_NAME);
end;

procedure TfrmMain.LoadSettings;
var
  Ini: TMemIniFile;
  Lang: string;
  Idx: Integer;
begin
  if not TFile.Exists(SettingsFile) then
  begin
    AddLog('No settings yet (' + SettingsFile + ')');
    Exit;
  end;
  Ini := TMemIniFile.Create(SettingsFile, TEncoding.UTF8);
  try
    edModel.Text := Ini.ReadString(SETTINGS_SECTION, 'Model', '');
    edAudio.Text := Ini.ReadString(SETTINGS_SECTION, 'Audio', '');
    chkTranslate.IsChecked := Ini.ReadBool(SETTINGS_SECTION, 'Translate', False);
    chkGPU.IsChecked := Ini.ReadBool(SETTINGS_SECTION, 'UseGPU', True);
    Lang := Ini.ReadString(SETTINGS_SECTION, 'Language', WHISPER_LANGUAGE_AUTO);
    Idx := cbLanguage.Items.IndexOf(Lang);
    if Idx >= 0 then
      cbLanguage.ItemIndex := Idx;
    AddLog('Settings read from ' + SettingsFile);
  finally
    Ini.Free;
  end;
end;

procedure TfrmMain.SaveSettings;
var
  Ini: TMemIniFile;
begin
  try
    TDirectory.CreateDirectory(SettingsFolder);
    Ini := TMemIniFile.Create(SettingsFile, TEncoding.UTF8);
    try
      Ini.WriteString(SETTINGS_SECTION, 'Model', edModel.Text);
      Ini.WriteString(SETTINGS_SECTION, 'Audio', edAudio.Text);
      Ini.WriteBool(SETTINGS_SECTION, 'Translate', chkTranslate.IsChecked);
      Ini.WriteBool(SETTINGS_SECTION, 'UseGPU', chkGPU.IsChecked);
      if cbLanguage.ItemIndex >= 0 then
        Ini.WriteString(SETTINGS_SECTION, 'Language', cbLanguage.Items[cbLanguage.ItemIndex]);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    on E: Exception do
      AddLog('Settings not saved to ' + SettingsFile + ': ' + E.Message);
  end;
end;

procedure TfrmMain.btnModelClick(Sender: TObject);
begin
  OpenDialog1.Filter := 'ggml models (*.bin)|*.bin|All files (*.*)|*.*';
  OpenDialog1.FileName := edModel.Text;
  if OpenDialog1.Execute then
    edModel.Text := OpenDialog1.FileName;
end;

procedure TfrmMain.btnAudioClick(Sender: TObject);
begin
  OpenDialog1.Filter := 'WAV files (*.wav)|*.wav|All files (*.*)|*.*';
  OpenDialog1.FileName := edAudio.Text;
  if OpenDialog1.Execute then
    edAudio.Text := OpenDialog1.FileName;
end;

procedure TfrmMain.btnLoadClick(Sender: TObject);
begin
  if Whisper1.Active then
    Whisper1.Active := False
  else
  begin
    Whisper1.ModelFile := edModel.Text;
    Whisper1.UseGPU := chkGPU.IsChecked;
    AddLog('Loading ' + Whisper1.ModelFile);
    Whisper1.Active := True;   // OnLoaded or OnLoadFailed follows
  end;
  UpdateControls;
end;

procedure TfrmMain.btnTranscribeClick(Sender: TObject);
begin
  memText.Lines.Clear;
  FSegments := nil;
  ProgressBar1.Value := 0;
  if cbLanguage.ItemIndex >= 0 then
    Whisper1.Language := cbLanguage.Items[cbLanguage.ItemIndex];
  Whisper1.Translate := chkTranslate.IsChecked;
  try
    Whisper1.TranscribeFileAsync(edAudio.Text);
    lblStatus.Text := 'Running';
  except
    on E: Exception do
      AddLog('Cannot start: ' + E.Message);
  end;
  UpdateControls;
end;

procedure TfrmMain.btnCancelClick(Sender: TObject);
begin
  AddLog('Cancel requested');
  Whisper1.Cancel;
end;

procedure TfrmMain.btnSaveClick(Sender: TObject);
var
  Ext, Text: string;
begin
  SaveDialog1.Filter := 'SubRip subtitles (*.srt)|*.srt|WebVTT subtitles (*.vtt)|*.vtt|Text (*.txt)|*.txt';
  SaveDialog1.DefaultExt := 'srt';
  SaveDialog1.FileName := ChangeFileExt(ExtractFileName(edAudio.Text), '.srt');
  if not SaveDialog1.Execute then
    Exit;
  Ext := LowerCase(ExtractFileExt(SaveDialog1.FileName));
  if Ext = '.vtt' then
    Text := WhisperSegmentsToVtt(FSegments)
  else if Ext = '.txt' then
    Text := WhisperSegmentsToText(FSegments, True)
  else
    Text := WhisperSegmentsToSrt(FSegments);
  TFile.WriteAllText(SaveDialog1.FileName, Text, TEncoding.UTF8);
  AddLog(Format('Saved %d segment(s) to %s', [Length(FSegments), SaveDialog1.FileName]));
end;

procedure TfrmMain.Whisper1Loaded(Sender: TObject);
begin
  lblStatus.Text := 'Ready';
  UpdateControls;
end;

procedure TfrmMain.Whisper1LoadFailed(Sender: TObject; const AMessage: string);
begin
  lblStatus.Text := 'No model';
  UpdateControls;
end;

procedure TfrmMain.Whisper1Unloaded(Sender: TObject);
begin
  AddLog('Model unloaded');
  lblStatus.Text := 'No model';
  UpdateControls;
end;

procedure TfrmMain.Whisper1Segment(Sender: TObject; const ASegment: TWhisperSegment);
var
  N: Integer;
begin
  N := Length(FSegments);
  SetLength(FSegments, N + 1);
  FSegments[N] := ASegment;
  memText.Lines.Add(Format('[%s --> %s]  %s', [WhisperTimeToStr(ASegment.T0),
    WhisperTimeToStr(ASegment.T1), Trim(ASegment.Text)]));
  memText.GoToTextEnd;
end;

procedure TfrmMain.Whisper1Progress(Sender: TObject; AProgress: Integer);
begin
  ProgressBar1.Value := AProgress;
  lblStatus.Text := Format('%d %%', [AProgress]);
end;

procedure TfrmMain.Whisper1Complete(Sender: TObject; const AResult: TWhisperTranscription);
begin
  FSegments := AResult.Segments;
  if AResult.ErrorMessage <> '' then
    lblStatus.Text := 'Failed'
  else if AResult.Cancelled then
    lblStatus.Text := 'Cancelled'
  else
  begin
    lblStatus.Text := 'Done';
    if AResult.ElapsedMs > 0 then
      AddLog(Format('Language %s (%s); real-time factor %.2f', [AResult.LanguageCode,
        AResult.LanguageName, AResult.AudioSeconds * 1000 / AResult.ElapsedMs]));
  end;
  UpdateControls;
end;

procedure TfrmMain.Whisper1Log(Sender: TObject; ALevel: TWhisperLogLevel; const AText: string);
begin
  if LEVEL_NAMES[ALevel] <> '' then
    AddLog(LEVEL_NAMES[ALevel] + ': ' + AText)
  else
    AddLog(AText);
end;

end.
