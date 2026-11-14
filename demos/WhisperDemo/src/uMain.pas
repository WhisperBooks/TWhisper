{ @abstract(Main form of WhisperDemo: model, WAV and compute-device
  selection, a device benchmark, transcription on a worker thread with live
  segments, progress and the library log, and export as text / SubRip /
  WebVTT.)

  The TWhisperAPI component (WhisperAPI1) and its events are set up in
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
    WhisperAPI1: TWhisperAPI;
    { Top panel with the settings and buttons. }
    layTop: TLayout;
    { Caption of cbModel. }
    lblModel: TLabel;
    { Models (ggml-*.bin) of the model folder. }
    cbModel: TComboBox;
    { Browses for a model (its folder becomes the model folder). }
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
    { Caption of cbDevice. }
    lblDevice: TLabel;
    { Compute device (applies when the model is loaded). }
    cbDevice: TComboBox;
    { Times every device and selects the fastest. }
    btnBenchmark: TButton;
    { Benchmark every model of the folder, not only the selected one. }
    chkAllModels: TCheckBox;
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
    { Starts the device benchmark on the WAV file. }
    procedure btnBenchmarkClick(Sender: TObject);
    { A benchmark timed a device. }
    procedure WhisperAPI1BenchmarkResult(Sender: TObject; const AResult: TWhisperBenchmarkResult);
    { The benchmark finished: selects the fastest device. }
    procedure WhisperAPI1BenchmarkComplete(Sender: TObject; const AResults: TWhisperBenchmarkArray;
      ABest: Integer);
    { The model is loaded. }
    procedure WhisperAPI1Loaded(Sender: TObject);
    { The library or the model could not be loaded. }
    procedure WhisperAPI1LoadFailed(Sender: TObject; const AMessage: string);
    { The model was unloaded. }
    procedure WhisperAPI1Unloaded(Sender: TObject);
    { A new segment. }
    procedure WhisperAPI1Segment(Sender: TObject; const ASegment: TWhisperSegment);
    { Progress of the run. }
    procedure WhisperAPI1Progress(Sender: TObject; AProgress: Integer);
    { The run finished. }
    procedure WhisperAPI1Complete(Sender: TObject; const AResult: TWhisperTranscription);
    { A log line. }
    procedure WhisperAPI1Log(Sender: TObject; ALevel: TWhisperLogLevel; const AText: string);
  private
    { Segments of the last run (for Save). }
    FSegments: TWhisperSegmentArray;
    { Device name of each cbDevice item ('' = default). }
    FDeviceNames: TStringList;
    { Folder of the models listed in cbModel. }
    FModelFolder: string;
    { Lists the ggml-*.bin models of AFolder in cbModel and selects ASelect
      (a file name; '' = the first). }
    procedure FillModels(const AFolder, ASelect: string);
    { Selects the model file AFileName (full path) in cbModel. }
    procedure SelectModel(const AFileName: string);
    { Full path of the model selected in cbModel ('' when none). }
    function SelectedModel: string;
    { Fills cbDevice from the loaded backends. }
    procedure FillDevices;
    { Selects the device named AName in cbDevice ('' = default). }
    procedure SelectDevice(const AName: string);
    { Name of the device selected in cbDevice. }
    function SelectedDevice: string;
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
    { Writes the settings: on closing and whenever a model, an audio file or
      a device is chosen or a run starts (a run stopped from the IDE never
      calls OnClose). }
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
  { Seconds of audio the benchmark times per device. }
  BENCHMARK_SECONDS = 30;
  { Text of the default device item. }
  DEFAULT_DEVICE_TEXT = 'Default (whisper.cpp: first GPU)';

procedure TfrmMain.FormCreate(Sender: TObject);
var
  Codes: TStringList;
  I: Integer;
begin
  Caption := Format('Whisper demo - whisper.cpp binding for Delphi (whisper.h %s)',
    [WHISPER_BINDING_VERSION]);
  ProgressBar1.Max := PROGRESS_MAX;
  cbLanguage.Items.Add(WHISPER_LANGUAGE_AUTO);
  Codes := WhisperAPI1.LanguageCodes;   // loads the library; a failure is logged
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
  FDeviceNames := TStringList.Create;
  FillDevices;
  LoadSettings;
  UpdateControls;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveSettings;
  WhisperAPI1.Cancel;
  FreeAndNil(FDeviceNames);
end;

procedure TfrmMain.FillModels(const AFolder, ASelect: string);
var
  Files: TStringDynArray;
  I, Idx: Integer;
  Name: string;
begin
  FModelFolder := AFolder;
  cbModel.Items.Clear;
  if (AFolder <> '') and TDirectory.Exists(AFolder) then
  begin
    Files := TDirectory.GetFiles(AFolder, 'ggml-*.bin');
    for I := 0 to High(Files) do
    begin
      Name := ExtractFileName(Files[I]);
      // VAD models (ggml-silero-*.bin) are not transcription models
      if not ContainsText(Name, 'silero') then
        cbModel.Items.Add(Name);
    end;
  end;
  Idx := cbModel.Items.IndexOf(ASelect);
  if (Idx < 0) and (cbModel.Items.Count > 0) then
    Idx := 0;
  cbModel.ItemIndex := Idx;
  AddLog(Format('%d model(s) in %s', [cbModel.Items.Count, AFolder]));
end;

procedure TfrmMain.SelectModel(const AFileName: string);
var
  Idx: Integer;
begin
  if not SameFileName(ExcludeTrailingPathDelimiter(ExtractFilePath(AFileName)),
    ExcludeTrailingPathDelimiter(FModelFolder)) then
    FillModels(ExtractFilePath(AFileName), ExtractFileName(AFileName))
  else
  begin
    Idx := cbModel.Items.IndexOf(ExtractFileName(AFileName));
    if Idx >= 0 then
      cbModel.ItemIndex := Idx;
  end;
end;

function TfrmMain.SelectedModel: string;
begin
  if cbModel.ItemIndex >= 0 then
    Result := TPath.Combine(FModelFolder, cbModel.Items[cbModel.ItemIndex])
  else
    Result := '';
end;

procedure TfrmMain.FillDevices;
var
  Devs: TWhisperDeviceArray;
  I: Integer;
begin
  cbDevice.Items.Clear;
  FDeviceNames.Clear;
  cbDevice.Items.Add(DEFAULT_DEVICE_TEXT);
  FDeviceNames.Add('');
  Devs := WhisperAPI1.SelectableDevices;
  for I := 0 to High(Devs) do
  begin
    cbDevice.Items.Add(WhisperDeviceText(Devs[I]));
    FDeviceNames.Add(Devs[I].Name);
  end;
  cbDevice.ItemIndex := 0;
  AddLog(Format('%d selectable device(s)', [Length(Devs)]));
end;

procedure TfrmMain.SelectDevice(const AName: string);
var
  Idx: Integer;
begin
  Idx := FDeviceNames.IndexOf(AName);
  if Idx >= 0 then
    cbDevice.ItemIndex := Idx
  else
  begin
    cbDevice.ItemIndex := 0;
    if AName <> '' then
      AddLog('Saved device ' + AName + ' is not available now - using the default');
  end;
end;

function TfrmMain.SelectedDevice: string;
begin
  if (cbDevice.ItemIndex >= 0) and (cbDevice.ItemIndex < FDeviceNames.Count) then
    Result := FDeviceNames[cbDevice.ItemIndex]
  else
    Result := '';
end;

procedure TfrmMain.AddLog(const AText: string);
begin
  memLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + AText);
  memLog.GoToTextEnd;
end;

procedure TfrmMain.UpdateControls;
begin
  btnLoad.Text := IfThen(WhisperAPI1.Active, 'Unload model', 'Load model');
  btnLoad.Enabled := not WhisperAPI1.Busy and (WhisperAPI1.Active or (cbModel.ItemIndex >= 0));
  cbModel.Enabled := not WhisperAPI1.Active;
  btnModel.Enabled := not WhisperAPI1.Active;
  cbDevice.Enabled := not WhisperAPI1.Active;
  btnBenchmark.Enabled := not WhisperAPI1.Busy and (cbModel.ItemIndex >= 0);
  btnTranscribe.Enabled := WhisperAPI1.Active and not WhisperAPI1.Busy;
  btnCancel.Enabled := WhisperAPI1.Busy;
  btnSave.Enabled := (Length(FSegments) > 0) and not WhisperAPI1.Busy;
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
    FillModels(Ini.ReadString(SETTINGS_SECTION, 'ModelFolder', ''),
      Ini.ReadString(SETTINGS_SECTION, 'Model', ''));
    chkAllModels.IsChecked := Ini.ReadBool(SETTINGS_SECTION, 'BenchmarkAllModels', False);
    edAudio.Text := Ini.ReadString(SETTINGS_SECTION, 'Audio', '');
    chkTranslate.IsChecked := Ini.ReadBool(SETTINGS_SECTION, 'Translate', False);
    SelectDevice(Ini.ReadString(SETTINGS_SECTION, 'Device', ''));
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
      Ini.WriteString(SETTINGS_SECTION, 'ModelFolder', FModelFolder);
      if cbModel.ItemIndex >= 0 then
        Ini.WriteString(SETTINGS_SECTION, 'Model', cbModel.Items[cbModel.ItemIndex]);
      Ini.WriteBool(SETTINGS_SECTION, 'BenchmarkAllModels', chkAllModels.IsChecked);
      Ini.WriteString(SETTINGS_SECTION, 'Audio', edAudio.Text);
      Ini.WriteBool(SETTINGS_SECTION, 'Translate', chkTranslate.IsChecked);
      Ini.WriteString(SETTINGS_SECTION, 'Device', SelectedDevice);
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
  OpenDialog1.FileName := SelectedModel;
  if OpenDialog1.Execute then
  begin
    FillModels(ExtractFilePath(OpenDialog1.FileName), ExtractFileName(OpenDialog1.FileName));
    SaveSettings;
  end;
  UpdateControls;
end;

procedure TfrmMain.btnAudioClick(Sender: TObject);
begin
  OpenDialog1.Filter := 'WAV files (*.wav)|*.wav|All files (*.*)|*.*';
  OpenDialog1.FileName := edAudio.Text;
  if OpenDialog1.Execute then
  begin
    edAudio.Text := OpenDialog1.FileName;
    SaveSettings;
  end;
end;

procedure TfrmMain.btnLoadClick(Sender: TObject);
begin
  if WhisperAPI1.Active then
    WhisperAPI1.Active := False
  else
  begin
    SaveSettings;
    WhisperAPI1.ModelFile := SelectedModel;
    WhisperAPI1.Device := SelectedDevice;
    AddLog('Loading ' + WhisperAPI1.ModelFile);
    WhisperAPI1.Active := True;   // OnLoaded or OnLoadFailed follows
  end;
  UpdateControls;
end;

procedure TfrmMain.btnTranscribeClick(Sender: TObject);
begin
  memText.Lines.Clear;
  FSegments := nil;
  ProgressBar1.Value := 0;
  if cbLanguage.ItemIndex >= 0 then
    WhisperAPI1.Language := cbLanguage.Items[cbLanguage.ItemIndex];
  WhisperAPI1.Translate := chkTranslate.IsChecked;
  SaveSettings;
  try
    WhisperAPI1.TranscribeFileAsync(edAudio.Text);
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
  WhisperAPI1.Cancel;
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

procedure TfrmMain.btnBenchmarkClick(Sender: TObject);
var
  Models: TStringList;
  I: Integer;
begin
  WhisperAPI1.ModelFile := SelectedModel;
  if cbLanguage.ItemIndex >= 0 then
    WhisperAPI1.Language := cbLanguage.Items[cbLanguage.ItemIndex];
  WhisperAPI1.Translate := chkTranslate.IsChecked;
  SaveSettings;
  Models := TStringList.Create;
  try
    if chkAllModels.IsChecked then
      for I := 0 to cbModel.Items.Count - 1 do
        Models.Add(TPath.Combine(FModelFolder, cbModel.Items[I]))
    else if SelectedModel <> '' then
      Models.Add(SelectedModel);
    memText.Lines.Clear;
    memText.Lines.Add(Format('Benchmark: %d model(s), first %d s of %s on every device',
      [Models.Count, BENCHMARK_SECONDS, ExtractFileName(edAudio.Text)]));
    try
      WhisperAPI1.BenchmarkFileAsync(edAudio.Text, BENCHMARK_SECONDS, nil, Models);
      lblStatus.Text := 'Benchmark';
    except
      on E: Exception do
        AddLog('Cannot start the benchmark: ' + E.Message);
    end;
  finally
    Models.Free;
  end;
  UpdateControls;
end;

procedure TfrmMain.WhisperAPI1BenchmarkResult(Sender: TObject; const AResult: TWhisperBenchmarkResult);
begin
  if AResult.Ok then
    memText.Lines.Add(Format('%-24s %-10s %6.2fx real time   (load %d ms, warm-up %d ms, run %d ms)  %s',
      [ExtractFileName(AResult.ModelFile), AResult.Device.Name, AResult.Speed, AResult.LoadMs,
       AResult.WarmupMs, AResult.RunMs, Copy(AResult.Text, 1, 60)]))
  else
    memText.Lines.Add(Format('%-24s %-10s failed: %s', [ExtractFileName(AResult.ModelFile),
      AResult.Device.Name, AResult.ErrorMessage]));
end;

procedure TfrmMain.WhisperAPI1BenchmarkComplete(Sender: TObject; const AResults: TWhisperBenchmarkArray;
  ABest: Integer);
begin
  lblStatus.Text := IfThen(WhisperAPI1.Active, 'Ready', 'No model');
  if ABest >= 0 then
  begin
    // Speed alone does not pick a model (bigger ones are more accurate): with
    // several models timed, the fastest device of the SELECTED model is used.
    if not SameFileName(AResults[ABest].ModelFile, SelectedModel) and
      (TWhisperBenchmark.Best(AResults, SelectedModel) >= 0) then
    begin
      memText.Lines.Add(Format('Fastest overall: %s on %s (%.2fx)', [ExtractFileName(AResults[ABest].ModelFile),
        AResults[ABest].Device.Name, AResults[ABest].Speed]));
      ABest := TWhisperBenchmark.Best(AResults, SelectedModel);
    end;
    SelectModel(AResults[ABest].ModelFile);
    SelectDevice(AResults[ABest].Device.Name);
    memText.Lines.Add(Format('Selected: %s on %s (%.2fx real time)%s', [ExtractFileName(AResults[ABest].ModelFile),
      AResults[ABest].Device.Name, AResults[ABest].Speed,
      IfThen(WhisperAPI1.Active, ' - unload and load the model to use it', '')]));
    SaveSettings;
  end
  else
    memText.Lines.Add('No device succeeded');
  UpdateControls;
end;

procedure TfrmMain.WhisperAPI1Loaded(Sender: TObject);
begin
  AddLog('Model running on ' + WhisperAPI1.ActiveDevice);
  lblStatus.Text := 'Ready';
  UpdateControls;
end;

procedure TfrmMain.WhisperAPI1LoadFailed(Sender: TObject; const AMessage: string);
begin
  lblStatus.Text := 'No model';
  UpdateControls;
end;

procedure TfrmMain.WhisperAPI1Unloaded(Sender: TObject);
begin
  AddLog('Model unloaded');
  lblStatus.Text := 'No model';
  UpdateControls;
end;

procedure TfrmMain.WhisperAPI1Segment(Sender: TObject; const ASegment: TWhisperSegment);
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

procedure TfrmMain.WhisperAPI1Progress(Sender: TObject; AProgress: Integer);
begin
  ProgressBar1.Value := AProgress;
  lblStatus.Text := Format('%d %%', [AProgress]);
end;

procedure TfrmMain.WhisperAPI1Complete(Sender: TObject; const AResult: TWhisperTranscription);
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

procedure TfrmMain.WhisperAPI1Log(Sender: TObject; ALevel: TWhisperLogLevel; const AText: string);
begin
  if LEVEL_NAMES[ALevel] <> '' then
    AddLog(LEVEL_NAMES[ALevel] + ': ' + AText)
  else
    AddLog(AText);
end;

end.
