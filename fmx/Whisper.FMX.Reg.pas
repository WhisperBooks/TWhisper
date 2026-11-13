{ @abstract(Design-time registration of the Whisper FMX component.)

  Compiled only into the design-time package dclWhisperAPIFMX, which puts
  @code(TWhisperAPI) (FireMonkey) on the "WhisperAPI" page of the tool palette. }
unit Whisper.FMX.Reg;

{$I ..\lib\Whisper.inc}

interface

{ Registers the FMX TWhisperAPI on the "WhisperAPI" palette page. }
procedure Register;

implementation

uses
  Classes, DesignIntf, DesignEditors, FMX.Types, Whisper.FMX;

type
  { Adds the units the IDE-generated TWhisperAPI event handlers need
    (TWhisperSegment, TWhisperLogLevel, TWhisperParams, ...) to the form's
    uses clause. }
  TWhisperSelectionEditor = class(TSelectionEditor)
  public
    { Names Whisper.Types, Whisper.API, Whisper.Core and Whisper.Components. }
    procedure RequiresUnits(Proc: TGetStrProc); override;
  end;

procedure TWhisperSelectionEditor.RequiresUnits(Proc: TGetStrProc);
begin
  Proc('Whisper.Types');
  Proc('Whisper.API');
  Proc('Whisper.Core');
  Proc('Whisper.Components');
end;

procedure Register;
begin
  // FMX class group: lets a VCL TWhisperAPI of the same name be installed as
  // well, as with FMX / VCL TButton.
  GroupDescendentsWith(TWhisperAPI, TFmxObject);
  RegisterComponents('WhisperAPI', [TWhisperAPI]);
  RegisterSelectionEditor(TWhisperAPI, TWhisperSelectionEditor);
end;

end.
