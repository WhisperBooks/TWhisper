{ @abstract(Main form of EpubReader: open an EPUB, read it in a Skia view,
  and - for a book with media overlays - play its audio with the words
  highlighted as they are read.)

  The book component (EpubUnum1), the view (View1) and their events are
  set up in uMain.fmx. The sound is FFmpegAPI's TFFmpegAudioPlayer
  (TFFMpegAPI, installed separately): the book's audio file streamed by
  FFmpeg to the platform's output (WASAPI, PulseAudio), and its clock - the
  sound really being heard - picks the clip to highlight. No FFmpeg: the
  book still reads, without sound.

  No main menu (on Linux FMX's GTK menu bar shows only first letters, and
  SteamOS runs every window full screen): a tool bar of icon buttons, as
  Sprite3D's results view draws them (a TPath icon in a TButton, coloured
  by the style), and keys - P play / pause, Ctrl+O open, Ctrl+Plus /
  Ctrl+Minus text size, D dark mode; the view scrolls with the wheel, the
  arrows, Page Up / Page Down and Space. A click on a word starts the
  audio there.

  Chapters are the table of contents' entries (the reading order's
  documents when it has none): previous / next chapter, and a click in the
  contents, show the chapter AND move the audio to its first clip (played
  at once when playing, else from there on Play). Previous / next step by
  sentence or by paragraph (the drop-down), whatever the overlay's clips
  are - a word-level book has a clip per word. Previous goes back to the
  start of the sentence being read; pressed again near that start, to the
  one before. }
unit uMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.IOUtils, System.Math,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls, FMX.Layouts,
  FMX.ListBox, FMX.Controls.Presentation, FMX.Objects, FMX.Menus, FMX.Edit, System.JSON,
  Epub.Zip, Epub.Layout, Epub.Book, Epub.Components, Epub.FMX, Epub.FMX.View,
  // sound: DCUs of TFFMpegAPI's runtime package FFmpegAPI
  FFmpeg.API, FFmpeg.Player;

type
  { A book in the Recently Opened list, with where its reader left off. }
  TRecentBook = record
    { The EPUB file. }
    FileName: string;
    { Its title (the menu shows it). }
    Title: string;
    { The word the reader was at (index into the book's Words), -1 = the
      start. }
    Word: Integer;
  end;

  { The reader's main form. }
  TfrmMain = class(TForm)
    { The book. }
    EpubUnum1: TEpubUnum;
    { The page view (Skia). }
    View1: TEpubView;
    { Tool bar (its buttons are made in FormCreate). }
    layTop: TLayout;
    { Title, document and playing state. }
    lblStatus: TLabel;
    { Table of contents. }
    lbToc: TListBox;
    { Between contents and page. }
    Splitter1: TSplitter;
    { Follows the audio: highlights the clip being read. }
    tmPlay: TTimer;
    { Chooses the book. }
    dlgOpen: TOpenDialog;
    { Sets up the temporary audio folder; opens a book named on the
      command line. }
    procedure FormCreate(Sender: TObject);
    { Stops the audio and removes the temporary files. }
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    { Keys: P, Ctrl+O, Ctrl+Plus / Ctrl+Minus, D, L (Learn to read), R (say
      again), [ / ] (speed). }
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    { Chooses and opens a book. }
    procedure btnOpenClick(Sender: TObject);
    { Previous document. }
    procedure btnPrevClick(Sender: TObject);
    { Next document. }
    procedure btnNextClick(Sender: TObject);
    { Previous sentence / paragraph (cbStep). }
    procedure btnPrevClipClick(Sender: TObject);
    { Next sentence / paragraph (cbStep). }
    procedure btnNextClipClick(Sender: TObject);
    { Word, sentence or paragraph steps: the buttons' hints. }
    procedure cbStepChange(Sender: TObject);
    { Learn to read on / off. }
    procedure btnLearnClick(Sender: TObject);
    { Speed slider moved: the player's speed, the label. }
    procedure tbSpeedChange(Sender: TObject);
    { Speed label clicked: back to 1x. }
    procedure lblSpeedClick(Sender: TObject);
    { The speed has stayed put for SPEED_SETTLE_MS: the player gets it. }
    procedure tmSpeedTimer(Sender: TObject);
    { Dark / light page and panels. }
    procedure btnDarkClick(Sender: TObject);
    { Play / pause. }
    procedure btnPlayClick(Sender: TObject);
    { Smaller text. }
    procedure btnSmallerClick(Sender: TObject);
    { Larger text. }
    procedure btnLargerClick(Sender: TObject);
    { The book is open: contents, first document, clip map. }
    procedure EpubUnum1Open(Sender: TObject);
    { The book could not be opened. }
    procedure EpubUnum1OpenFailed(Sender: TObject; const AMessage: string);
    { A contents entry was chosen. }
    procedure lbTocChange(Sender: TObject);
    { A word was clicked: play from its clip. }
    procedure View1WordClick(Sender: TObject; AWord: Integer);
    { Another document is shown. }
    procedure View1DocumentChange(Sender: TObject);
    { Follows the audio. }
    procedure tmPlayTimer(Sender: TObject);
  private
    { Opens a book. }
    { Previous document of the reading order. }
    btnPrev: TButton;
    { Previous clip. }
    btnPrevClip: TButton;
    { Plays / pauses the book's audio (media overlays). }
    btnPlay: TButton;
    { Next clip. }
    btnNextClip: TButton;
    { Next document of the reading order. }
    btnNext: TButton;
    { Smaller text. }
    btnSmaller: TButton;
    { Larger text. }
    btnLarger: TButton;
    { What previous / next step by: sentence (0) or paragraph (1). }
    cbStep: TComboBox;
    { Learn to read on / off (stays pressed while on). }
    btnLearn: TButton;
    { Learn to read: a green band behind the tool bar - the mode must be
      obvious at a glance (owner). }
    recLearn: TRectangle;
    { Learn to read is on: Next / Previous move, then say the unit and
      stop; a click says one word; R says the unit again. Also a way to
      proof-read a book's timings by ear. }
    FLearn: Boolean;
    { Learn to read: first word of the unit shown (and said), -1 = none. }
    FLearnFirst: Integer;
    { Learn to read: its last word. }
    FLearnLast: Integer;
    { Playing speed, SPEED_MIN .. SPEED_MAX (1 = as recorded). }
    tbSpeed: TTrackBar;
    { The speed as text ('1.0x'); a click sets 1x again. }
    lblSpeed: TLabel;
    { Applies the slider's speed once it stops moving: every change of
      speed restarts the player's feed (seek, new filter graph), so a drag
      that applied each step made the window stop responding (owner). }
    tmSpeed: TTimer;
    { The speed waiting for tmSpeed. }
    FPendingSpeed: Double;
    { Dark mode on / off. }
    btnDark: TButton;
    { Dark mode is on. }
    FDark: Boolean;
    { Chapters in reading order: their first word in Book.Words. }
    FChapterWord: TArray<Integer>;
    { Chapters: their entry in Book.Toc (-1 = a document, no contents). }
    FChapterToc: TArray<Integer>;
    { Chapters: their document. }
    FChapterDoc: TArray<Integer>;
    { lbToc's selection is being set from code (no chapter jump). }
    FSyncingToc: Boolean;
    { Clip that Play starts from after a jump while paused, -1 = none (Play
      resumes). }
    FSeekClip: Integer;
    { The layout used to find paragraphs (blocks) of words: document
      FUnitDoc's. }
    FUnitLayout: TEpubDocLayout;
    { Document of FUnitLayout, -1 = none. }
    FUnitDoc: Integer;
    { FFmpeg (nil when its libraries are not found: no sound). }
    FFFmpeg: TFFmpegLibrary;
    { The sound (nil without FFmpeg). }
    FPlayer: TFFmpegAudioPlayer;
    { Why there is no sound / it is silent ('' when all is well). }
    FSoundNote: string;
    { What RegisterOpenWith did at start-up, shown until a book opens. }
    FOpenWithNote: string;
    { The menu bar: File (Open, Recently Opened, Exit), View. }
    mnuMain: TMainMenu;
    { File > Recently Opened (filled by BuildRecentMenu). }
    miRecent: TMenuItem;
    { File > Go to Footnote (filled by BuildNotesMenu; disabled when the
      book has none). }
    miNotes: TMenuItem;
    { First word of each note of the book (miNotes' items' Tags index it). }
    FNoteWords: TArray<Integer>;
    { The find bar, under the tool bar (shown by Edit > Find, Ctrl+F). }
    layFind: TLayout;
    { What to find: a word, the start of a word, or several words. }
    edFind: TEdit;
    { Where the finding is: '3 of 17', 'Not found'. }
    lblFind: TLabel;
    { The query FFindHits were found for ('' = none yet). }
    FFindQuery: string;
    { First word of every match of FFindQuery, in book order. }
    FFindHits: TArray<Integer>;
    { Words in a match. }
    FFindLength: Integer;
    { The match shown, -1 = none yet. }
    FFindIndex: Integer;
    { View > Dark mode (checked when on). }
    miDark: TMenuItem;
    { View > Learn to read (checked when on). }
    miLearn: TMenuItem;
    { Recently opened books, the latest first (at most RECENT_MAX), with
      their reading positions. }
    FRecent: TArray<TRecentBook>;
    { The book open now ('' = none): its position is kept for it. }
    FBookFile: string;
    { Folder the audio files are extracted to. }
    FAudioFolder: string;
    { Archive path of the audio file in the player, '' when none. }
    FAudioPath: string;
    { The clip highlighted, -1 when none. }
    FClip: Integer;
    { The audio is playing. }
    FPlaying: Boolean;
    { First word of each clip (-1 when it has none). }
    FClipFirst: TArray<Integer>;
    { Last word of each clip. }
    FClipLast: TArray<Integer>;
    { Opens AFileName. }
    procedure OpenBook(const AFileName: string);
    { Plays from the start of clip AClip. }
    procedure StartClip(AClip: Integer);
    { Stops the audio (the highlight stays). }
    procedure StopPlaying;
    { First clip of document ADoc, -1 when none. }
    function FirstClipOfDocument(ADoc: Integer): Integer;
    { The clip reading word AWord, -1 when none. }
    function ClipOfWord(AWord: Integer): Integer;
    { Enables the buttons and writes the status. }
    procedure UpdateControls;
    { Makes the tool bar's buttons. }
    procedure BuildToolBar;
    { An icon button (Sprite3D's way: a TPath in a TButton). }
    function AddIconButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TButton;
    { A text button. }
    function AddTextButton(const AText, AHint: string; AOnClick: TNotifyEvent): TButton;
    { An icon takes the colour the style gives the button's text. }
    procedure IconButtonApplyStyle(Sender: TObject);
    { Shows AIcon on button AButton. }
    procedure SetIcon(AButton: TButton; const AIcon: string);
    { Loads FFmpeg and the sound output (FSoundNote says what is missing). }
    procedure StartSound;
    { Makes the chapter list (FChapterWord / Toc / Doc). }
    procedure BuildChapters;
    { The chapter word AWord is in, -1 before the first. }
    function ChapterOfWord(AWord: Integer): Integer;
    { Shows chapter AChapter and moves the audio to its first clip. }
    procedure GoChapter(AChapter: Integer);
    { The word being read or shown: the clip's first word, else the shown
      document's first word; -1 without a book. }
    function CurrentWord: Integer;
    { The first clip with words at or after word AWord, -1 when none. }
    function ClipFromWord(AWord: Integer): Integer;
    { Goes to clip AClip: played from there when playing, else highlighted
      and Play starts there. }
    procedure GoClip(AClip: Integer);
    { The block (paragraph) of word AWord in its document's layout. }
    function WordBlock(AWord: Integer): Integer;
    { What Previous / Next step by (UNIT_PHRASE, UNIT_SENTENCE,
      UNIT_PARAGRAPH): cbStep's choice, whose list starts with Phrase only
      in Learn to read. }
    function StepUnit: Integer;
    { Fills cbStep for the mode (Learn to read: Word, Sentence, Paragraph,
      Word chosen; else Sentence, Paragraph), keeping the unit when it can. }
    procedure FillSteps;
    { A unit (word, sentence or paragraph, by StepUnit) starts at word
      AWord. }
    function IsUnitStart(AWord: Integer): Boolean;
    { The last word of the unit that starts at word AWord. }
    function UnitEnd(AWord: Integer): Integer;
    { Opens the audio file of clip AClip in the player (extracted from the
      book once); False when it cannot (FSoundNote says why). }
    function OpenClipAudio(AClip: Integer): Boolean;
    { Learn to read: shows words AFirst .. ALast and says them, then
      stops (no sound for words without clips). }
    procedure SayWords(AFirst, ALast: Integer);
    { Learn to read: Next (ADirection 1) / Previous (-1). }
    procedure LearnStep(ADirection: Integer);
    { Makes the menu bar. }
    procedure BuildMenu;
    { Fills File > Recently Opened from FRecent. }
    procedure BuildRecentMenu;
    { A Recently Opened item: opens its book (Tag = index in FRecent). }
    procedure miRecentItemClick(Sender: TObject);
    { Fills File > Go to Footnote with the open book's notes. }
    procedure BuildNotesMenu;
    { A Go to Footnote item: shows the note (Tag = index in FNoteWords). }
    procedure miNoteClick(Sender: TObject);
    { File > Recently Opened > Clear the list. }
    procedure miClearRecentClick(Sender: TObject);
    { File > Exit. }
    procedure miExitClick(Sender: TObject);
    { Makes the find bar (hidden). }
    procedure BuildFindBar;
    { Edit > Find: shows the find bar, the text selected. }
    procedure miFindClick(Sender: TObject);
    { Edit > Find next. }
    procedure miFindNextClick(Sender: TObject);
    { Edit > Find previous. }
    procedure miFindPreviousClick(Sender: TObject);
    { The find bar's close button / Esc. }
    procedure btnFindCloseClick(Sender: TObject);
    { Keys in the find box: Enter next, Shift+Enter previous, Esc close. }
    procedure edFindKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    { Lists every match of AQuery in FFindHits (whole words, the last one
      may be the start of a word; case and punctuation ignored). }
    procedure FindAll(const AQuery: string);
    { Shows the next (ADirection 1) or previous (-1) match, from the place
      being read; round the book at its end. }
    procedure FindStep(ADirection: Integer);
    { The word the reader is at (the unit said in Learn to read, else the
      clip highlighted, else the shown document's first word); -1 = none. }
    function ReadingWord: Integer;
    { Puts the open book first in FRecent with its reading position. }
    procedure RememberBook;
    { Index in FRecent of the book with file name AFileName (the name
      without folder decides, for now: owner), -1 when none. }
    function RecentIndex(const AFileName: string): Integer;
    { Goes to word AWord as when reading paused there: its clip
      highlighted, Play starts there. }
    procedure RestoreWord(AWord: Integer);
    { Reads dark mode, text size, speed and the recent books
      (SettingsFile). }
    procedure LoadSettings;
    { Writes them. }
    procedure SaveSettings;
    { The start of the sentence / paragraph that word AWord is in. }
    function UnitStart(AWord: Integer): Integer;
    { Selects in lbToc the chapter of word AWord (no jump). }
    procedure SyncToc(AWord: Integer);
    { Colours of the page and the panels for FDark. }
    procedure ApplyTheme;
    { lbToc's style is (re)applied: its background for FDark. }
    procedure TocApplyStyle(Sender: TObject);
  end;

var
  { The main form. }
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows, Winapi.ShlObj, System.Win.Registry,
  {$ENDIF}
  FmxWineCanvas, FmxSkiaCanvas;

const
  { Text size step, px. }
  SIZE_STEP = 2;
  // The tool bar's icons: SVG path data in a 24 by 24 box (Sprite3D's
  // transport icons; the folder is new). FMX.Objects' TPath (the shape)
  // hides System.IOUtils' TPath (file names): both are written qualified.
  { Previous document: bar and two triangles pointing left. }
  ICON_FIRST = 'M5 6h2v12H5z M8 12l6-6v12z M14 12l6-6v12z';
  { Previous clip: triangle left and bar. }
  ICON_PREVIOUS = 'M7 12l7-6v12z M15 6h2v12h-2z';
  { Play: triangle right. }
  ICON_PLAY = 'M8 5v14l11-7z';
  { Pause: two bars. }
  ICON_PAUSE = 'M6 5h4v14H6z M14 5h4v14h-4z';
  { Next clip: bar and triangle right. }
  ICON_NEXT = 'M7 6h2v12H7z M10 6v12l7-6z';
  { Next document: two triangles right and bar. }
  ICON_LAST = 'M4 6v12l6-6z M10 6v12l6-6z M17 6h2v12h-2z';
  { Dark mode: a crescent moon. }
  ICON_DARK = 'M15 3C10 3 6 7 6 12s4 9 9 9c-3-2-5-5-5-9s2-7 5-9z';
  { Icon box, px. }
  ICON_SIZE = 24;
  { Slowest speed: FFmpegAPI's player (one atempo filter) goes down to 0.5. }
  SPEED_MIN = 0.5;
  { Fastest speed (owner: 2x "sounds silly"; the player goes to 2). }
  SPEED_MAX = 1.5;
  { Speed slider and [ / ] keys step. }
  SPEED_STEP = 0.1;
  { The slider must rest this long before the player gets the speed, ms
    (a drag, a held [ / ] key: applied once, at the end). }
  SPEED_SETTLE_MS = 300;
  { Step unit (StepUnit): a phrase - the words between two marks of
    punctuation (, ; : . ! ? ) or a dash), Learn to read only: whole
    sentences are often too much prose for a learner (owner). Word steps
    were tried and dropped (owner: "phrase works well, drop word"); a
    click picks the unit its word is in. }
  UNIT_PHRASE = 0;
  { Step unit: a sentence. }
  UNIT_SENTENCE = 1;
  { Step unit: a paragraph. }
  UNIT_PARAGRAPH = 2;
  { Learn to read: sound added before a unit said on its own, s. 0: with
    40 ms a single word took in the end of the word before (owner). }
  SAY_PAD_BEFORE = 0;
  { Learn to read: sound added after it, s (0, as above: the next word's
    start was heard). }
  SAY_PAD_AFTER = 0;
  { Previous goes to the sentence before when the one being read started
    less than this long ago, s. }
  BACK_GRACE = 1.5;
  { Dark mode: page. }
  DARK_PAGE = $FF1E1E1E;
  { Dark mode: text. }
  DARK_TEXT = $FFD8D8D8;
  { Dark mode: highlight (dark amber: light text stays readable on it). }
  DARK_HIGHLIGHT = $FF6B5310;
  { Dark mode: background of notes (footnotes). }
  DARK_NOTE = $FF2C2C34;
  { Dark mode: links. }
  DARK_LINK = $FF7AB8FF;
  { Dark mode: window and contents panel. }
  DARK_PANEL = $FF2B2B2B;
  { Dark mode: panel text. }
  DARK_PANEL_TEXT = $FFE0E0E0;
  { Learn to read: tool bar band. }
  LEARN_BAR = $FFBFE8C6;
  { Learn to read: highlight (green, where reading uses amber). }
  LEARN_HIGHLIGHT = $FF8FDC9E;
  { Learn to read, dark mode: tool bar band. }
  LEARN_BAR_DARK = $FF1E5A2C;
  { Learn to read, dark mode: highlight (light text stays readable). }
  LEARN_HIGHLIGHT_DARK = $FF2F6E3C;
  { Books kept in File > Recently Opened. }
  RECENT_MAX = 10;
  { Added to the window title in Learn to read. }
  LEARN_TITLE = ' - LEARN TO READ';
  { Button width, px. }
  BUTTON_WIDTH = 36;
  { Longest extension kept for an extracted audio file, the dot included. }
  MAX_AUDIO_EXTENSION = 8;

{ The extension of APath (a path inside a book) for the extracted copy:
  '.mp3', '.m4a', ... when it is a dot and a few ASCII letters or digits,
  else '' - nothing of the book's path that could name another folder. }
function SafeAudioExtension(const APath: string): string;
var
  I, P: Integer;
begin
  Result := '';
  P := LastDelimiter('.', APath);
  if (P = 0) or (Length(APath) - P + 1 > MAX_AUDIO_EXTENSION) or (P = Length(APath)) then
    Exit;
  for I := P + 1 to Length(APath) do
    if not CharInSet(APath[I], ['a'..'z', 'A'..'Z', '0'..'9']) then
      Exit;
  Result := Copy(APath, P, MaxInt);
end;

function TfrmMain.AddIconButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TButton;
var
  Icon: FMX.Objects.TPath;
begin
  Result := TButton.Create(Self);
  Result.Parent := layTop;
  // left-aligned controls are ordered by their X: each goes after the last
  Result.Position.X := layTop.ChildrenCount * 1000;
  Result.Align := TAlignLayout.Left;
  Result.Width := BUTTON_WIDTH;
  Result.Margins.Left := 2;
  Result.Margins.Top := 6;
  Result.Margins.Bottom := 6;
  Result.Text := '';
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.OnClick := AOnClick;
  Result.OnApplyStyleLookup := IconButtonApplyStyle;
  Icon := FMX.Objects.TPath.Create(Self);
  Icon.Parent := Result;
  Icon.Align := TAlignLayout.Center;
  Icon.Width := ICON_SIZE;
  Icon.Height := ICON_SIZE;
  Icon.WrapMode := TPathWrapMode.Original;
  Icon.Data.Data := AIcon;
  Icon.Stroke.Kind := TBrushKind.None;
  Icon.Fill.Color := TAlphaColors.Black;   // the style's colour once styled
  Icon.HitTest := False;
  Result.TagObject := Icon;
end;

function TfrmMain.AddTextButton(const AText, AHint: string; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := layTop;
  Result.Position.X := layTop.ChildrenCount * 1000;
  Result.Align := TAlignLayout.Left;
  Result.Width := BUTTON_WIDTH;
  Result.Margins.Left := 2;
  Result.Margins.Top := 6;
  Result.Margins.Bottom := 6;
  Result.Text := AText;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.OnClick := AOnClick;
end;

procedure TfrmMain.IconButtonApplyStyle(Sender: TObject);
var
  Button: TButton;
begin
  Button := Sender as TButton;
  if Button.TagObject is FMX.Objects.TPath then
    FMX.Objects.TPath(Button.TagObject).Fill.Color := Button.ResultingTextSettings.FontColor;
end;

procedure TfrmMain.SetIcon(AButton: TButton; const AIcon: string);
begin
  if (AButton <> nil) and (AButton.TagObject is FMX.Objects.TPath) then
    FMX.Objects.TPath(AButton.TagObject).Data.Data := AIcon;
end;

procedure TfrmMain.BuildToolBar;
begin
  recLearn := TRectangle.Create(Self);
  recLearn.Parent := layTop;
  recLearn.Align := TAlignLayout.Contents;
  recLearn.HitTest := False;
  recLearn.Stroke.Kind := TBrushKind.None;
  recLearn.Fill.Color := LEARN_BAR;
  recLearn.Visible := False;
  recLearn.SendToBack;
  btnPrev := AddIconButton(ICON_FIRST, 'Previous chapter (the audio follows)', btnPrevClick);
  btnPrevClip := AddIconButton(ICON_PREVIOUS, 'Previous sentence', btnPrevClipClick);
  btnPlay := AddIconButton(ICON_PLAY, 'Play / pause (P)', btnPlayClick);
  btnNextClip := AddIconButton(ICON_NEXT, 'Next sentence', btnNextClipClick);
  btnNext := AddIconButton(ICON_LAST, 'Next chapter (the audio follows)', btnNextClick);
  // what previous / next step by
  cbStep := TComboBox.Create(Self);
  cbStep.Parent := layTop;
  cbStep.Position.X := layTop.ChildrenCount * 1000;
  cbStep.Align := TAlignLayout.Left;
  cbStep.Width := 110;
  cbStep.Margins.Left := 4;
  cbStep.Margins.Top := 9;
  cbStep.Margins.Bottom := 9;
  cbStep.Hint := 'What previous / next step by';
  cbStep.ShowHint := True;
  FillSteps;
  cbStep.OnChange := cbStepChange;
  btnLearn := AddTextButton('Abc', 'Learn to read (L): Next / Previous say one phrase, sentence or ' +
    'paragraph and stop; click a word for its phrase; Play or R says it again', btnLearnClick);
  btnLearn.StaysPressed := True;
  // playing speed: the pitch stays (FFmpeg's atempo)
  lblSpeed := TLabel.Create(Self);
  lblSpeed.Parent := layTop;
  lblSpeed.Position.X := layTop.ChildrenCount * 1000;
  lblSpeed.Align := TAlignLayout.Left;
  lblSpeed.Width := 40;
  lblSpeed.Margins.Left := 8;
  lblSpeed.TextSettings.HorzAlign := TTextAlign.Trailing;
  lblSpeed.Text := '1.0x';
  lblSpeed.HitTest := True;
  lblSpeed.Hint := 'Playing speed - click for 1x';
  lblSpeed.ShowHint := True;
  lblSpeed.OnClick := lblSpeedClick;
  tbSpeed := TTrackBar.Create(Self);
  tbSpeed.Parent := layTop;
  tbSpeed.Position.X := layTop.ChildrenCount * 1000;
  tbSpeed.Align := TAlignLayout.Left;
  tbSpeed.Width := 110;
  tbSpeed.Margins.Left := 4;
  tbSpeed.Margins.Right := 4;
  tbSpeed.Margins.Top := 12;
  tbSpeed.Margins.Bottom := 12;
  tbSpeed.Min := SPEED_MIN;
  tbSpeed.Max := SPEED_MAX;
  tbSpeed.Frequency := SPEED_STEP;
  tbSpeed.Value := 1;
  tbSpeed.Hint := 'Playing speed, 0.5x - 1.5x ([ slower, ] faster)';
  tbSpeed.ShowHint := True;
  tbSpeed.OnChange := tbSpeedChange;
  FPendingSpeed := 1;
  tmSpeed := TTimer.Create(Self);
  tmSpeed.Enabled := False;
  tmSpeed.Interval := SPEED_SETTLE_MS;
  tmSpeed.OnTimer := tmSpeedTimer;
  btnSmaller := AddTextButton('A-', 'Smaller text (Ctrl+Minus)', btnSmallerClick);
  btnLarger := AddTextButton('A+', 'Larger text (Ctrl+Plus)', btnLargerClick);
  btnDark := AddIconButton(ICON_DARK, 'Dark mode (D)', btnDarkClick);
  lblStatus.Position.X := layTop.ChildrenCount * 1000;   // after the buttons
end;

procedure TfrmMain.StartSound;
begin
  try
    // any FFmpeg 8 build - GPL or LGPL (owner): the licence is shown
    FFFmpeg := TFFmpegLibrary.Create('');
    FPlayer := TFFmpegAudioPlayer.Create(FFFmpeg);
    FSoundNote := FPlayer.OutputNote;
    {$IFDEF POSIX}
    WriteLn(ErrOutput, FFFmpeg.Description);
    WriteLn(ErrOutput, 'Sound output: ', FPlayer.Output.Description);
    {$ENDIF}
  except
    on E: Exception do
    begin
      FreeAndNil(FPlayer);
      FreeAndNil(FFFmpeg);
      FSoundNote := 'No sound: ' + E.Message;
    end;
  end;
end;

{ The settings file, the platform's way (JSON: they will grow): Windows
  %APPDATA%\EpubReader\EpubReader.json, macOS ~/Library/Application
  Support/EpubReader/EpubReader.json, Linux $XDG_CONFIG_HOME (else
  ~/.config)/EpubReader/EpubReader.json. }
function SettingsFile: string;
var
  Base: string;
begin
  {$IF Defined(MSWINDOWS)}
  Base := System.IOUtils.TPath.GetHomePath;   // %APPDATA% (Roaming)
  {$ELSEIF Defined(MACOS)}
  Base := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetHomePath, 'Library/Application Support');
  {$ELSE}
  Base := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Base = '' then
    Base := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetHomePath, '.config');
  {$ENDIF}
  Result := System.IOUtils.TPath.Combine(System.IOUtils.TPath.Combine(Base, 'EpubReader'), 'EpubReader.json');
end;

{ Puts the reader in the system's "Open with" list for .epub files, for
  this user only (no administrator rights; the default program is left as
  it is - Windows lets only the user choose that, in "Open with > Always").
  Windows: HKCU\Software\Classes - a ProgID EpubUnum.EpubReader with the
  open command, .epub\OpenWithProgids naming it, Applications\
  EpubReader.exe\SupportedTypes; then the shell is told. Linux: a
  .desktop file for application/epub+zip in ~/.local/share/applications
  (through EpubReader.sh when it is next to the program - SteamOS needs
  its ICU set-up). Written only when missing or pointing elsewhere (the
  program moved), so a normal start changes nothing. Returns what was
  done ('' when nothing). }
function RegisterOpenWith: string;
const
  PROG_ID = 'EpubUnum.EpubReader';
var
  Exe, Command: string;
  {$IFDEF MSWINDOWS}
  Reg: TRegistry;
  {$ENDIF}
  {$IFDEF LINUX}
  Folder, FileName, Launcher, Text: string;
  {$ENDIF}
begin
  Result := '';
  Exe := ParamStr(0);
  {$IFDEF MSWINDOWS}
  Command := '"' + Exe + '" "%1"';
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\Classes\' + PROG_ID + '\shell\open\command') and
      (Reg.ReadString('') = Command) then
      Exit;
    Reg.CloseKey;
    if Reg.OpenKey('Software\Classes\' + PROG_ID, True) then
    begin
      Reg.WriteString('', 'EPUB book');
      Reg.CloseKey;
    end;
    if Reg.OpenKey('Software\Classes\' + PROG_ID + '\DefaultIcon', True) then
    begin
      Reg.WriteString('', '"' + Exe + '",0');
      Reg.CloseKey;
    end;
    if Reg.OpenKey('Software\Classes\' + PROG_ID + '\shell\open\command', True) then
    begin
      Reg.WriteString('', Command);
      Reg.CloseKey;
    end;
    if Reg.OpenKey('Software\Classes\.epub\OpenWithProgids', True) then
    begin
      Reg.WriteString(PROG_ID, '');
      Reg.CloseKey;
    end;
    if Reg.OpenKey('Software\Classes\Applications\' + ExtractFileName(Exe) + '\SupportedTypes', True) then
    begin
      Reg.WriteString('.epub', '');
      Reg.CloseKey;
    end;
    if Reg.OpenKey('Software\Classes\Applications\' + ExtractFileName(Exe) + '\shell\open\command', True) then
    begin
      Reg.WriteString('', Command);
      Reg.CloseKey;
    end;
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
    Result := 'Added to "Open with" for .epub files';
  finally
    Reg.Free;
  end;
  {$ENDIF}
  {$IFDEF LINUX}
  Launcher := System.IOUtils.TPath.Combine(ExtractFilePath(Exe), 'EpubReader.sh');
  if FileExists(Launcher) then
    Command := '"' + Launcher + '" %f'
  else
    Command := '"' + Exe + '" %f';
  Folder := GetEnvironmentVariable('XDG_DATA_HOME');
  if Folder = '' then
    Folder := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetHomePath, '.local/share');
  Folder := System.IOUtils.TPath.Combine(Folder, 'applications');
  FileName := System.IOUtils.TPath.Combine(Folder, 'epubreader.desktop');
  Text := '[Desktop Entry]'#10'Type=Application'#10'Name=EpubReader'#10 +
    'Comment=Read EPUB books, read aloud with the words highlighted'#10'Exec=' + Command + #10 +
    'MimeType=application/epub+zip;'#10'Terminal=false'#10'Categories=Office;Viewer;'#10;
  if FileExists(FileName) and (TFile.ReadAllText(FileName) = Text) then
    Exit;
  ForceDirectories(Folder);
  TFile.WriteAllText(FileName, Text);
  Result := 'Added to "Open with" for EPUB books (' + FileName + ')';
  {$ENDIF}
end;

procedure TfrmMain.BuildMenu;

  { A menu item under AParent. }
  function Item(AParent: TFmxObject; const AText: string; AOnClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Parent := AParent;
    Result.Text := AText;
    Result.OnClick := AOnClick;
  end;

var
  M: TMenuItem;
begin
  mnuMain := TMainMenu.Create(Self);
  mnuMain.Parent := Self;
  M := Item(mnuMain, '&File', nil);
  Item(M, '&Open...'#9'Ctrl+O', btnOpenClick);
  miRecent := Item(M, '&Recently Opened', nil);
  miNotes := Item(M, 'Go to &Footnote', nil);
  miNotes.Enabled := False;
  Item(M, '-', nil);
  Item(M, 'E&xit', miExitClick);
  M := Item(mnuMain, '&Edit', nil);
  Item(M, '&Find...'#9'Ctrl+F', miFindClick);
  Item(M, 'Find &next'#9'F3', miFindNextClick);
  Item(M, 'Find &previous'#9'Shift+F3', miFindPreviousClick);
  M := Item(mnuMain, '&View', nil);
  miDark := Item(M, '&Dark mode'#9'D', btnDarkClick);
  miLearn := Item(M, '&Learn to read'#9'L', btnLearnClick);
  Item(M, '-', nil);
  Item(M, '&Larger text'#9'Ctrl+Plus', btnLargerClick);
  Item(M, '&Smaller text'#9'Ctrl+Minus', btnSmallerClick);
  BuildRecentMenu;
  // a menu made in code reaches the window (Windows' / macOS' own menu
  // bar) only when it is recreated - without this there was no menu
  mnuMain.RecreateOSMenu;
end;

procedure TfrmMain.BuildRecentMenu;
var
  I: Integer;
  M: TMenuItem;
begin
  while miRecent.ItemsCount > 0 do
    miRecent.Items[0].Free;
  for I := 0 to High(FRecent) do
  begin
    M := TMenuItem.Create(Self);
    M.Parent := miRecent;
    if FRecent[I].Title <> '' then
      M.Text := Format('&%d  %s  (%s)', [(I + 1) mod 10, FRecent[I].Title, ExtractFileName(FRecent[I].FileName)])
    else
      M.Text := Format('&%d  %s', [(I + 1) mod 10, ExtractFileName(FRecent[I].FileName)]);
    M.Tag := I;
    M.OnClick := miRecentItemClick;
  end;
  if Length(FRecent) > 0 then
  begin
    M := TMenuItem.Create(Self);
    M.Parent := miRecent;
    M.Text := '-';
    M := TMenuItem.Create(Self);
    M.Parent := miRecent;
    M.Text := 'Clear the list';
    M.OnClick := miClearRecentClick;
  end;
  miRecent.Enabled := Length(FRecent) > 0;
  mnuMain.RecreateOSMenu;
end;

procedure TfrmMain.BuildNotesMenu;
const
  { Most notes listed (a menu, not an index). }
  MAX_NOTES = 300;
  { Words of a note shown in its item. }
  QUOTE_WORDS = 8;
var
  B: TEpubBook;
  W, K, N, C: Integer;
  Text, Where: string;
  M: TMenuItem;
begin
  while miNotes.ItemsCount > 0 do
    miNotes.Items[0].Free;
  FNoteWords := nil;
  B := EpubUnum1.Book;
  if B <> nil then
  begin
    // a note = a run of words whose role is note, in one document
    W := 0;
    while (W < B.WordCount) and (Length(FNoteWords) < MAX_NOTES) do
    begin
      if B.Words[W].Role <> ewrNote then
      begin
        Inc(W);
        Continue;
      end;
      FNoteWords := FNoteWords + [W];
      Text := '';
      K := W;
      N := 0;
      while (K < B.WordCount) and (B.Words[K].Role = ewrNote) and
        (B.Words[K].Document = B.Words[W].Document) do
      begin
        if N < QUOTE_WORDS then
          Text := Text + ' ' + B.Words[K].Text;
        Inc(N);
        Inc(K);
      end;
      if N > QUOTE_WORDS then
        Text := Text + ' ...';
      // where it is: its chapter
      Where := '';
      C := ChapterOfWord(W);
      if (C >= 0) and (FChapterToc[C] >= 0) then
        Where := Trim(B.Toc[FChapterToc[C]].Title) + ': ';
      M := TMenuItem.Create(Self);
      M.Parent := miNotes;
      M.Text := Format('%d. %s%s', [Length(FNoteWords), Where, Trim(Text)]);
      M.Tag := High(FNoteWords);
      M.OnClick := miNoteClick;
      W := K;
    end;
  end;
  miNotes.Enabled := Length(FNoteWords) > 0;
  mnuMain.RecreateOSMenu;
end;

procedure TfrmMain.miNoteClick(Sender: TObject);
var
  I: Integer;
begin
  I := (Sender as TMenuItem).Tag;
  if (I >= 0) and (I <= High(FNoteWords)) then
    RestoreWord(FNoteWords[I]);
end;

procedure TfrmMain.miRecentItemClick(Sender: TObject);
var
  I: Integer;
begin
  I := (Sender as TMenuItem).Tag;
  if (I < 0) or (I > High(FRecent)) then
    Exit;
  if not FileExists(FRecent[I].FileName) then
  begin
    ShowMessage('The book is no longer there: ' + FRecent[I].FileName);
    Delete(FRecent, I, 1);
    BuildRecentMenu;
    Exit;
  end;
  OpenBook(FRecent[I].FileName);
end;

procedure TfrmMain.miClearRecentClick(Sender: TObject);
begin
  // the open book stays (it is put back when the reader closes)
  FRecent := nil;
  BuildRecentMenu;
end;

procedure TfrmMain.miExitClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain.BuildFindBar;
var
  B: TButton;
begin
  layFind := TLayout.Create(Self);
  layFind.Parent := Self;
  layFind.Align := TAlignLayout.Top;
  layFind.Position.Y := layTop.Position.Y + layTop.Height + 1;   // under the tool bar
  layFind.Height := 36;
  layFind.Visible := False;
  edFind := TEdit.Create(Self);
  edFind.Parent := layFind;
  edFind.Align := TAlignLayout.Left;
  edFind.Width := 320;
  edFind.Margins.Rect := RectF(8, 5, 4, 5);
  edFind.TextPrompt := 'Find in the book';
  edFind.OnKeyDown := edFindKeyDown;
  B := AddTextButton('<', 'Previous match (Shift+F3, Shift+Enter)', miFindPreviousClick);
  B.Parent := layFind;
  B.Position.X := 100000;
  B := AddTextButton('>', 'Next match (F3, Enter)', miFindNextClick);
  B.Parent := layFind;
  B.Position.X := 100000;
  lblFind := TLabel.Create(Self);
  lblFind.Parent := layFind;
  lblFind.Align := TAlignLayout.Left;
  lblFind.Position.X := 100000;
  lblFind.Width := 180;
  lblFind.Margins.Left := 8;
  B := AddTextButton('X', 'Close (Esc)', btnFindCloseClick);
  B.Parent := layFind;
  B.Align := TAlignLayout.Right;
end;

procedure TfrmMain.miFindClick(Sender: TObject);
begin
  layFind.Visible := True;
  edFind.SetFocus;
  edFind.SelectAll;
end;

procedure TfrmMain.miFindNextClick(Sender: TObject);
begin
  if Trim(edFind.Text) = '' then
    miFindClick(nil)
  else
    FindStep(1);
end;

procedure TfrmMain.miFindPreviousClick(Sender: TObject);
begin
  if Trim(edFind.Text) = '' then
    miFindClick(nil)
  else
    FindStep(-1);
end;

procedure TfrmMain.btnFindCloseClick(Sender: TObject);
begin
  layFind.Visible := False;
  View1.SetFocus;
end;

procedure TfrmMain.edFindKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    if ssShift in Shift then
      FindStep(-1)
    else
      FindStep(1);
    Key := 0;
  end
  else if Key = vkEscape then
  begin
    btnFindCloseClick(nil);
    Key := 0;
  end;
end;

{ AText lower case, without the punctuation around it (EpubWordCore). }
function FindKey(const AText: string): string;
var
  F, L: Integer;
begin
  F := 1;
  L := Length(AText);
  EpubWordCore(AText, F, L);
  Result := LowerCase(Copy(AText, F, L - F + 1));
end;

procedure TfrmMain.FindAll(const AQuery: string);
var
  B: TEpubBook;
  Parts: TArray<string>;
  Keys: TArray<string>;
  I, J, N: Integer;
  Ok: Boolean;
  W: string;
begin
  FFindQuery := AQuery;
  FFindHits := nil;
  FFindIndex := -1;
  B := EpubUnum1.Book;
  Parts := Trim(AQuery).Split([' '], TStringSplitOptions.ExcludeEmpty);
  Keys := nil;
  for I := 0 to High(Parts) do
    if FindKey(Parts[I]) <> '' then
      Keys := Keys + [FindKey(Parts[I])];
  FFindLength := Length(Keys);
  if (B = nil) or (FFindLength = 0) then
    Exit;
  N := B.WordCount;
  for I := 0 to N - FFindLength do
  begin
    if B.Words[I].Role = ewrNav then
      Continue;   // the contents page
    Ok := True;
    for J := 0 to FFindLength - 1 do
    begin
      W := FindKey(B.Words[I + J].Text);
      // the last word may be the start of one ('Vim' finds 'Vimes')
      if (J < FFindLength - 1) and (W <> Keys[J]) or
        (J = FFindLength - 1) and not W.StartsWith(Keys[J]) then
      begin
        Ok := False;
        Break;
      end;
    end;
    if Ok then
      FFindHits := FFindHits + [I];
  end;
end;

procedure TfrmMain.FindStep(ADirection: Integer);
var
  B: TEpubBook;
  From, I, W, C: Integer;
begin
  B := EpubUnum1.Book;
  if B = nil then
    Exit;
  layFind.Visible := True;
  if edFind.Text <> FFindQuery then
    FindAll(edFind.Text);
  if Length(FFindHits) = 0 then
  begin
    lblFind.Text := 'Not found';
    Exit;
  end;
  // from the match shown, else from the place being read
  if FFindIndex >= 0 then
    FFindIndex := (FFindIndex + ADirection + Length(FFindHits)) mod Length(FFindHits)
  else
  begin
    From := Max(ReadingWord, 0);
    FFindIndex := -1;
    if ADirection > 0 then
    begin
      for I := 0 to High(FFindHits) do
        if FFindHits[I] > From then
        begin
          FFindIndex := I;
          Break;
        end;
      if FFindIndex < 0 then
        FFindIndex := 0;   // round to the start
    end
    else
    begin
      for I := High(FFindHits) downto 0 do
        if FFindHits[I] < From then
        begin
          FFindIndex := I;
          Break;
        end;
      if FFindIndex < 0 then
        FFindIndex := High(FFindHits);
    end;
  end;
  lblFind.Text := Format('%d of %d', [FFindIndex + 1, Length(FFindHits)]);
  // show it lit; Play starts there
  W := FFindHits[FFindIndex];
  StopPlaying;
  FLearnFirst := -1;
  if B.Words[W].Document <> View1.Document then
    View1.ShowDocument(B.Words[W].Document);
  View1.Highlight(W, W + FFindLength - 1);
  View1.ScrollToWord(W, True);
  SyncToc(W);
  C := ClipOfWord(W);
  if C < 0 then
    C := ClipFromWord(W);
  if C >= 0 then
  begin
    FClip := C;
    FSeekClip := C;
  end;
  UpdateControls;
end;

function TfrmMain.ReadingWord: Integer;
begin
  if FLearn and (FLearnFirst >= 0) then
    Result := FLearnFirst
  else
    Result := CurrentWord;
end;

function TfrmMain.RecentIndex(const AFileName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FRecent) do
    if SameFileName(ExtractFileName(FRecent[I].FileName), ExtractFileName(AFileName)) then
      Exit(I);
  Result := -1;
end;

procedure TfrmMain.RememberBook;
var
  R: TRecentBook;
  I: Integer;
begin
  if (FBookFile = '') or (EpubUnum1.Book = nil) then
    Exit;
  R.FileName := FBookFile;
  R.Title := EpubUnum1.Book.Title;
  R.Word := ReadingWord;
  I := RecentIndex(FBookFile);
  if I >= 0 then
    Delete(FRecent, I, 1);
  Insert(R, FRecent, 0);
  if Length(FRecent) > RECENT_MAX then
    SetLength(FRecent, RECENT_MAX);
  BuildRecentMenu;
end;

procedure TfrmMain.RestoreWord(AWord: Integer);
var
  B: TEpubBook;
  C: Integer;
begin
  B := EpubUnum1.Book;
  if (B = nil) or (AWord < 0) or (AWord >= B.WordCount) then
    Exit;
  C := ClipOfWord(AWord);
  if C < 0 then
    C := ClipFromWord(AWord);
  if (C >= 0) and (B.Clips[C].Document = B.Words[AWord].Document) then
    GoClip(C)   // highlighted, and Play starts there
  else
  begin
    View1.ShowDocument(B.Words[AWord].Document);
    View1.ScrollToWord(AWord, True);
    SyncToc(AWord);
    UpdateControls;
  end;
end;

procedure TfrmMain.LoadSettings;
var
  V: TJSONValue;
  O, E: TJSONObject;
  A: TJSONArray;
  I: Integer;
  Size, Speed: Double;
  R: TRecentBook;
begin
  if not FileExists(SettingsFile) then
    Exit;
  try
    V := TJSONObject.ParseJSONValue(TFile.ReadAllText(SettingsFile, TEncoding.UTF8));
    try
      if not (V is TJSONObject) then
        Exit;
      O := TJSONObject(V);
      O.TryGetValue<Boolean>('dark', FDark);
      if O.TryGetValue<Double>('textSize', Size) and (Size >= 10) and (Size <= 60) then
        View1.FontSize := Size;
      if O.TryGetValue<Double>('speed', Speed) then
        tbSpeed.Value := EnsureRange(Speed, SPEED_MIN, SPEED_MAX);
      FRecent := nil;
      if O.TryGetValue<TJSONArray>('recent', A) then
        for I := 0 to A.Count - 1 do
          if (A.Items[I] is TJSONObject) and (Length(FRecent) < RECENT_MAX) then
          begin
            E := TJSONObject(A.Items[I]);
            R.FileName := '';
            R.Title := '';
            R.Word := -1;
            E.TryGetValue<string>('file', R.FileName);
            E.TryGetValue<string>('title', R.Title);
            E.TryGetValue<Integer>('word', R.Word);
            if R.FileName <> '' then
              FRecent := FRecent + [R];
          end;
    finally
      V.Free;
    end;
  except
    // unreadable settings: the defaults
  end;
  ApplyTheme;
  miDark.IsChecked := FDark;
  BuildRecentMenu;   // recreates the OS menu
end;

procedure TfrmMain.SaveSettings;
var
  O, E: TJSONObject;
  A: TJSONArray;
  I: Integer;
begin
  O := TJSONObject.Create;
  try
    O.AddPair('dark', TJSONBool.Create(FDark));
    O.AddPair('textSize', TJSONNumber.Create(View1.FontSize));
    O.AddPair('speed', TJSONNumber.Create(FPendingSpeed));
    A := TJSONArray.Create;
    O.AddPair('recent', A);
    for I := 0 to High(FRecent) do
    begin
      E := TJSONObject.Create;
      E.AddPair('file', FRecent[I].FileName);
      E.AddPair('title', FRecent[I].Title);
      E.AddPair('word', TJSONNumber.Create(FRecent[I].Word));
      A.AddElement(E);
    end;
    try
      ForceDirectories(ExtractFilePath(SettingsFile));
      TFile.WriteAllText(SettingsFile, O.Format(2), TEncoding.UTF8);
    except
      // not saved: the next start has the defaults
    end;
  finally
    O.Free;
  end;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FFindIndex := -1;
  FLearnFirst := -1;
  FLearnLast := -1;
  FClip := -1;
  FSeekClip := -1;
  FUnitDoc := -1;
  lbToc.OnApplyStyleLookup := TocApplyStyle;
  BuildToolBar;
  BuildFindBar;
  BuildMenu;
  StartSound;
  // a new name every run (Random without Randomize gave the same one, so
  // two readers shared - and deleted - one folder)
  FAudioFolder := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath,
    'EpubReader-' + System.IOUtils.TPath.GetGUIDFileName);
  // which canvas FMX really draws the form with (GDI+, Direct2D, Skia ...)
  // and what the Wine / Proton units decided - stderr, as TSteamAPI's demos
  {$IFDEF POSIX}
  WriteLn(ErrOutput, 'FMX canvas in use: ', FmxCanvasClassName);
  {$ENDIF}
  if FmxWineCanvasNote <> '' then
    Caption := Caption + ' [' + FmxWineCanvasName + ']';
  // in the system's "Open with" list (this user; nothing when already so)
  try
    FOpenWithNote := RegisterOpenWith;
  except
    // the reader works without it
    FOpenWithNote := '';
  end;
  // dark mode, text size, speed, the recent books and their positions
  LoadSettings;
  UpdateControls;
  // a book named on the command line (Open with), else the last one read
  if ParamCount > 0 then
    OpenBook(ParamStr(1))
  else if (Length(FRecent) > 0) and FileExists(FRecent[0].FileName) then
    OpenBook(FRecent[0].FileName);
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  StopPlaying;
  // where the reader left off, and the settings
  RememberBook;
  SaveSettings;
  FreeAndNil(FUnitLayout);
  FreeAndNil(FPlayer);
  FreeAndNil(FFFmpeg);
  try
    if TDirectory.Exists(FAudioFolder) then
      TDirectory.Delete(FAudioFolder, True);
  except
    // a file still held by the player: left for the system's temp cleanup
  end;
end;

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  // Ctrl+F, F3 / Shift+F3 work anywhere
  if (ssCtrl in Shift) and ((KeyChar = 'f') or (KeyChar = 'F') or (Key = Ord('F'))) then
  begin
    miFindClick(nil);
    Key := 0;
    KeyChar := #0;
    Exit;
  end;
  if Key = vkF3 then
  begin
    if ssShift in Shift then
      miFindPreviousClick(nil)
    else
      miFindNextClick(nil);
    Key := 0;
    Exit;
  end;
  // typing in the find box is text, not the reader's keys (P, D, L, R ...)
  if (edFind <> nil) and edFind.IsFocused then
    Exit;
  if (KeyChar = 'p') or (KeyChar = 'P') then
  begin
    btnPlayClick(nil);
    KeyChar := #0;
  end
  else if (ssCtrl in Shift) and ((KeyChar = 'o') or (KeyChar = 'O') or (Key = Ord('O'))) then
  begin
    btnOpenClick(nil);
    Key := 0;
    KeyChar := #0;
  end
  else if (ssCtrl in Shift) and ((KeyChar = '+') or (KeyChar = '=')) then
  begin
    btnLargerClick(nil);
    KeyChar := #0;
  end
  else if (ssCtrl in Shift) and (KeyChar = '-') then
  begin
    btnSmallerClick(nil);
    KeyChar := #0;
  end
  else if ((KeyChar = 'd') or (KeyChar = 'D')) and not (ssCtrl in Shift) then
  begin
    btnDarkClick(nil);
    KeyChar := #0;
  end
  else if ((KeyChar = 'l') or (KeyChar = 'L')) and not (ssCtrl in Shift) then
  begin
    btnLearnClick(nil);
    KeyChar := #0;
  end
  else if ((KeyChar = 'r') or (KeyChar = 'R')) and not (ssCtrl in Shift) and FLearn then
  begin
    // say the unit again
    if FLearnFirst >= 0 then
      SayWords(FLearnFirst, FLearnLast)
    else
      LearnStep(1);
    KeyChar := #0;
  end
  else if KeyChar = '[' then
  begin
    tbSpeed.Value := tbSpeed.Value - SPEED_STEP;
    KeyChar := #0;
  end
  else if KeyChar = ']' then
  begin
    tbSpeed.Value := tbSpeed.Value + SPEED_STEP;
    KeyChar := #0;
  end;
end;

procedure TfrmMain.tbSpeedChange(Sender: TObject);
var
  V: Double;
begin
  // to the slider's steps (a drag gives any value)
  V := EnsureRange(Round(tbSpeed.Value / SPEED_STEP) * SPEED_STEP, SPEED_MIN, SPEED_MAX);
  lblSpeed.Text := FormatFloat('0.0', V) + 'x';
  // the label follows at once; the player when the slider rests
  FPendingSpeed := V;
  tmSpeed.Enabled := False;
  tmSpeed.Enabled := True;
end;

procedure TfrmMain.tmSpeedTimer(Sender: TObject);
begin
  tmSpeed.Enabled := False;
  if FPlayer = nil then
    Exit;
  try
    FPlayer.Speed := FPendingSpeed;
  except
    on E: Exception do
    begin
      // no avfilter (avfilter-11 / swscale-9 missing): 1x only
      FSoundNote := E.Message;
      tbSpeed.OnChange := nil;
      tbSpeed.Value := 1;
      tbSpeed.OnChange := tbSpeedChange;
      FPendingSpeed := 1;
      lblSpeed.Text := '1.0x';
      UpdateControls;
    end;
  end;
end;

procedure TfrmMain.lblSpeedClick(Sender: TObject);
begin
  tbSpeed.Value := 1;
end;

procedure TfrmMain.OpenBook(const AFileName: string);
begin
  StopPlaying;
  // the book being left: its position kept
  RememberBook;
  FFindQuery := '';
  FFindHits := nil;
  FFindIndex := -1;
  if lblFind <> nil then
    lblFind.Text := '';
  FBookFile := '';
  FOpenWithNote := '';
  FAudioPath := '';
  FClip := -1;
  FSeekClip := -1;
  FLearnFirst := -1;
  FLearnLast := -1;
  FreeAndNil(FUnitLayout);
  FUnitDoc := -1;
  FChapterWord := nil;
  FChapterToc := nil;
  FChapterDoc := nil;
  EpubUnum1.Active := False;
  EpubUnum1.FileName := AFileName;
  EpubUnum1.Active := True;   // OnOpen or OnOpenFailed follows
  UpdateControls;
end;

procedure TfrmMain.btnOpenClick(Sender: TObject);
begin
  dlgOpen.Filter := 'EPUB books (*.epub)|*.epub|All files (*.*)|*.*';
  if dlgOpen.Execute then
    OpenBook(dlgOpen.FileName);
end;

procedure TfrmMain.EpubUnum1Open(Sender: TObject);
var
  B: TEpubBook;
  I, F, L, First: Integer;
begin
  B := EpubUnum1.Book;
  Caption := 'EpubReader - ' + B.Title;
  if FLearn then
    Caption := Caption + LEARN_TITLE;
  lbToc.BeginUpdate;
  try
    lbToc.Clear;
    for I := 0 to High(B.Toc) do
      lbToc.Items.Add(StringOfChar(' ', B.Toc[I].Level * 3) + B.Toc[I].Title);
  finally
    lbToc.EndUpdate;
  end;
  if FDark then
    ApplyTheme;   // the new items' text colour
  B.LoadText;
  SetLength(FClipFirst, Length(B.Clips));
  SetLength(FClipLast, Length(B.Clips));
  for I := 0 to High(B.Clips) do
    if B.ClipWords(I, F, L) then
    begin
      FClipFirst[I] := F;
      FClipLast[I] := L;
    end
    else
    begin
      FClipFirst[I] := -1;
      FClipLast[I] := -1;
    end;
  BuildChapters;
  BuildNotesMenu;
  // the first linear document with words
  First := 0;
  for I := 0 to High(B.Documents) do
    if B.Documents[I].Linear and (B.Documents[I].WordCount > 0) then
    begin
      First := I;
      Break;
    end;
  View1.ShowDocument(First);
  // this book now: first in Recently Opened, and back where it was left
  FBookFile := ExpandFileName(EpubUnum1.FileName);
  I := RecentIndex(FBookFile);
  if (I >= 0) and (FRecent[I].Word >= 0) then
    RestoreWord(FRecent[I].Word);
  RememberBook;
  View1.SetFocus;
  UpdateControls;
end;

procedure TfrmMain.EpubUnum1OpenFailed(Sender: TObject; const AMessage: string);
begin
  lbToc.Clear;
  BuildNotesMenu;
  View1.Clear;
  Caption := 'EpubReader';
  if FLearn then
    Caption := Caption + LEARN_TITLE;
  UpdateControls;
  ShowMessage(AMessage);
end;

procedure TfrmMain.lbTocChange(Sender: TObject);
var
  B: TEpubBook;
  I, K: Integer;
begin
  if FSyncingToc then
    Exit;
  B := EpubUnum1.Book;
  I := lbToc.ItemIndex;
  if (B = nil) or (I < 0) or (I > High(B.Toc)) or (B.Toc[I].Document < 0) then
    Exit;
  // the chapter of this entry (entries at one place share a chapter)
  for K := 0 to High(FChapterToc) do
    if FChapterToc[K] = I then
    begin
      GoChapter(K);
      Exit;
    end;
  View1.ShowFragment(B.Toc[I].Document, B.Toc[I].Fragment);
  UpdateControls;
end;

procedure TfrmMain.BuildChapters;
var
  B: TEpubBook;
  I, K, W, N: Integer;
  Doc: TEpubDocument;
begin
  B := EpubUnum1.Book;
  FChapterWord := nil;
  FChapterToc := nil;
  FChapterDoc := nil;
  if B = nil then
    Exit;
  SetLength(FChapterWord, Length(B.Toc) + Length(B.Documents));
  SetLength(FChapterToc, Length(FChapterWord));
  SetLength(FChapterDoc, Length(FChapterWord));
  N := 0;
  for I := 0 to High(B.Toc) do
  begin
    if B.Toc[I].Document < 0 then
      Continue;
    Doc := B.Documents[B.Toc[I].Document];
    W := Doc.FirstWord;
    if B.Toc[I].Fragment <> '' then
      for K := 0 to High(Doc.Ids) do
        if (Doc.Ids[K].Id = B.Toc[I].Fragment) and (Doc.Ids[K].FirstWord >= 0) then
        begin
          W := Doc.Ids[K].FirstWord;
          Break;
        end;
    // in reading order only; an entry at the place of the one before
    // (a part and its first chapter) is that chapter
    if (N > 0) and (W <= FChapterWord[N - 1]) then
      Continue;
    FChapterWord[N] := W;
    FChapterToc[N] := I;
    FChapterDoc[N] := B.Toc[I].Document;
    Inc(N);
  end;
  if N = 0 then
    // no contents: the linear documents with words
    for I := 0 to High(B.Documents) do
      if B.Documents[I].Linear and (B.Documents[I].WordCount > 0) then
      begin
        FChapterWord[N] := B.Documents[I].FirstWord;
        FChapterToc[N] := -1;
        FChapterDoc[N] := I;
        Inc(N);
      end;
  SetLength(FChapterWord, N);
  SetLength(FChapterToc, N);
  SetLength(FChapterDoc, N);
end;

function TfrmMain.ChapterOfWord(AWord: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FChapterWord) do
    if FChapterWord[I] <= AWord then
      Result := I
    else
      Break;
end;

function TfrmMain.CurrentWord: Integer;
var
  B: TEpubBook;
begin
  Result := -1;
  B := EpubUnum1.Book;
  if B = nil then
    Exit;
  if (FClip >= 0) and (FClip <= High(FClipFirst)) and (FClipFirst[FClip] >= 0) and
    (B.Clips[FClip].Document = View1.Document) then
    Result := FClipFirst[FClip]
  else if (View1.Document >= 0) and (View1.Document <= High(B.Documents)) then
    Result := B.Documents[View1.Document].FirstWord;
end;

function TfrmMain.ClipFromWord(AWord: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FClipFirst) do
    if FClipFirst[I] >= AWord then
      Exit(I);
  Result := -1;
end;

procedure TfrmMain.GoClip(AClip: Integer);
var
  B: TEpubBook;
begin
  B := EpubUnum1.Book;
  if (B = nil) or (AClip < 0) or (AClip > High(B.Clips)) then
    Exit;
  if FPlaying then
  begin
    StartClip(AClip);
    Exit;
  end;
  // paused or stopped: show it; Play starts here
  FClip := AClip;
  FSeekClip := AClip;
  if B.Clips[AClip].Document <> View1.Document then
    View1.ShowDocument(B.Clips[AClip].Document);
  if FClipFirst[AClip] >= 0 then
  begin
    View1.Highlight(FClipFirst[AClip], FClipLast[AClip]);
    View1.ScrollToWord(FClipFirst[AClip], True);
    SyncToc(FClipFirst[AClip]);
  end;
  UpdateControls;
end;

procedure TfrmMain.GoChapter(AChapter: Integer);
var
  B: TEpubBook;
  C, Limit: Integer;
begin
  B := EpubUnum1.Book;
  if (B = nil) or (AChapter < 0) or (AChapter > High(FChapterWord)) then
    Exit;
  // Learn to read: the next step starts in the new chapter
  FLearnFirst := -1;
  if FChapterToc[AChapter] >= 0 then
    View1.ShowFragment(FChapterDoc[AChapter], B.Toc[FChapterToc[AChapter]].Fragment)
  else
    View1.ShowDocument(FChapterDoc[AChapter]);
  SyncToc(FChapterWord[AChapter]);
  // the audio follows: the chapter's first clip - one inside the chapter
  // (a chapter without audio does not jump to a later chapter's)
  C := ClipFromWord(FChapterWord[AChapter]);
  if AChapter < High(FChapterWord) then
    Limit := FChapterWord[AChapter + 1]
  else
    Limit := MaxInt;
  if (C >= 0) and (FClipFirst[C] < Limit) then
    GoClip(C)
  else
  begin
    // nothing to hear here: stop, and Play starts with the shown chapter
    StopPlaying;
    FClip := -1;
    FSeekClip := -1;
    View1.ClearHighlight;
    UpdateControls;
  end;
end;

procedure TfrmMain.SyncToc(AWord: Integer);
var
  K: Integer;
begin
  K := ChapterOfWord(AWord);
  if (K < 0) or (FChapterToc[K] < 0) or (lbToc.ItemIndex = FChapterToc[K]) then
    Exit;
  FSyncingToc := True;
  try
    lbToc.ItemIndex := FChapterToc[K];
  finally
    FSyncingToc := False;
  end;
end;

function TfrmMain.WordBlock(AWord: Integer): Integer;
var
  B: TEpubBook;
  D: Integer;
begin
  B := EpubUnum1.Book;
  D := B.Words[AWord].Document;
  if (FUnitLayout = nil) or (FUnitDoc <> D) then
  begin
    FreeAndNil(FUnitLayout);
    FUnitLayout := B.DocumentLayout(D);
    FUnitDoc := D;
  end;
  Result := B.BlockOfWord(FUnitLayout, D, AWord);
end;

{ True when word AWord ends a phrase: its last character, after closing
  quotes and brackets, is , ; : . ! ? or a dash (U+2012 - U+2015, which
  EpubUnum leaves on the word before it), or the word closes a bracket. }
function EndsPhrase(const AWord: string): Boolean;
var
  N: Integer;
begin
  Result := False;
  N := Length(AWord);
  if (N > 0) and CharInSet(AWord[N], [')', ']']) then
    Exit(True);
  while (N > 0) and ((AWord[N] = '"') or (AWord[N] = '''') or (Ord(AWord[N]) = $2019) or
    (Ord(AWord[N]) = $201D) or (Ord(AWord[N]) = $BB)) do
    Dec(N);
  if N = 0 then
    Exit;
  Result := CharInSet(AWord[N], [',', ';', ':', '.', '!', '?']) or
    ((Ord(AWord[N]) >= $2012) and (Ord(AWord[N]) <= $2015));
end;

function TfrmMain.IsUnitStart(AWord: Integer): Boolean;
var
  B: TEpubBook;
begin
  B := EpubUnum1.Book;
  if AWord <= 0 then
    Exit(True);
  if B.Words[AWord - 1].Document <> B.Words[AWord].Document then
    Exit(True);
  if (StepUnit <> UNIT_PARAGRAPH) and EpubEndsSentence(B.Words[AWord - 1].Text) then
    Exit(True);
  if (StepUnit = UNIT_PHRASE) and EndsPhrase(B.Words[AWord - 1].Text) then
    Exit(True);
  Result := WordBlock(AWord - 1) <> WordBlock(AWord);
end;

function TfrmMain.UnitStart(AWord: Integer): Integer;
begin
  Result := AWord;
  while not IsUnitStart(Result) do
    Dec(Result);
end;

function TfrmMain.UnitEnd(AWord: Integer): Integer;
var
  B: TEpubBook;
begin
  B := EpubUnum1.Book;
  Result := AWord;
  while (Result + 1 < B.WordCount) and not IsUnitStart(Result + 1) do
    Inc(Result);
end;

function TfrmMain.StepUnit: Integer;
begin
  if cbStep.ItemIndex < 0 then
    Result := UNIT_SENTENCE
  else if FLearn then
    Result := cbStep.ItemIndex
  else
    Result := cbStep.ItemIndex + UNIT_SENTENCE;
end;

procedure TfrmMain.FillSteps;
var
  Was: Integer;
  Handler: TNotifyEvent;
begin
  if cbStep.Count > 0 then
    Was := StepUnit
  else
    Was := UNIT_SENTENCE;
  Handler := cbStep.OnChange;
  cbStep.OnChange := nil;
  try
    cbStep.Items.Clear;
    if FLearn then
    begin
      cbStep.Items.Add('Phrase');
      Was := UNIT_PHRASE;   // the mode starts with phrases
    end
    else if Was < UNIT_SENTENCE then
      Was := UNIT_SENTENCE;
    cbStep.Items.Add('Sentence');
    cbStep.Items.Add('Paragraph');
    if FLearn then
      cbStep.ItemIndex := Was
    else
      cbStep.ItemIndex := Was - UNIT_SENTENCE;
  finally
    cbStep.OnChange := Handler;
  end;
  cbStepChange(nil);
end;

procedure TfrmMain.cbStepChange(Sender: TObject);
var
  Name: string;
begin
  case StepUnit of
    UNIT_PHRASE: Name := 'phrase';
    UNIT_PARAGRAPH: Name := 'paragraph';
  else
    Name := 'sentence';
  end;
  if FLearn then
  begin
    btnPrevClip.Hint := 'Previous ' + Name + ' - said, then stops';
    btnNextClip.Hint := 'Next ' + Name + ' - said, then stops';
  end
  else
  begin
    btnPrevClip.Hint := 'Previous ' + Name;
    btnNextClip.Hint := 'Next ' + Name;
  end;
  // the unit shown is redone in the new size at the next step
end;

procedure TfrmMain.btnLearnClick(Sender: TObject);
begin
  FLearn := not FLearn;
  btnLearn.IsPressed := FLearn;
  miLearn.IsChecked := FLearn;
  mnuMain.RecreateOSMenu;
  FLearnFirst := -1;
  FLearnLast := -1;
  if FLearn then
    StopPlaying;
  // obvious at a glance: green band and highlight, title, status, hints
  Caption := StringReplace(Caption, LEARN_TITLE, '', []);
  if FLearn then
  begin
    Caption := Caption + LEARN_TITLE;
    btnPlay.Hint := 'Say the highlighted words again (R)';
  end
  else
    btnPlay.Hint := 'Play / pause (P)';
  ApplyTheme;
  FillSteps;
  UpdateControls;
end;

function TfrmMain.OpenClipAudio(AClip: Integer): Boolean;
var
  B: TEpubBook;
  C: TEpubClip;
  Target: string;
  I, First: Integer;
begin
  Result := False;
  B := EpubUnum1.Book;
  if (B = nil) or (FPlayer = nil) or (AClip < 0) or (AClip > High(B.Clips)) then
    Exit;
  C := B.Clips[AClip];
  try
    if C.AudioPath <> FAudioPath then
    begin
      // FFmpeg streams a file: the book's audio is extracted once
      // The file name is made HERE, never from the path inside the book:
      // that path is the book's to choose, and one with backslashes and
      // '..', or an absolute one (which System.IOUtils.TPath.Combine returns as it is),
      // wrote the book's bytes anywhere on the disk. It is
      // <book number>-<first clip of this audio file><extension>, so a
      // second book never finds the first one's file under its own name.
      First := AClip;
      for I := 0 to AClip do
        if B.Clips[I].AudioPath = C.AudioPath then
        begin
          First := I;
          Break;
        end;
      Target := System.IOUtils.TPath.Combine(FAudioFolder, Format('%d-%d%s', [EpubUnum1.BookSerial, First,
        SafeAudioExtension(C.AudioPath)]));
      if not TFile.Exists(Target) then
      begin
        ForceDirectories(FAudioFolder);
        B.Zip.Extract(C.AudioPath, Target);
      end;
      FPlayer.Open(Target);
      FAudioPath := C.AudioPath;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      FSoundNote := E.Message;
      UpdateControls;
    end;
  end;
end;

procedure TfrmMain.SayWords(AFirst, ALast: Integer);
var
  B: TEpubBook;
  W, CFirst, CLast, C: Integer;
  T0, T1: Double;
begin
  B := EpubUnum1.Book;
  if (B = nil) or (AFirst < 0) or (ALast < AFirst) then
    Exit;
  StopPlaying;
  FLearnFirst := AFirst;
  FLearnLast := ALast;
  if B.Words[AFirst].Document <> View1.Document then
    View1.ShowDocument(B.Words[AFirst].Document);
  View1.Highlight(AFirst, ALast);
  View1.ScrollToWord(AFirst, True);
  SyncToc(AFirst);
  // the clips of the unit's first and last words that have one
  CFirst := -1;
  for W := AFirst to ALast do
  begin
    CFirst := ClipOfWord(W);
    if CFirst >= 0 then
      Break;
  end;
  CLast := -1;
  if CFirst >= 0 then
    for W := ALast downto AFirst do
    begin
      C := ClipOfWord(W);
      // one audio file: a unit across two parts is said up to the first's end
      if (C >= 0) and SameText(B.Clips[C].AudioPath, B.Clips[CFirst].AudioPath) and
        (B.Clips[C].ClipEnd > B.Clips[CFirst].ClipBegin) then
      begin
        CLast := C;
        Break;
      end;
    end;
  if CLast < 0 then
  begin
    // nothing to hear (not read in this recording): shown only, and the
    // unit said before is cut off
    if FPlayer <> nil then
      FPlayer.Pause;
    UpdateControls;
    Exit;
  end;
  // Play after this goes on from the unit
  FClip := CFirst;
  FSeekClip := CFirst;
  if not OpenClipAudio(CFirst) then
    Exit;
  T0 := Max(0, B.Clips[CFirst].ClipBegin - SAY_PAD_BEFORE);
  T1 := B.Clips[CLast].ClipEnd + SAY_PAD_AFTER;
  try
    FPlayer.PlayRange(T0, T1);
  except
    on E: Exception do
      FSoundNote := E.Message;
  end;
  UpdateControls;
end;

procedure TfrmMain.LearnStep(ADirection: Integer);
var
  B: TEpubBook;
  W: Integer;
begin
  B := EpubUnum1.Book;
  if (B = nil) or (B.WordCount = 0) then
    Exit;
  if FLearnFirst < 0 then
  begin
    // no unit said yet: from the word being read (paused) - Next goes
    // on to the unit after it, Previous says its own; nothing read yet:
    // the page's first unit
    W := CurrentWord;
    if W < 0 then
      Exit;
    W := UnitStart(W);
    if (ADirection > 0) and (FClip >= 0) then
    begin
      W := UnitEnd(W) + 1;
      if W >= B.WordCount then
        Exit;
    end;
  end
  else if ADirection > 0 then
  begin
    // the unit after the one shown (redone in the step chosen now)
    W := UnitEnd(UnitStart(FLearnLast)) + 1;
    if W >= B.WordCount then
      Exit;
  end
  else
  begin
    W := UnitStart(FLearnFirst);
    if W = 0 then
      Exit;
    W := UnitStart(W - 1);
  end;
  if (W < 0) or (W >= B.WordCount) then
    Exit;
  SayWords(W, UnitEnd(W));
end;

procedure TfrmMain.btnDarkClick(Sender: TObject);
begin
  FDark := not FDark;
  miDark.IsChecked := FDark;
  mnuMain.RecreateOSMenu;
  ApplyTheme;
end;

procedure TfrmMain.ApplyTheme;
var
  I: Integer;
begin
  // the page
  if FDark then
  begin
    View1.BackgroundColor := DARK_PAGE;
    View1.TextColor := DARK_TEXT;
    if FLearn then
      View1.HighlightColor := LEARN_HIGHLIGHT_DARK
    else
      View1.HighlightColor := DARK_HIGHLIGHT;
    View1.LinkColor := DARK_LINK;
    View1.NoteColor := DARK_NOTE;
  end
  else
  begin
    // TEpubView's own defaults: warm paper
    View1.BackgroundColor := $FFFBF7EF;
    View1.TextColor := $FF222222;
    if FLearn then
      View1.HighlightColor := LEARN_HIGHLIGHT
    else
      View1.HighlightColor := $FFFFE08A;
    View1.LinkColor := $FF1A5FB4;
    View1.NoteColor := $FFEDE6D6;
  end;
  // Learn to read: the green band behind the tool bar
  recLearn.Visible := FLearn;
  if FDark then
    recLearn.Fill.Color := LEARN_BAR_DARK
  else
    recLearn.Fill.Color := LEARN_BAR;
  // the window behind the tool bar
  if FDark then
  begin
    Fill.Kind := TBrushKind.Solid;
    Fill.Color := DARK_PANEL;
  end
  else
    Fill.Kind := TBrushKind.None;
  // the status line
  if FDark then
  begin
    lblStatus.StyledSettings := lblStatus.StyledSettings - [TStyledSetting.FontColor];
    lblStatus.TextSettings.FontColor := DARK_PANEL_TEXT;
  end
  else
    lblStatus.StyledSettings := lblStatus.StyledSettings + [TStyledSetting.FontColor];
  if FDark then
  begin
    lblSpeed.StyledSettings := lblSpeed.StyledSettings - [TStyledSetting.FontColor];
    lblSpeed.TextSettings.FontColor := DARK_PANEL_TEXT;
  end
  else
    lblSpeed.StyledSettings := lblSpeed.StyledSettings + [TStyledSetting.FontColor];
  // the contents: the items' text here, the background in TocApplyStyle
  for I := 0 to lbToc.Count - 1 do
    if FDark then
    begin
      lbToc.ListItems[I].StyledSettings := lbToc.ListItems[I].StyledSettings - [TStyledSetting.FontColor];
      lbToc.ListItems[I].TextSettings.FontColor := DARK_PANEL_TEXT;
    end
    else
      lbToc.ListItems[I].StyledSettings := lbToc.ListItems[I].StyledSettings + [TStyledSetting.FontColor];
  // Dark: FMX's transparent list box style, so the form's dark Fill shows
  // through - the plain style's white background (not reliably reachable
  // by name) left light text on white: unreadable (owner, zip 10).
  if FDark then
    lbToc.StyleLookup := 'transparentlistboxstyle'
  else
    lbToc.StyleLookup := '';
  lbToc.NeedStyleLookup;
  lbToc.ApplyStyleLookup;
  // the tool bar's buttons keep the platform style (their icons follow it)
end;

procedure TfrmMain.TocApplyStyle(Sender: TObject);
var
  O: TFmxObject;
begin
  // a fresh copy of the style: light as the style made it; dark: its
  // background made dark too, should the style still have one (a style
  // without 'transparentlistboxstyle' falls back to the plain one)
  if not FDark then
    Exit;
  O := lbToc.FindStyleResource('background');
  if O is TShape then
  begin
    TShape(O).Fill.Kind := TBrushKind.Solid;
    TShape(O).Fill.Color := DARK_PANEL;
  end
  else if O is TControl then
    TControl(O).Opacity := 0;   // a background of another kind: hidden
end;

procedure TfrmMain.btnPrevClick(Sender: TObject);
var
  K, W: Integer;
begin
  // the start of this chapter; at its start already, the one before
  W := CurrentWord;
  K := ChapterOfWord(W);
  if (K >= 0) and (FClip >= 0) and (W > FChapterWord[K]) and
    (ClipFromWord(FChapterWord[K]) <> FClip) then
    GoChapter(K)
  else if K > 0 then
    GoChapter(K - 1)
  else if K = 0 then
    GoChapter(0);
end;

procedure TfrmMain.btnNextClick(Sender: TObject);
var
  K: Integer;
begin
  K := ChapterOfWord(CurrentWord);
  if K < High(FChapterWord) then
    GoChapter(K + 1);
end;

procedure TfrmMain.btnSmallerClick(Sender: TObject);
begin
  if View1.FontSize > 10 then
    View1.FontSize := View1.FontSize - SIZE_STEP;
end;

procedure TfrmMain.btnLargerClick(Sender: TObject);
begin
  if View1.FontSize < 60 then
    View1.FontSize := View1.FontSize + SIZE_STEP;
end;

function TfrmMain.FirstClipOfDocument(ADoc: Integer): Integer;
var
  B: TEpubBook;
  I: Integer;
begin
  Result := -1;
  B := EpubUnum1.Book;
  if B = nil then
    Exit;
  for I := 0 to High(B.Clips) do
    if B.Clips[I].Document = ADoc then
      Exit(I);
end;

function TfrmMain.ClipOfWord(AWord: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FClipFirst) do
    if (AWord >= FClipFirst[I]) and (AWord <= FClipLast[I]) then
      Exit(I);
  Result := -1;
end;

procedure TfrmMain.StartClip(AClip: Integer);
var
  B: TEpubBook;
  C: TEpubClip;
begin
  B := EpubUnum1.Book;
  if (B = nil) or (AClip < 0) or (AClip > High(B.Clips)) then
    Exit;
  C := B.Clips[AClip];
  FSeekClip := -1;
  if FPlayer = nil then
  begin
    // no sound: show the clip at least
    FClip := AClip;
    if C.Document <> View1.Document then
      View1.ShowDocument(C.Document);
    if FClipFirst[AClip] >= 0 then
    begin
      View1.Highlight(FClipFirst[AClip], FClipLast[AClip]);
      View1.ScrollToWord(FClipFirst[AClip], True);
    end;
    UpdateControls;
    Exit;
  end;
  if not OpenClipAudio(AClip) then
    Exit;
  // Play reads on: Learn to read's unit is left
  FLearnFirst := -1;
  try
    FPlayer.Play(C.ClipBegin);
  except
    on E: Exception do
    begin
      FSoundNote := E.Message;
      UpdateControls;
      Exit;
    end;
  end;
  FPlaying := True;
  FClip := -2;   // the timer highlights the clip it finds
  tmPlay.Enabled := True;
  UpdateControls;
end;

procedure TfrmMain.StopPlaying;
begin
  tmPlay.Enabled := False;
  if FPlaying and (FPlayer <> nil) then
    FPlayer.Pause;
  FPlaying := False;
  UpdateControls;
end;

procedure TfrmMain.btnPlayClick(Sender: TObject);
var
  B: TEpubBook;
  C: Integer;
begin
  B := EpubUnum1.Book;
  if (B = nil) or (Length(B.Clips) = 0) then
    Exit;
  if FLearn then
  begin
    // Learn to read: Play says what is highlighted again (a hard word:
    // click it, then Play as often as needed) - it never reads on
    StopPlaying;
    if FLearnFirst >= 0 then
      SayWords(FLearnFirst, FLearnLast)
    else if CurrentWord >= 0 then
      SayWords(UnitStart(CurrentWord), UnitEnd(UnitStart(CurrentWord)));
    Exit;
  end;
  if FPlaying then
  begin
    StopPlaying;
    Exit;
  end;
  if FSeekClip >= 0 then
  begin
    // a jump while paused: play from there
    C := FSeekClip;
    StartClip(C);
    Exit;
  end;
  if (FPlayer <> nil) and (FClip >= 0) and (B.Clips[FClip].Document = View1.Document) and
    (FPlayer.FileName <> '') and not FPlayer.Ended then
  begin
    // resume where it was paused
    FPlayer.Resume;
    FPlaying := True;
    tmPlay.Enabled := True;
    UpdateControls;
    Exit;
  end;
  C := FirstClipOfDocument(View1.Document);
  if C < 0 then
    C := 0;
  StartClip(C);
end;

procedure TfrmMain.btnPrevClipClick(Sender: TObject);
var
  B: TEpubBook;
  W, S, C: Integer;
  AtStart: Boolean;
begin
  if FLearn then
  begin
    LearnStep(-1);
    Exit;
  end;
  B := EpubUnum1.Book;
  W := CurrentWord;
  if (B = nil) or (W < 0) or (Length(B.Clips) = 0) then
    Exit;
  S := UnitStart(W);
  C := ClipFromWord(S);
  // at (or just past) the start of this sentence: the one before
  if FPlaying and (C >= 0) and (FPlayer <> nil) and SameText(B.Clips[C].AudioPath, FAudioPath) then
    AtStart := FPlayer.Position - B.Clips[C].ClipBegin < BACK_GRACE
  else
    AtStart := (C < 0) or (FClip <= C);
  if AtStart and (S > 0) then
  begin
    S := UnitStart(S - 1);
    C := ClipFromWord(S);
  end;
  if C >= 0 then
    GoClip(C);
end;

procedure TfrmMain.btnNextClipClick(Sender: TObject);
var
  B: TEpubBook;
  W, C: Integer;
begin
  if FLearn then
  begin
    LearnStep(1);
    Exit;
  end;
  B := EpubUnum1.Book;
  W := CurrentWord;
  if (B = nil) or (W < 0) or (Length(B.Clips) = 0) then
    Exit;
  repeat
    Inc(W);
  until (W >= B.WordCount) or IsUnitStart(W);
  if W >= B.WordCount then
    Exit;
  C := ClipFromWord(W);
  // always forward, even when a clip holds several sentences
  if (C >= 0) and (C <= FClip) then
    C := FClip + 1;
  if (C >= 0) and (C <= High(B.Clips)) then
    GoClip(C);
end;

procedure TfrmMain.View1WordClick(Sender: TObject; AWord: Integer);
var
  C: Integer;
begin
  if FLearn then
  begin
    // the phrase / sentence / paragraph (cbStep) the word is in - a click
    // that said one word left Play repeating just that word (owner)
    SayWords(UnitStart(AWord), UnitEnd(UnitStart(AWord)));
    Exit;
  end;
  C := ClipOfWord(AWord);
  if C >= 0 then
    StartClip(C);
end;

procedure TfrmMain.View1DocumentChange(Sender: TObject);
begin
  UpdateControls;
end;

procedure TfrmMain.tmPlayTimer(Sender: TObject);
var
  B: TEpubBook;
  T: Double;
  C, I: Integer;
begin
  B := EpubUnum1.Book;
  if (B = nil) or (FPlayer = nil) or not FPlaying then
    Exit;
  // the time of the sound really being heard
  T := FPlayer.Position;
  C := B.ClipAt(FAudioPath, T);
  if (C <> FClip) and (C >= 0) then
  begin
    FClip := C;
    if B.Clips[C].Document <> View1.Document then
      View1.ShowDocument(B.Clips[C].Document);
    if FClipFirst[C] >= 0 then
    begin
      View1.Highlight(FClipFirst[C], FClipLast[C]);
      View1.ScrollToWord(FClipFirst[C], True);
      SyncToc(FClipFirst[C]);
    end;
    UpdateControls;
  end;
  if FPlayer.LastError <> '' then
  begin
    FSoundNote := FPlayer.LastError;
    StopPlaying;
    Exit;
  end;
  // this audio file has played out: go on with the next file's first clip
  if FPlayer.Ended then
  begin
    I := Max(FClip, 0);
    while (I <= High(B.Clips)) and (B.Clips[I].AudioPath = FAudioPath) do
      Inc(I);
    if I <= High(B.Clips) then
      StartClip(I)
    else
      StopPlaying;
  end;
end;

procedure TfrmMain.UpdateControls;
var
  B: TEpubBook;
  S: string;
begin
  B := EpubUnum1.Book;
  btnPrev.Enabled := (B <> nil) and (Length(FChapterWord) > 0);
  btnNext.Enabled := (B <> nil) and (ChapterOfWord(CurrentWord) < High(FChapterWord));
  btnPlay.Enabled := (B <> nil) and (Length(B.Clips) > 0);
  btnPrevClip.Enabled := btnPlay.Enabled;
  btnNextClip.Enabled := btnPlay.Enabled;
  if FPlaying then
    SetIcon(btnPlay, ICON_PAUSE)
  else
    SetIcon(btnPlay, ICON_PLAY);
  if B = nil then
    S := 'No book open'
  else
  begin
    S := Format('%s - document %d of %d', [B.Title, View1.Document + 1, Length(B.Documents)]);
    if Length(B.Clips) = 0 then
      S := S + ' - no audio (no media overlays)'
    else if FPlaying then
      S := S + Format(' - playing %s', [ExtractFileName(StringReplace(FAudioPath, '/', PathDelim, [rfReplaceAll]))]);
  end;
  if FSoundNote <> '' then
    S := S + ' - ' + FSoundNote;
  if FOpenWithNote <> '' then
    S := S + ' - ' + FOpenWithNote;
  if FLearn then
    S := 'LEARN TO READ - ' + S;
  lblStatus.Text := S;
end;

end.
