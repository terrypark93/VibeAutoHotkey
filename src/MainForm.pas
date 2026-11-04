unit MainForm;


interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.JSON, System.IOUtils, System.IniFiles, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Dialogs, Vcl.Menus;

type
  TMainWindow = class(TForm)
  private
    FList: TListView;
    FLog: TMemo;
    FTray: TTrayIcon;
    FTrayMenu: TPopupMenu;
    FRefresh, FSave, FTest: TButton;
    FAction: TComboBox;
    FKey: TComboBox;
    FActions: array[0..2] of Integer;
    FKeys: array[0..2] of Word;
    FRegistered: array[0..2] of Boolean;
    FPreferredPID: array[0..2] of DWORD;
    procedure SelectionChanged(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ActionChanged(Sender: TObject);
    procedure KeyChanged(Sender: TObject);
    procedure RegisterKeys;
    procedure LoadSettings;
    function SettingsPath: string;
    procedure RefreshClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure TestClick(Sender: TObject);
    procedure HotKey(var Msg: TWMHotKey); message WM_HOTKEY;
    procedure FocusResult(var Msg: TMessage); message WM_APP + 1;
    procedure RefreshProcesses;
    procedure Log(const S: string);
    procedure RestoreFromTray(Sender: TObject);
    procedure ExitFromTray(Sender: TObject);
    procedure FormMinimized(var Msg: TWMSize); message WM_SIZE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainWindow: TMainWindow;

implementation

uses Winapi.TlHelp32, UIAFocus;

const
  Names: array[0..2] of string = ('ChatGPT.exe', 'ChatGPT Classic.exe', 'Claude.exe');
  Keys: array[0..2] of Word = (VK_F9, VK_F10, VK_F11);

function WindowForProcess(PID: DWORD): HWND;
var
  H: HWND;
  WindowPID: DWORD;
begin
  Result := 0;
  H := GetTopWindow(0);
  while H <> 0 do
  begin
    GetWindowThreadProcessId(H, @WindowPID);
    if (WindowPID = PID) and (GetWindow(H, GW_OWNER) = 0) and
       IsWindowVisible(H) then Exit(H);
    H := GetWindow(H, GW_HWNDNEXT);
  end;
end;

function TargetIsForeground(Target: HWND): Boolean;
var Foreground: HWND; TargetPID, ForegroundPID: DWORD;
begin
  Result := False;
  Foreground := GetForegroundWindow;
  if (Target = 0) or (Foreground = 0) then Exit;
  if (Foreground = Target) or
     (GetAncestor(Foreground, GA_ROOTOWNER) = Target) then Exit(True);
  GetWindowThreadProcessId(Target, @TargetPID);
  GetWindowThreadProcessId(Foreground, @ForegroundPID);
  Result := (TargetPID <> 0) and (TargetPID = ForegroundPID);
end;

procedure TMainWindow.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.WndParent := 0;
  Params.ExStyle := (Params.ExStyle or WS_EX_APPWINDOW) and not WS_EX_TOOLWINDOW;
end;

constructor TMainWindow.Create(AOwner: TComponent);
var
  I: Integer;
  MenuItem: TMenuItem;
begin
  inherited CreateNew(AOwner);
  Caption := 'VibeAutoHotkey';
  Icon.Handle := LoadIcon(HInstance, 'MAINICON');
  Application.Icon.Assign(Icon);
  FTrayMenu := TPopupMenu.Create(Self);
  MenuItem := TMenuItem.Create(FTrayMenu);
  MenuItem.Caption := 'VibeAutoHotkey 열기';
  MenuItem.OnClick := RestoreFromTray;
  FTrayMenu.Items.Add(MenuItem);
  MenuItem := TMenuItem.Create(FTrayMenu);
  MenuItem.Caption := '종료';
  MenuItem.OnClick := ExitFromTray;
  FTrayMenu.Items.Add(MenuItem);
  FTray := TTrayIcon.Create(Self);
  FTray.Icon.Assign(Icon);
  FTray.Hint := 'VibeAutoHotkey';
  FTray.PopupMenu := FTrayMenu;
  FTray.OnDblClick := RestoreFromTray;
  FTray.Visible := True;
  Width := 900;
  Height := 560;
  Position := poScreenCenter;
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alTop;
  FList.Height := 330;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  with FList.Columns.Add do begin Caption := '프로세스'; Width := 190 end;
  with FList.Columns.Add do begin Caption := 'PID'; Width := 80 end;
  with FList.Columns.Add do begin Caption := '창 제목'; Width := 390 end;
  with FList.Columns.Add do begin Caption := '단축키'; Width := 130 end;
  FRefresh := TButton.Create(Self);
  FRefresh.Parent := Self;
  FRefresh.SetBounds(10, 340, 110, 30);
  FRefresh.Caption := '새로고침';
  FRefresh.OnClick := RefreshClick;
  FSave := TButton.Create(Self);
  FSave.Parent := Self;
  FSave.SetBounds(130, 340, 110, 30);
  FSave.Caption := '설정 저장';
  FSave.OnClick := SaveClick;
  FTest := TButton.Create(Self);
  FTest.Parent := Self;
  FTest.SetBounds(250, 340, 110, 30);
  FTest.Caption := '동작 테스트';
  FTest.OnClick := TestClick;
  FAction := TComboBox.Create(Self);
  FAction.Parent := Self;
  FAction.SetBounds(375, 342, 250, 25);
  FAction.Style := csDropDownList;
  FAction.Items.Add('창 활성화만');
  FAction.Items.Add('입력창 포커스');
  FAction.Items.Add('입력창 포커스 + 마이크');
  FAction.ItemIndex := 0;
  FAction.OnChange := ActionChanged;
  FKey := TComboBox.Create(Self);
  FKey.Parent := Self;
  FKey.SetBounds(640, 342, 140, 25);
  FKey.Style := csDropDownList;
  for I := 1 to 12 do FKey.Items.Add('Ctrl+Alt+F' + I.ToString);
  FKey.OnChange := KeyChanged;
  FList.OnSelectItem := SelectionChanged;
  FLog := TMemo.Create(Self);
  FLog.Parent := Self;
  FLog.SetBounds(10, 380, 860, 130);
  FLog.Anchors := [akLeft, akTop, akRight, akBottom];
  FLog.ReadOnly := True;
  for I := 0 to 2 do
  begin
    FKeys[I] := Keys[I];
    FActions[I] := 1;
  end;
  LoadSettings;
  RegisterKeys;
  RefreshProcesses;
end;

procedure TMainWindow.RegisterKeys;
var I, J, Candidate: Integer; Used: Boolean;
begin
  for I := 0 to 2 do
  begin
    if FRegistered[I] then UnregisterHotKey(Handle, I + 1);
    FRegistered[I] := False;
    for J := 0 to I - 1 do
      if FKeys[J] = FKeys[I] then
      begin
        Log('설정의 중복 단축키: ' + Names[I]);
        Break;
      end;
    if J < I then Continue;
    FRegistered[I] := RegisterHotKey(Handle, I + 1,
      MOD_CONTROL or MOD_ALT or MOD_NOREPEAT, FKeys[I]);
    if not FRegistered[I] then
    begin
      Log('단축키 충돌: ' + Names[I] + ' Ctrl+Alt+F' +
        (FKeys[I] - VK_F1 + 1).ToString);
      for Candidate := VK_F12 downto VK_F1 do
      begin
        Used := False;
        for J := 0 to 2 do
          if (J <> I) and (FKeys[J] = Candidate) then Used := True;
        if Used then Continue;
        if RegisterHotKey(Handle, I + 1, MOD_CONTROL or MOD_ALT or MOD_NOREPEAT,
          Candidate) then
        begin
          FKeys[I] := Candidate;
          FRegistered[I] := True;
          Log('대체 단축키 등록: ' + Names[I] + ' Ctrl+Alt+F' +
            (Candidate - VK_F1 + 1).ToString);
          Break;
        end;
      end;
      if not FRegistered[I] then Log('사용 가능한 단축키 없음: ' + Names[I]);
    end;
  end;
end;

function TMainWindow.SettingsPath: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, 'VibeAutoHotkey.json');
end;

procedure TMainWindow.LoadSettings;
var J: TJSONObject; A: TJSONArray; I, V: Integer;
begin
  if not TFile.Exists(SettingsPath) then Exit;
  try
    J := TJSONObject.ParseJSONValue(TFile.ReadAllText(SettingsPath, TEncoding.UTF8)) as TJSONObject;
    try
      if J = nil then Exit;
      A := J.GetValue<TJSONArray>('actions');
      if A <> nil then
        for I := 0 to 2 do
          if (I < A.Count) and TryStrToInt(A.Items[I].Value, V) and (V >= 0) and (V <= 2) then
            FActions[I] := V;
      A := J.GetValue<TJSONArray>('keys');
      if A <> nil then
        for I := 0 to 2 do
          if (I < A.Count) and TryStrToInt(A.Items[I].Value, V) and
             (V >= VK_F1) and (V <= VK_F12) then FKeys[I] := V;
    finally J.Free end;
  except on E: Exception do Log('설정 읽기 실패: ' + E.Message) end;
end;

procedure TMainWindow.SelectionChanged(Sender: TObject; Item: TListItem; Selected: Boolean);
var I: Integer;
begin
  if not Selected then Exit;
  for I := 0 to 2 do
    if SameText(Item.Caption, Names[I]) then
    begin
      FPreferredPID[I] := StrToIntDef(Item.SubItems[0], 0);
      FAction.ItemIndex := FActions[I];
      FKey.ItemIndex := FKeys[I] - VK_F1;
      Exit
    end;
end;

procedure TMainWindow.KeyChanged(Sender: TObject);
var I, J: Integer; NewKey: Word;
begin
  if (FList.Selected = nil) or (FKey.ItemIndex < 0) then Exit;
  NewKey := VK_F1 + FKey.ItemIndex;
  for I := 0 to 2 do
    if SameText(FList.Selected.Caption, Names[I]) then
    begin
      for J := 0 to 2 do
        if (J <> I) and (FKeys[J] = NewKey) then
        begin
          Log('중복 단축키: Ctrl+Alt+F' + (FKey.ItemIndex + 1).ToString);
          FKey.ItemIndex := FKeys[I] - VK_F1;
          Exit;
        end;
      FKeys[I] := NewKey;
      RegisterKeys;
      RefreshProcesses;
      Exit;
    end;
end;

procedure TMainWindow.ActionChanged(Sender: TObject);
var I: Integer;
begin
  if FList.Selected = nil then Exit;
  for I := 0 to 2 do
    if SameText(FList.Selected.Caption, Names[I]) then FActions[I] := FAction.ItemIndex;
end;

destructor TMainWindow.Destroy;
var I: Integer;
begin
  FTray.Visible := False;
  for I := 0 to 2 do if FRegistered[I] then UnregisterHotKey(Handle, I + 1);
  inherited;
end;

procedure TMainWindow.FormMinimized(var Msg: TWMSize);
begin
  inherited;
  if Msg.SizeType = SIZE_MINIMIZED then Hide;
end;

procedure TMainWindow.RestoreFromTray(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  SetForegroundWindow(Handle);
end;

procedure TMainWindow.ExitFromTray(Sender: TObject);
begin
  Close;
end;

procedure TMainWindow.Log(const S: string);
begin
  FLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' ' + S);
end;

procedure TMainWindow.RefreshProcesses;
var
  Snapshot: THandle;
  Entry: TProcessEntry32;
  I: Integer;
  Item: TListItem;
  H: HWND;
  Title: array[0..255] of Char;
begin
  FList.Items.Clear;
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snapshot = INVALID_HANDLE_VALUE then begin Log('프로세스 목록 조회 실패'); Exit end;
  try
    Entry.dwSize := SizeOf(Entry);
    if Process32First(Snapshot, Entry) then repeat
      for I := 0 to 2 do
        if SameText(Entry.szExeFile, Names[I]) then
        begin
          H := WindowForProcess(Entry.th32ProcessID);
          if H = 0 then Continue;
          Title[0] := #0;
          if H <> 0 then GetWindowText(H, Title, Length(Title));
          Item := FList.Items.Add;
          Item.Caption := Names[I];
          Item.SubItems.Add(Entry.th32ProcessID.ToString);
          Item.SubItems.Add(Title);
          Item.SubItems.Add('Ctrl+Alt+F' + (FKeys[I] - VK_F1 + 1).ToString);
          Item.Data := Pointer(NativeUInt(H));
        end;
    until not Process32Next(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
end;

procedure TMainWindow.RefreshClick(Sender: TObject);
begin RefreshProcesses end;

procedure TMainWindow.SaveClick(Sender: TObject);
var J: TJSONObject; A: TJSONArray; I: Integer;
begin
  J := TJSONObject.Create;
  try
    A := TJSONArray.Create;
    for I := 0 to 2 do A.Add(FActions[I]);
    J.AddPair('actions', A);
    A := TJSONArray.Create;
    for I := 0 to 2 do A.Add(FKeys[I]);
    J.AddPair('keys', A);
    TFile.WriteAllText(SettingsPath, J.ToJSON, TEncoding.UTF8);
    Log('설정 저장: ' + SettingsPath);
  except on E: Exception do Log('설정 저장 실패: ' + E.Message) end;
  J.Free;
end;

procedure TMainWindow.TestClick(Sender: TObject);
var H, ReplyWindow: HWND; Action, I: Integer;
begin
  if FList.Selected = nil then begin Log('대상을 선택하세요'); Exit end;
  H := HWND(NativeUInt(FList.Selected.Data));
  if not IsWindow(H) then begin Log('창을 다시 검색하세요'); Exit end;
  if IsIconic(H) then ShowWindow(H, SW_RESTORE);
  SetForegroundWindow(H);
  for I := 1 to 10 do
  begin
    if TargetIsForeground(H) then Break;
    Sleep(50);
  end;
  if not TargetIsForeground(H) then begin Log('창 활성화 실패'); Exit end;
  Log('창 활성화 성공: ' + FList.Selected.Caption);
  Action := 0;
  for I := 0 to 2 do
    if SameText(FList.Selected.Caption, Names[I]) then Action := FActions[I];
  if Action = 0 then
  begin
    Log('현재 동작: 창 활성화만 (입력창 포커스를 사용하려면 오른쪽 동작 메뉴에서 선택)');
    Exit;
  end;
  ReplyWindow := Handle;
  TThread.CreateAnonymousThread(
    procedure
    var Success: Boolean; Detail, MicDetail: string; Info: PString;
    begin
      try
        if not TargetIsForeground(H) then
        begin Success := False; Detail := '대상 창이 전경 창에서 벗어남' end
        else Success := FocusEditableControl(H, Detail);
        if Success and (Action = 2) then
        begin
          ActivateMicrophone(H, MicDetail);
          Detail := Detail + ' / 마이크: ' + MicDetail;
        end;
      except on E: Exception do
        begin Success := False; Detail := E.Message end;
      end;
      New(Info);
      Info^ := Detail;
      if not PostMessage(ReplyWindow, WM_APP + 1, Ord(Success), LPARAM(Info)) then
        Dispose(Info);
    end).Start;
end;

procedure TMainWindow.FocusResult(var Msg: TMessage);
var Info: PString;
begin
  Info := PString(Msg.LParam);
  try
    if Msg.WParam = 0 then Log('입력창 포커스 실패: ' + Info^)
    else Log('입력창 포커스 ' + Info^);
  finally Dispose(Info) end;
end;

procedure TMainWindow.HotKey(var Msg: TWMHotKey);
var I, Target: Integer;
begin
  if (Msg.HotKey < 1) or (Msg.HotKey > 3) then Exit;
  Target := Msg.HotKey - 1;
  RefreshProcesses;
  for I := 0 to FList.Items.Count - 1 do
    if SameText(FList.Items[I].Caption, Names[Target]) and
       (DWORD(StrToIntDef(FList.Items[I].SubItems[0], 0)) = FPreferredPID[Target]) then
    begin
      FList.Selected := FList.Items[I];
      TestClick(nil);
      Exit;
    end;
  for I := 0 to FList.Items.Count - 1 do
    if SameText(FList.Items[I].Caption, Names[Target]) then
    begin
      FList.Selected := FList.Items[I];
      Log('선택한 PID를 찾지 못해 다른 인스턴스를 사용: ' + Names[Target]);
      TestClick(nil);
      Exit;
    end;
  Log('실행 중인 대상 없음: ' + Names[Target]);
end;

end.
