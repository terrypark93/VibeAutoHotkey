program VibeAutoHotkey;

{$R VibeAutoHotkey.res}

uses
  Vcl.Forms,
  MainForm in 'src\MainForm.pas',
  UIAFocus in 'src\UIAFocus.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainWindow, MainWindow);
  Application.Run;
end.
