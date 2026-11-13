{ @abstract(Cross-platform, cross-compiler loading of dynamic libraries
  (DLL / .so / .dylib).)

  @link(TWhisperDynLib) wraps one loaded library. It follows the approach of
  Castle Game Engine's TDynLib (one object per library, a selectable policy
  for missing symbols, a Load that can raise or return nil) with these
  differences:

  @unorderedList(
    @item(Library search covers the executable's folder and, on macOS, the
      app bundle's Contents/MacOS and Contents/Frameworks folders before the
      operating-system search path. Linux dlopen does not look next to the
      executable unless the binary has an $ORIGIN rpath.)
    @item(Failures report every path tried and the OS error message.)
    @item(Warnings go to an event (@link(TWhisperDynLib.OnWarning)), so there is
      no dependency on any logging framework.)
    @item(Symbols are looked up by @code(string); the platform-specific
      conversion is done here.)
    @item(Missing optional symbols are collected in
      @link(TWhisperDynLib.MissingSymbols) for diagnostics.)
  )

  Compiles with Delphi (Windows, macOS, Linux) and Free Pascal.

  @bold(Important:) procedural variables bound from a library dangle once the
  library is freed. Owners of such variables must clear them before (or
  immediately after) freeing the @link(TWhisperDynLib) - see
  @code(TWhisperLib.Unload) for the pattern.

  Adapted from TSteamDynLib of TSteamAPI (Steamworks.DynLib), same author
  and conventions; only names and examples differ.

  Example:
  @longCode(#
  var
    Lib: TWhisperDynLib;
    whisper_print_system_info: function: PAnsiChar; cdecl;
  begin
    Lib := TWhisperDynLib.Load('whisper.dll', False);
    if Lib = nil then
      Exit; // not installed
    try
      Lib.Bind(whisper_print_system_info, 'whisper_print_system_info');
      ...
    finally
      whisper_print_system_info := nil;
      FreeAndNil(Lib);
    end;
  end;
  #)
}
unit Whisper.DynLib;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes
  {$ifdef FPC}, DynLibs{$endif}
  {$if defined(MSWINDOWS) and not defined(FPC)}, Windows{$endif}
  {$if not defined(MSWINDOWS) and not defined(FPC)}, Posix.Dlfcn{$endif};

type
  { Native library handle. }
  TWhisperLibHandle = {$ifdef FPC}TLibHandle{$else}HMODULE{$endif};

const
  { Value of a @link(TWhisperLibHandle) that does not refer to a library. }
  InvalidWhisperLibHandle = {$ifdef FPC}NilHandle{$else}0{$endif};

type
  { Raised when a library cannot be loaded, or a required symbol is missing
    while @link(TWhisperDynLib.SymbolErrorMode) is @link(semRaise). }
  EWhisperDynLibError = class(Exception);

  { What @link(TWhisperDynLib.Symbol) and @link(TWhisperDynLib.Bind) do when a
    required symbol is missing. }
  TWhisperSymbolErrorMode = (
    { Raise @link(EWhisperDynLibError). }
    semRaise,
    { Return @nil silently. }
    semReturnNil,
    { Fire @link(TWhisperDynLib.OnWarning) and return @nil. }
    semWarnAndReturnNil
  );

  { Event used for non-fatal library problems. }
  TWhisperDynLibWarningEvent = procedure(Sender: TObject; const AMessage: string) of object;

  { One loaded dynamic library. Create it with @link(Load) or @link(LoadFirst);
    @link(Destroy) unloads it. }
  TWhisperDynLib = class
  private
    { Backing field of @link(Handle). }
    FHandle: TWhisperLibHandle;
    { Backing field of @link(Name). }
    FName: string;
    { Backing field of @link(FileName). }
    FFileName: string;
    { Backing field of @link(SymbolErrorMode). }
    FSymbolErrorMode: TWhisperSymbolErrorMode;
    { Backing field of @link(MissingSymbols). }
    FMissing: TStringList;
    { Backing field of @link(OnWarning). }
    FOnWarning: TWhisperDynLibWarningEvent;
    { Loads one file. @returns(@false with AError set on failure.) }
    class function TryLoadFile(const AFileName: string; out AHandle: TWhisperLibHandle;
      out AError: string): Boolean; static;
    { GetProcAddress without any error handling. }
    function RawSymbol(const AName: string): Pointer;
    { Raises @link(OnWarning) if assigned. }
    procedure Warn(const AMessage: string);
  public
    { Wraps an already loaded handle. Normally use @link(Load) instead.
      @param(AName  Name the library was requested by.)
      @param(AFileName  Full file name, if known.)
      @param(AHandle  Valid handle; ownership passes to this object.)
      @raises(EWhisperDynLibError if AHandle is invalid.) }
    constructor Create(const AName, AFileName: string; AHandle: TWhisperLibHandle);

    { Unloads the library. Procedural variables bound from it become invalid. }
    destructor Destroy; override;

    { Candidate file names tried, in order, when loading AName.
      If AName contains a path only AName itself is returned. Otherwise:
      the executable's folder (made absolute), (macOS) the bundle's Contents/MacOS and
      Contents/Frameworks, then the bare name for the OS search path. }
    class function CandidatePaths(const AName: string): TStringList; static;

    { Loads a library.
      @param(AName  File name with or without a path, e.g. @code('whisper.dll').)
      @param(ARaiseOnError  If @true a failure raises @link(EWhisperDynLibError),
        otherwise @nil is returned.)
      @returns(The loaded library, or @nil (only when ARaiseOnError is @false).)
      @raises(EWhisperDynLibError when the library cannot be loaded and ARaiseOnError is @true.) }
    class function Load(const AName: string; ARaiseOnError: Boolean = True): TWhisperDynLib;

    { Loads the first library of ANames that can be loaded.
      Useful when a library ships under several names. }
    class function LoadFirst(const ANames: array of string; ARaiseOnError: Boolean = True): TWhisperDynLib;

    { Address of an exported symbol, honouring @link(SymbolErrorMode) when it
      is missing.
      @raises(EWhisperDynLibError if missing and SymbolErrorMode = semRaise.) }
    function Symbol(const AName: string): Pointer;

    { @true if the library exports AName. Never raises, never warns. }
    function HasSymbol(const AName: string): Boolean;

    { Binds an export into a procedural variable.

      @param(AProc  Procedural variable (passed untyped) that receives the address.)
      @param(AName  Export name.)
      @param(ARequired  When @true a missing symbol is handled by
        @link(SymbolErrorMode); when @false it silently yields @nil and is
        recorded in @link(MissingSymbols).)
      @returns(@true if the symbol was found.)

      @longCode(#
      var
        whisper_lang_max_id: function: Int32; cdecl;
      ...
      Lib.Bind(whisper_lang_max_id, 'whisper_lang_max_id');
      #) }
    function Bind(var AProc; const AName: string; ARequired: Boolean = True): Boolean;

    { Name the library was requested by. }
    property Name: string read FName;
    { File the library was actually loaded from (best effort). }
    property FileName: string read FFileName;
    { Native handle. }
    property Handle: TWhisperLibHandle read FHandle;
    { Policy for missing required symbols. Default @link(semRaise). }
    property SymbolErrorMode: TWhisperSymbolErrorMode read FSymbolErrorMode write FSymbolErrorMode default semRaise;
    { Symbols requested with @link(Bind) or @link(Symbol) that were not found. }
    property MissingSymbols: TStringList read FMissing;
    { Fired for @link(semWarnAndReturnNil) and non-fatal unload problems. }
    property OnWarning: TWhisperDynLibWarningEvent read FOnWarning write FOnWarning;
  end;

implementation

{ TWhisperDynLib }

constructor TWhisperDynLib.Create(const AName, AFileName: string; AHandle: TWhisperLibHandle);
begin
  inherited Create;
  if AHandle = InvalidWhisperLibHandle then
    raise EWhisperDynLibError.CreateFmt('Invalid handle for library "%s"', [AName]);
  FName := AName;
  FFileName := AFileName;
  FHandle := AHandle;
  FSymbolErrorMode := semRaise;
  FMissing := TStringList.Create;
  FMissing.Sorted := True;
  FMissing.Duplicates := dupIgnore;
end;

destructor TWhisperDynLib.Destroy;
var
  Ok: Boolean;
begin
  if FHandle <> InvalidWhisperLibHandle then
  begin
    {$ifdef FPC}
    Ok := DynLibs.UnloadLibrary(FHandle);
    {$else}
      {$ifdef MSWINDOWS}
      Ok := Windows.FreeLibrary(FHandle);
      {$else}
      // Delphi on POSIX: FreeLibrary's result is unreliable (also noted by CGE)
      FreeLibrary(FHandle);
      Ok := True;
      {$endif}
    {$endif}
    if not Ok then
      Warn(Format('Unloading library "%s" failed', [FName]));
    FHandle := InvalidWhisperLibHandle;
  end;
  FMissing.Free;
  inherited;
end;

procedure TWhisperDynLib.Warn(const AMessage: string);
begin
  if Assigned(FOnWarning) then
    FOnWarning(Self, AMessage);
end;

class function TWhisperDynLib.TryLoadFile(const AFileName: string; out AHandle: TWhisperLibHandle;
  out AError: string): Boolean;
begin
  AError := '';
  {$ifdef FPC}
  AHandle := DynLibs.LoadLibrary(AFileName);
  if AHandle = InvalidWhisperLibHandle then
    AError := DynLibs.GetLoadErrorStr;
  {$else}
    {$ifdef MSWINDOWS}
    AHandle := Windows.LoadLibrary(PChar(AFileName));
    if AHandle = InvalidWhisperLibHandle then
      AError := SysErrorMessage(GetLastError);
    {$else}
    AHandle := LoadLibrary(PChar(AFileName));
    if AHandle = InvalidWhisperLibHandle then
      AError := string(UTF8String(dlerror));
    {$endif}
  {$endif}
  Result := AHandle <> InvalidWhisperLibHandle;
end;

class function TWhisperDynLib.CandidatePaths(const AName: string): TStringList;
var
  ExeDir: string;
begin
  Result := TStringList.Create;
  if ExtractFilePath(AName) <> '' then
  begin
    Result.Add(AName);
    Exit;
  end;
  // ParamStr(0) is argv[0] on Linux / macOS and may be relative to the
  // current directory ('WhisperConsole/WhisperConsole'): make it absolute so the
  // path tried, loaded and logged is exact.
  ExeDir := IncludeTrailingPathDelimiter(ExpandFileName(ExtractFilePath(ParamStr(0))));
  Result.Add(ExeDir + AName);
  {$ifdef WHISPER_MACOS}
  // <App>.app/Contents/MacOS/<exe>  ->  also try Contents/Frameworks
  Result.Add(ExpandFileName(ExeDir + '..' + PathDelim + 'Frameworks' + PathDelim + AName));
  {$endif}
  Result.Add(AName); // OS search path
end;

class function TWhisperDynLib.Load(const AName: string; ARaiseOnError: Boolean): TWhisperDynLib;
var
  Paths: TStringList;
  Errors: string;
  I: Integer;
  H: TWhisperLibHandle;
  Err: string;
begin
  Result := nil;
  Errors := '';
  {$ifdef WHISPER_UNSUPPORTED_PLATFORM}
  if ARaiseOnError then
    raise EWhisperDynLibError.CreateFmt('Dynamic library "%s" is not supported on this platform', [AName]);
  Exit;
  {$endif}
  Paths := CandidatePaths(AName);
  try
    for I := 0 to Paths.Count - 1 do
    begin
      // Explicit paths that do not exist are listed but not loaded;
      // the bare name is always tried (OS search path)
      if (ExtractFilePath(Paths[I]) <> '') and not FileExists(Paths[I]) then
      begin
        Errors := Errors + sLineBreak + '  ' + Paths[I] + ': not present';
        Continue;
      end;
      if TryLoadFile(Paths[I], H, Err) then
        Exit(TWhisperDynLib.Create(AName, Paths[I], H));
      Errors := Errors + sLineBreak + '  ' + Paths[I];
      if Err <> '' then
        Errors := Errors + ': ' + Err;
    end;
  finally
    Paths.Free;
  end;
  if ARaiseOnError then
    raise EWhisperDynLibError.CreateFmt('Cannot load dynamic library "%s". Tried:%s', [AName, Errors]);
end;

class function TWhisperDynLib.LoadFirst(const ANames: array of string; ARaiseOnError: Boolean): TWhisperDynLib;
var
  I: Integer;
  Msg: string;
begin
  Msg := '';
  for I := Low(ANames) to High(ANames) do
  begin
    try
      Result := Load(ANames[I], True);
      Exit;
    except
      on E: EWhisperDynLibError do
        Msg := Msg + sLineBreak + E.Message;
    end;
  end;
  Result := nil;
  if ARaiseOnError then
    raise EWhisperDynLibError.Create('None of the candidate libraries could be loaded:' + Msg);
end;

function TWhisperDynLib.RawSymbol(const AName: string): Pointer;
begin
  {$ifdef FPC}
  Result := DynLibs.GetProcedureAddress(FHandle, AnsiString(AName));
  {$else}
    {$ifdef MSWINDOWS}
    Result := Windows.GetProcAddress(FHandle, PAnsiChar(AnsiString(AName)));
    {$else}
    Result := GetProcAddress(FHandle, PChar(AName));
    {$endif}
  {$endif}
end;

function TWhisperDynLib.HasSymbol(const AName: string): Boolean;
begin
  Result := RawSymbol(AName) <> nil;
end;

function TWhisperDynLib.Symbol(const AName: string): Pointer;
begin
  Result := RawSymbol(AName);
  if Result = nil then
  begin
    FMissing.Add(AName);
    case FSymbolErrorMode of
      semRaise:
        raise EWhisperDynLibError.CreateFmt('Symbol "%s" not found in library "%s"', [AName, FFileName]);
      semWarnAndReturnNil:
        Warn(Format('Symbol "%s" not found in library "%s"', [AName, FFileName]));
      semReturnNil: ;
    end;
  end;
end;

function TWhisperDynLib.Bind(var AProc; const AName: string; ARequired: Boolean): Boolean;
begin
  if ARequired then
    Pointer(AProc) := Symbol(AName)
  else
  begin
    Pointer(AProc) := RawSymbol(AName);
    if Pointer(AProc) = nil then
      FMissing.Add(AName);
  end;
  Result := Pointer(AProc) <> nil;
end;

end.
