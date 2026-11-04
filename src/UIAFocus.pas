unit UIAFocus;

interface

uses Winapi.Windows;

function FocusEditableControl(Window: HWND; out Detail: string): Boolean;
function ActivateMicrophone(Window: HWND; out Detail: string): Boolean;

implementation

uses Winapi.ActiveX, System.SysUtils, System.Variants;

type
  TComMethod = function(Self: Pointer; A: HWND; out B: Pointer): HRESULT; stdcall;
  TCreateCondition = function(Self: Pointer; PropertyId: Integer; Value: OleVariant;
    out Condition: Pointer): HRESULT; stdcall;
  TFindFirst = function(Self: Pointer; Scope: Integer; Condition: Pointer;
    out Element: Pointer): HRESULT; stdcall;
  TSetFocus = function(Self: Pointer): HRESULT; stdcall;
  TGetFocused = function(Self: Pointer; out Element: Pointer): HRESULT; stdcall;
  TCompareElements = function(Self, First, Second: Pointer;
    out Equal: LongBool): HRESULT; stdcall;
  TGetRect = function(Self: Pointer; out Bounds: TRect): HRESULT; stdcall;
  TGetBoolean = function(Self: Pointer; out Value: LongBool): HRESULT; stdcall;
  TGetText = function(Self: Pointer; out Value: WideString): HRESULT; stdcall;
  TFindAll = function(Self: Pointer; Scope: Integer; Condition: Pointer;
    out Elements: Pointer): HRESULT; stdcall;
  TGetLength = function(Self: Pointer; out Count: Integer): HRESULT; stdcall;
  TGetElement = function(Self: Pointer; Index: Integer; out Element: Pointer): HRESULT; stdcall;
  TGetPattern = function(Self: Pointer; PatternId: Integer; out Pattern: Pointer): HRESULT; stdcall;
  TInvoke = function(Self: Pointer): HRESULT; stdcall;

procedure MoveCaretToEnd;
var Inputs: array[0..3] of TInput;
begin
  ZeroMemory(@Inputs, SizeOf(Inputs));
  Inputs[0].Itype := INPUT_KEYBOARD;
  Inputs[0].ki.wVk := VK_CONTROL;
  Inputs[1].Itype := INPUT_KEYBOARD;
  Inputs[1].ki.wVk := VK_END;
  Inputs[2].Itype := INPUT_KEYBOARD;
  Inputs[2].ki.wVk := VK_END;
  Inputs[2].ki.dwFlags := KEYEVENTF_KEYUP;
  Inputs[3].Itype := INPUT_KEYBOARD;
  Inputs[3].ki.wVk := VK_CONTROL;
  Inputs[3].ki.dwFlags := KEYEVENTF_KEYUP;
  SendInput(Length(Inputs), Inputs[0], SizeOf(TInput));
end;

const
  CLSID_CUIAutomation: TGUID = '{FF48DBA4-60EF-4201-AA87-54103EEF594E}';
  IID_IUIAutomation: TGUID = '{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}';
  TreeScope_Descendants = 4;
  UIA_ControlTypePropertyId = 30003;
  UIA_EditControlTypeId = 50004;
  UIA_DocumentControlTypeId = 50030;
  UIA_ButtonControlTypeId = 50000;
  UIA_InvokePatternId = 10000;

function MethodAt(Obj: Pointer; Index: Integer): Pointer; forward;

function MicrophoneName(const S: string): Boolean;
var N: string;
begin
  N := LowerCase(S);
  Result := (Pos('microphone', N) > 0) or (Pos('mic', N) > 0) or
    (Pos('dictat', N) > 0) or (Pos('voice', N) > 0) or
    (Pos('마이크', N) > 0) or (Pos('음성', N) > 0);
  if (Pos('stop', N) > 0) or (Pos('종료', N) > 0) or
     (Pos('중지', N) > 0) then Result := False;
end;

function ActivateMicrophone(Window: HWND; out Detail: string): Boolean;
var
  Automation, Root, Condition, Elements, Element, Pattern: Pointer;
  Value: OleVariant;
  InitResult: HRESULT;
  Count, I: Integer;
  Name: WideString;
  Enabled: LongBool;
  TargetPID, ForegroundPID: DWORD;
begin
  Result := False;
  Detail := '마이크 버튼을 찾지 못함';
  Automation := nil; Root := nil; Condition := nil; Elements := nil;
  Element := nil; Pattern := nil;
  GetWindowThreadProcessId(Window, @TargetPID);
  GetWindowThreadProcessId(GetForegroundWindow, @ForegroundPID);
  if (TargetPID = 0) or (TargetPID <> ForegroundPID) then
  begin Detail := '대상 창이 전경 창이 아님'; Exit end;
  InitResult := CoInitializeEx(nil, COINIT_MULTITHREADED);
  try
    if Failed(CoCreateInstance(CLSID_CUIAutomation, nil, CLSCTX_INPROC_SERVER,
      IID_IUIAutomation, Automation)) then Exit;
    if Failed(TComMethod(MethodAt(Automation, 6))(Automation, Window, Root)) then Exit;
    Value := UIA_ButtonControlTypeId;
    if Failed(TCreateCondition(MethodAt(Automation, 23))(Automation,
      UIA_ControlTypePropertyId, Value, Condition)) then Exit;
    if Failed(TFindAll(MethodAt(Root, 6))(Root, TreeScope_Descendants,
      Condition, Elements)) or (Elements = nil) then Exit;
    Count := 0;
    if Failed(TGetLength(MethodAt(Elements, 3))(Elements, Count)) then Exit;
    for I := 0 to Count - 1 do
    begin
      Element := nil;
      if Failed(TGetElement(MethodAt(Elements, 4))(Elements, I, Element)) or
         (Element = nil) then Continue;
      try
        Name := '';
        if Failed(TGetText(MethodAt(Element, 23))(Element, Name)) or
           not MicrophoneName(string(Name)) then Continue;
        Detail := '버튼 사용 불가: ' + string(Name);
        Enabled := False;
        if Failed(TGetBoolean(MethodAt(Element, 28))(Element, Enabled)) or
           not Enabled then Exit;
        Detail := 'InvokePattern 미지원: ' + string(Name);
        if Failed(TGetPattern(MethodAt(Element, 16))(Element,
          UIA_InvokePatternId, Pattern)) or (Pattern = nil) then Exit;
        GetWindowThreadProcessId(GetForegroundWindow, @ForegroundPID);
        if TargetPID <> ForegroundPID then
        begin Detail := '마이크 실행 전 대상 창이 바뀜'; Exit end;
        Result := Succeeded(TInvoke(MethodAt(Pattern, 3))(Pattern));
        if Result then Detail := '버튼 실행 요청: ' + string(Name)
        else Detail := '버튼 실행 실패: ' + string(Name);
        Exit;
      finally
        if Element <> nil then IUnknown(Element)._Release;
        Element := nil;
      end;
    end;
  finally
    if Pattern <> nil then IUnknown(Pattern)._Release;
    if Elements <> nil then IUnknown(Elements)._Release;
    if Condition <> nil then IUnknown(Condition)._Release;
    if Root <> nil then IUnknown(Root)._Release;
    if Automation <> nil then IUnknown(Automation)._Release;
    if Succeeded(InitResult) then CoUninitialize;
  end;
end;

function MethodAt(Obj: Pointer; Index: Integer): Pointer;
begin
  Result := PPointer(NativeUInt(PPointer(Obj)^) + NativeUInt(Index) * SizeOf(Pointer))^;
end;

function FocusEditableControl(Window: HWND; out Detail: string): Boolean;
var
  Automation, Root, Condition, Element, Focused: Pointer;
  Value: OleVariant;
  InitResult: HRESULT;
  Equal: LongBool;
  HasFocus: LongBool;
  Bounds, WindowBounds: TRect;
  X, Y: Integer;
  TargetPID, ForegroundPID: DWORD;
  Kind: Integer;
  ElementName: WideString;
  Clicked: Boolean;
begin
  Result := False;
  Kind := 0;
  Bounds := TRect.Empty;
  Detail := 'UI Automation 초기화 실패';
  Automation := nil; Root := nil; Condition := nil; Element := nil; Focused := nil;
  InitResult := CoInitializeEx(nil, COINIT_MULTITHREADED);
  try
    if Failed(CoCreateInstance(CLSID_CUIAutomation, nil, CLSCTX_INPROC_SERVER,
      IID_IUIAutomation, Automation)) then Exit;
    Detail := '대상 창 UI Automation 연결 실패';
    if Failed(TComMethod(MethodAt(Automation, 6))(Automation, Window, Root)) then Exit;
    Detail := '편집/문서 컨트롤을 찾지 못함';
    for Kind in [UIA_EditControlTypeId, UIA_DocumentControlTypeId] do
    begin
      Value := Kind;
      if Failed(TCreateCondition(MethodAt(Automation, 23))(Automation,
        UIA_ControlTypePropertyId, Value, Condition)) then Continue;
      TFindFirst(MethodAt(Root, 5))(Root, TreeScope_Descendants, Condition, Element);
      IUnknown(Condition)._Release;
      Condition := nil;
      if Element <> nil then Break;
    end;
    if Element = nil then Exit;
    ElementName := '';
    TGetText(MethodAt(Element, 23))(Element, ElementName);
    Clicked := False;
    Detail := '입력 영역 확인 실패: ' + string(ElementName);
      if Succeeded(TGetRect(MethodAt(Element, 43))(Element, Bounds)) and
         GetWindowRect(Window, WindowBounds) and
         (Bounds.Right > Bounds.Left) and (Bounds.Bottom > Bounds.Top) then
      begin
        X := Bounds.Left + 28;
        Y := Bounds.Top + (Bounds.Bottom - Bounds.Top) div 2;
        GetWindowThreadProcessId(Window, @TargetPID);
        GetWindowThreadProcessId(GetForegroundWindow, @ForegroundPID);
        if (X >= WindowBounds.Left) and (X < WindowBounds.Right) and
           (Y >= WindowBounds.Top) and (Y < WindowBounds.Bottom) and
           (TargetPID <> 0) and (TargetPID = ForegroundPID) then
        begin
          SetCursorPos(X, Y);
          mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
          mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
          Sleep(80);
          Clicked := True;
        end;
      end;
    if not Clicked then Exit;
    Equal := False;
    HasFocus := False;
    if Succeeded(TGetFocused(MethodAt(Automation, 8))(Automation, Focused)) and
       (Focused <> nil) then
      TCompareElements(MethodAt(Automation, 3))(
        Automation, Element, Focused, Equal);
    if Succeeded(TGetBoolean(MethodAt(Element, 26))(Element, HasFocus)) then
      Result := Equal or HasFocus
    else Result := Equal;
    if Result then
    begin
      GetWindowThreadProcessId(GetForegroundWindow, @ForegroundPID);
      if (TargetPID <> 0) and (TargetPID = ForegroundPID) then
        MoveCaretToEnd;
    end;
    if Result then Detail := Format('성공: 종류=%d 이름=%s 영역=%d,%d,%d,%d 클릭=%s',
      [Kind, string(ElementName), Bounds.Left, Bounds.Top, Bounds.Right,
       Bounds.Bottom, BoolToStr(Clicked, True)])
    else Detail := Format('포커스 검증 실패: 종류=%d 이름=%s 영역=%d,%d,%d,%d 클릭=%s',
      [Kind, string(ElementName), Bounds.Left, Bounds.Top, Bounds.Right,
       Bounds.Bottom, BoolToStr(Clicked, True)]);
  finally
    if Focused <> nil then IUnknown(Focused)._Release;
    if Element <> nil then IUnknown(Element)._Release;
    if Condition <> nil then IUnknown(Condition)._Release;
    if Root <> nil then IUnknown(Root)._Release;
    if Automation <> nil then IUnknown(Automation)._Release;
    if Succeeded(InitResult) then CoUninitialize;
  end;
end;

end.
