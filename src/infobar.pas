{ TInfoBar

  MessageDlg without the dialog: a strip with the message, the dialog's icon
  and buttons, over the top or bottom edge of a control - the form when
  Control is empty.  Nothing waits for it; the answer comes to OnAnswer.

  Several messages stack, errors first; past MaxVisible they wait.  A
  message shown again under the same key replaces itself.

    InfoBar1.Show('notes.md changed on disk. Load it?', mtConfirmation, [mbYes, mbNo], 'changed');
    InfoBar1.ShowQuestion('notes.md changed on disk.', mtWarning, [mrYes, '&Reload', mrNo, '&Keep mine'], 'changed');

  Copyright (c) 2026 Tony Stone. 0BSD; see LICENSE.
}
unit InfoBar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  // LCL
  LCLType, LCLIntf, Controls, Forms, Graphics, StdCtrls, Buttons, Dialogs, DialogRes, Menus;

type
  TInfoBarEdge = (ieTop, ieBottom);

  TInfoBarAnswerEvent = procedure(Sender: TObject; const Key: string; Answer: TModalResult) of object;

  { TInfoBar }

  TInfoBar = class(TComponent)
  private
    FButtons: TMsgDlgButtons;
    FControl: TControl;
    FEdge: TInfoBarEdge;
    FFocus: TWinControl; // had the focus when the first strip came up
    FKind: TMsgDlgType;
    FMaxVisible: integer;
    FMessages: TFPList;  // TInfoBarMessage, in the order shown
    FNextSeq: integer;
    FShowCloseButton: boolean;
    FText: string;
    FOnAnswer: TInfoBarAnswerEvent;
    function GetCount: integer;
    function GetShowing: boolean;
    function IndexOfKey(const AKey: string): integer;
    procedure SetControl(AValue: TControl);
    procedure SetEdge(AValue: TInfoBarEdge);
    procedure SetMaxVisible(AValue: integer);
    procedure Add(const AMsg: string; AKind: TMsgDlgType; const Answers: array of TModalResult; const Captions: array of string; const AKey: string);
    procedure Remove(Index: integer);
    procedure Relayout;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function AccentColor(AKind: TMsgDlgType): TColor; virtual;
    procedure DoAnswer(const AKey: string; Answer: TModalResult); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Shows Text with Kind and Buttons.
    procedure Show; overload;
    procedure Show(const AMsg: string; AKind: TMsgDlgType; AButtons: TMsgDlgButtons; const AKey: string = ''); overload;
    // QuestionDlg's buttons: ModalResults, each with an optional caption.
    procedure ShowQuestion(const AMsg: string; AKind: TMsgDlgType; const AButtons: array of const; const AKey: string = '');
    // Takes messages away without an answer: all of them, or the one with
    // this key.
    procedure Hide; overload;
    procedure Hide(const AKey: string); overload;
    // A message with this key is up or waiting.
    function Has(const AKey: string): boolean;
    // Messages up and waiting.
    property Count: integer read GetCount;
    property Showing: boolean read GetShowing;
    // Used by the strips.
    procedure Answered(Msg: TObject; Answer: TModalResult);
  published
    property Buttons: TMsgDlgButtons read FButtons write FButtons default [];
    // What the bar lies on.  Empty: the form.  Changing it, or Edge, while
    // messages are up moves them.
    property Control: TControl read FControl write SetControl;
    property Edge: TInfoBarEdge read FEdge write SetEdge default ieTop;
    // The dialog type: its icon, color and place in the stack.  mtCustom has
    // no icon.
    property Kind: TMsgDlgType read FKind write FKind default mtInformation;
    // Strips shown at once; the rest wait, counted on the last.  1 shows
    // one message at a time.
    property MaxVisible: integer read FMaxVisible write SetMaxVisible default 3;
    property ShowCloseButton: boolean read FShowCloseButton write FShowCloseButton default True;
    property Text: string read FText write FText;
    // A button's ModalResult, or mrClose for the close button, with the
    // message's key.  The message is gone already, except for Help
    // (mrNone), which leaves it up as a dialog would.
    property OnAnswer: TInfoBarAnswerEvent read FOnAnswer write FOnAnswer;
  end;

implementation

const
  IconSize = 16; // at 96 PPI
  Gap = 8;       // at 96 PPI, between everything
  MinText = 160; // at 96 PPI, the narrowest the message gets beside the buttons

  // place in the stack: errors first
  Rank: array[TMsgDlgType] of integer = (3, 4, 1, 2, 0);

type

  { TInfoBarStrip - what one message looks like }

  TInfoBarStrip = class(TCustomControl)
  private
    FBar: TInfoBar;
    FMsg: TObject;
    FButtonControls: array of TButton;
    FCloseButton: TSpeedButton;
    FMore: integer; // messages waiting behind this one
    FOwnsMsg: boolean; // taken off: the message goes with the strip
    procedure ButtonClick(Sender: TObject);
    procedure ButtonRow(out RowWidth, RowHeight: integer);
    function CloseSpace: integer;
    function IconSpace: integer;
    function Shown: string;
    function ButtonsBelow: boolean;
    function TextRect: TRect;
    function TextHeight(AWidth: integer): integer;
    function TopRowHeight: integer;
    function NeededHeight: integer;
  protected
    procedure AlignControls(AControl: TControl; var RemainingClientRect: TRect); override;
    procedure DoSetBounds(ALeft, ATop, AWidth, AHeight: integer); override;
    procedure Paint; override;
  public
    constructor Create(ABar: TInfoBar; AMsg: TObject); reintroduce;
    destructor Destroy; override;
    procedure Rebuild;
    procedure UpdateHeight;
  end;

  { TInfoBarMessage - one message, up or waiting }

  TInfoBarMessage = class
    Key, Text: string;
    Kind: TMsgDlgType;
    Answers: array of TModalResult;
    Captions: array of string;
    Seq: integer;
    Strip: TInfoBarStrip;
  end;

// Percent of the way from B to A.
function MixColors(A, B: TColor; Percent: integer): TColor;
var
  CA, CB: TColorRef;

  function Mix(X, Y: byte): byte;
  begin
    Result := (X * Percent + Y * (100 - Percent)) div 100;
  end;

begin
  CA := ColorToRGB(A);
  CB := ColorToRGB(B);
  Result := RGBToColor(Mix(Red(CA), Red(CB)), Mix(Green(CA), Green(CB)), Mix(Blue(CA), Blue(CB)));
end;

// The LCL's own caption for a dialog button, translated like MessageDlg's.
function ResultCaption(Answer: TModalResult): string;
var
  Btn: TMsgDlgBtn;
begin
  for Btn in TMsgDlgBtn do
    if BitBtnModalResults[MsgDlgBtnToBitBtnKind[Btn]] = Answer then
      Exit(GetButtonCaption(BitBtnImages[MsgDlgBtnToBitBtnKind[Btn]]));
  Result := IntToStr(Answer);
end;

// Errors before warnings before the rest; oldest first within a kind.
function CompareMessages(A, B: Pointer): integer;
begin
  Result := Rank[TInfoBarMessage(B).Kind] - Rank[TInfoBarMessage(A).Kind];
  if Result = 0 then Result := TInfoBarMessage(A).Seq - TInfoBarMessage(B).Seq;
end;

{ TInfoBarStrip }

constructor TInfoBarStrip.Create(ABar: TInfoBar; AMsg: TObject);
begin
  inherited Create(ABar);
  FBar := ABar;
  FMsg := AMsg;
  ControlStyle := ControlStyle - [csAcceptsControls, csSetCaption] + [csOpaque];
  Visible := False;
  FCloseButton := TSpeedButton.Create(Self);
  FCloseButton.Flat := True;
  FCloseButton.Caption := '×';
  FCloseButton.Tag := mrClose;
  FCloseButton.OnClick := @ButtonClick;
  FCloseButton.Parent := Self;
end;

destructor TInfoBarStrip.Destroy;
begin
  if FOwnsMsg then FMsg.Free;
  inherited Destroy;
end;

// One button per answer, in order, left of the close button.
procedure TInfoBarStrip.Rebuild;
var
  I: integer;
  Msg: TInfoBarMessage;
begin
  Msg := TInfoBarMessage(FMsg);
  for I := 0 to High(FButtonControls) do
    FButtonControls[I].Free;
  SetLength(FButtonControls, Length(Msg.Answers));
  FCloseButton.Visible := FBar.ShowCloseButton;
  FCloseButton.Width := Canvas.TextHeight('Xg') + Scale96ToFont(Gap);
  FCloseButton.Height := FCloseButton.Width;
  for I := 0 to High(Msg.Answers) do
  begin
    FButtonControls[I] := TButton.Create(Self);
    // No accelerators: a strip that stays up must not take Alt+letter from
    // the window.  LibreOffice's info bars have none either.
    FButtonControls[I].Caption := StringReplace(StripHotkey(Msg.Captions[I]), '&', '&&', [rfReplaceAll]);
    // the answer goes in Tag: a ModalResult would close a modal form
    FButtonControls[I].Tag := Msg.Answers[I];
    FButtonControls[I].OnClick := @ButtonClick;
    FButtonControls[I].Parent := Self;
  end;
  UpdateHeight;
  ReAlign;
  Invalidate;
end;

procedure TInfoBarStrip.ButtonClick(Sender: TObject);
begin
  FBar.Answered(FMsg, TControl(Sender).Tag);
end;

procedure TInfoBarStrip.ButtonRow(out RowWidth, RowHeight: integer);
var
  I, W, H: integer;
begin
  RowWidth := 0;
  RowHeight := 0;
  for I := 0 to High(FButtonControls) do
  begin
    W := 0;
    H := 0;
    FButtonControls[I].GetPreferredSize(W, H);
    if I > 0 then Inc(RowWidth, Scale96ToFont(Gap));
    Inc(RowWidth, W);
    RowHeight := Max(RowHeight, H);
  end;
end;

function TInfoBarStrip.CloseSpace: integer;
begin
  if FCloseButton.Visible then Result := FCloseButton.Width + Scale96ToFont(Gap)
  else
    Result := 0;
end;

function TInfoBarStrip.IconSpace: integer;
begin
  if TInfoBarMessage(FMsg).Kind = mtCustom then Result := 0
  else
    Result := Scale96ToFont(IconSize + Gap);
end;

// The message, and how many wait behind it.
function TInfoBarStrip.Shown: string;
begin
  Result := TInfoBarMessage(FMsg).Text;
  if FMore > 0 then Result := Result + Format('   (+%d more)', [FMore]);
end;

// Too narrow for the text beside the buttons: the buttons go below it.
function TInfoBarStrip.ButtonsBelow: boolean;
var
  RowW, RowH: integer;
begin
  if Length(FButtonControls) = 0 then Exit(False);
  ButtonRow(RowW, RowH);
  Result := Width - IconSpace - CloseSpace - RowW - Scale96ToFont(Gap) * 3 < Scale96ToFont(MinText);
end;

// Left and right of the message; the height is worked out where it is used.
function TInfoBarStrip.TextRect: TRect;
var
  RowW, RowH: integer;
begin
  Result := Rect(Scale96ToFont(Gap) + IconSpace, 0, Width - Scale96ToFont(Gap) - CloseSpace, Height);
  if not ButtonsBelow and (Length(FButtonControls) > 0) then
  begin
    ButtonRow(RowW, RowH);
    Dec(Result.Right, RowW + Scale96ToFont(Gap));
  end;
  Result.Right := Max(Result.Left + 1, Result.Right);
end;

// Measured on the screen, as TCustomLabel does, so no handle is needed.
function TInfoBarStrip.TextHeight(AWidth: integer): integer;
var
  DC: HDC;
  OldFont: HGDIOBJ;
  R: TRect;
  S: string;
begin
  S := Shown;
  if S = '' then Exit(0);
  DC := GetDC(0);
  try
    OldFont := SelectObject(DC, HGDIOBJ(Font.Reference.Handle));
    R := Rect(0, 0, Max(AWidth, 1), 0);
    DrawText(DC, PChar(S), Length(S), R, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    SelectObject(DC, OldFont);
  finally
    ReleaseDC(0, DC);
  end;
  Result := R.Bottom - R.Top;
end;

// The message, the icon and the close button; the buttons too unless they are below.
function TInfoBarStrip.TopRowHeight: integer;
var
  RowW, RowH: integer;
begin
  Result := TextHeight(TextRect.Width);
  if IconSpace > 0 then Result := Max(Result, Scale96ToFont(IconSize));
  if FCloseButton.Visible then Result := Max(Result, FCloseButton.Height);
  if not ButtonsBelow then
  begin
    ButtonRow(RowW, RowH);
    Result := Max(Result, RowH);
  end;
end;

// Not AutoSize: that moves children of its own accord.  The height follows
// the width instead, as a word-wrapped TCustomLabel's does.
function TInfoBarStrip.NeededHeight: integer;
var
  RowW, RowH: integer;
begin
  Result := TopRowHeight + Scale96ToFont(Gap);
  if ButtonsBelow then
  begin
    ButtonRow(RowW, RowH);
    Inc(Result, RowH + Scale96ToFont(Gap) div 2);
  end;
end;

procedure TInfoBarStrip.UpdateHeight;
begin
  if Height <> NeededHeight then Height := NeededHeight;
end;

// The children placed by hand, as TCustomFlowPanel does: the close button
// at the right, the buttons left of it, or under the message when narrow.
procedure TInfoBarStrip.AlignControls(AControl: TControl; var RemainingClientRect: TRect);
var
  I, X, Y, W, H, RowTop, RowW, RowH: integer;
  IsBelow: boolean;
begin
  DisableAlign;
  try
    IsBelow := ButtonsBelow;
    RowTop := TopRowHeight;
    ButtonRow(RowW, RowH);
    W := FCloseButton.Width;
    if IsBelow then Y := Scale96ToFont(Gap) div 2 + (RowTop - W) div 2
    else
      Y := (RemainingClientRect.Height - W) div 2;
    FCloseButton.SetBounds(RemainingClientRect.Right - Scale96ToFont(Gap) - W, Y, W, W);

    X := RemainingClientRect.Right - Scale96ToFont(Gap);
    if not IsBelow then Dec(X, CloseSpace);
    for I := High(FButtonControls) downto 0 do
    begin
      W := 0;
      H := 0;
      FButtonControls[I].GetPreferredSize(W, H);
      Dec(X, W);
      if IsBelow then Y := RemainingClientRect.Bottom - Scale96ToFont(Gap) div 2 - RowH + (RowH - H) div 2
      else
        Y := (RemainingClientRect.Height - H) div 2;
      FButtonControls[I].SetBounds(X, Y, W, H);
      Dec(X, Scale96ToFont(Gap));
    end;
  finally
    EnableAlign;
  end;
end;

procedure TInfoBarStrip.DoSetBounds(ALeft, ATop, AWidth, AHeight: integer);
var
  WidthChanged: boolean;
begin
  WidthChanged := AWidth <> Width;
  inherited DoSetBounds(ALeft, ATop, AWidth, AHeight);
  // the text wraps to the width, so a new width can need a new height
  if WidthChanged and HandleAllocated then UpdateHeight;
end;

procedure TInfoBarStrip.Paint;
const
  Icons: array[TMsgDlgType] of integer = (idDialogWarning, idDialogError, idDialogInfo,
    idDialogConfirm, 0);
var
  R: TRect;
  Middle, Y: integer;
  Kind: TMsgDlgType;
  S: string;
begin
  Kind := TInfoBarMessage(FMsg).Kind;
  Canvas.Brush.Color := MixColors(FBar.AccentColor(Kind), clWindow, 15);
  Canvas.Pen.Color := MixColors(FBar.AccentColor(Kind), clWindow, 50);
  Canvas.Rectangle(ClientRect);

  // the top row's middle, which is the bar's middle unless below
  if ButtonsBelow then Middle := Scale96ToFont(Gap) div 2 + TopRowHeight div 2
  else
    Middle := Height div 2;

  if IconSpace > 0 then
    DialogGlyphs.ResolutionForControl[IconSize, Self].Draw(Canvas, Scale96ToFont(Gap),
      Middle - Scale96ToFont(IconSize) div 2, DialogGlyphs.DialogIcon[Icons[Kind]]);

  S := Shown;
  R := TextRect;
  Y := TextHeight(R.Width);
  R.Top := Middle - Y div 2;
  R.Bottom := R.Top + Y;
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  if Canvas.Font.Color = clDefault then Canvas.Font.Color := clWindowText;
  DrawText(Canvas.Handle, PChar(S), Length(S), R, DT_WORDBREAK or DT_NOPREFIX);
end;

{ TInfoBar }

constructor TInfoBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := mtInformation;
  FMaxVisible := 3;
  FMessages := TFPList.Create;
  FShowCloseButton := True;
end;

destructor TInfoBar.Destroy;
var
  I: integer;
begin
  // the strips are owned components and go with the bar
  for I := 0 to FMessages.Count - 1 do
    TInfoBarMessage(FMessages[I]).Free;
  FreeAndNil(FMessages);
  inherited Destroy;
end;

procedure TInfoBar.Notification(AComponent: TComponent; Operation: TOperation);
var
  I: integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then Exit;
  if AComponent = FControl then
  begin
    FControl := nil;
    Hide;
  end
  else if AComponent = FFocus then
    FFocus := nil
  else if (FMessages <> nil) and (AComponent is TInfoBarStrip) then
    for I := 0 to FMessages.Count - 1 do
      if TInfoBarMessage(FMessages[I]).Strip = AComponent then TInfoBarMessage(FMessages[I]).Strip := nil;
end;

function TInfoBar.AccentColor(AKind: TMsgDlgType): TColor;
begin
  case AKind of
    mtWarning: Result := RGBToColor(219, 154, 4);
    mtError: Result := RGBToColor(207, 34, 46);
    mtCustom: Result := clBtnShadow;
    else
      Result := clHighlight;
  end;
end;

function TInfoBar.GetCount: integer;
begin
  Result := FMessages.Count;
end;

function TInfoBar.GetShowing: boolean;
begin
  Result := (FMessages.Count > 0) and (TInfoBarMessage(FMessages[0]).Strip <> nil) and TInfoBarMessage(FMessages[0]).Strip.Visible;
end;

function TInfoBar.IndexOfKey(const AKey: string): integer;
begin
  if AKey <> '' then
    for Result := 0 to FMessages.Count - 1 do
      if TInfoBarMessage(FMessages[Result]).Key = AKey then Exit;
  Result := -1;
end;

function TInfoBar.Has(const AKey: string): boolean;
begin
  Result := IndexOfKey(AKey) >= 0;
end;

procedure TInfoBar.SetControl(AValue: TControl);
begin
  if FControl = AValue then Exit;
  if FControl <> nil then FControl.RemoveFreeNotification(Self);
  FControl := AValue;
  if FControl <> nil then FControl.FreeNotification(Self);
  Relayout;
end;

procedure TInfoBar.SetEdge(AValue: TInfoBarEdge);
begin
  if FEdge = AValue then Exit;
  FEdge := AValue;
  Relayout;
end;

procedure TInfoBar.SetMaxVisible(AValue: integer);
begin
  FMaxVisible := Max(AValue, 1);
  Relayout;
end;

procedure TInfoBar.Show;
var
  Btn: TMsgDlgBtn;
  Answers: array of TModalResult;
  Captions: array of string;
begin
  Answers := [];
  Captions := [];
  for Btn in FButtons do
  begin
    Answers := Concat(Answers, [BitBtnModalResults[MsgDlgBtnToBitBtnKind[Btn]]]);
    Captions := Concat(Captions, [GetButtonCaption(BitBtnImages[MsgDlgBtnToBitBtnKind[Btn]])]);
  end;
  Add(FText, FKind, Answers, Captions, '');
end;

procedure TInfoBar.Show(const AMsg: string; AKind: TMsgDlgType; AButtons: TMsgDlgButtons; const AKey: string);
var
  Btn: TMsgDlgBtn;
  Answers: array of TModalResult;
  Captions: array of string;
begin
  Answers := [];
  Captions := [];
  for Btn in AButtons do
  begin
    Answers := Concat(Answers, [BitBtnModalResults[MsgDlgBtnToBitBtnKind[Btn]]]);
    Captions := Concat(Captions, [GetButtonCaption(BitBtnImages[MsgDlgBtnToBitBtnKind[Btn]])]);
  end;
  Add(AMsg, AKind, Answers, Captions, AKey);
end;

procedure TInfoBar.ShowQuestion(const AMsg: string; AKind: TMsgDlgType; const AButtons: array of const; const AKey: string);
var
  I: integer;
  Answers: array of TModalResult;
  Captions: array of string;
begin
  Answers := [];
  Captions := [];
  for I := 0 to High(AButtons) do
    case AButtons[I].VType of
      vtInteger:
      begin
        Answers := Concat(Answers, [TModalResult(AButtons[I].VInteger)]);
        Captions := Concat(Captions, [ResultCaption(AButtons[I].VInteger)]);
      end;
      vtAnsiString:
        if Length(Captions) > 0 then Captions[High(Captions)] := ansistring(AButtons[I].VAnsiString);
      vtUnicodeString:
        if Length(Captions) > 0 then Captions[High(Captions)] := UTF8Encode(unicodestring(AButtons[I].VUnicodeString));
      else
        raise EInvalidArgument.CreateFmt('TInfoBar.ShowQuestion: a ModalResult or a caption expected at %d', [I]);
    end;
  Add(AMsg, AKind, Answers, Captions, AKey);
end;

// A new message, or the one with this key changed.
procedure TInfoBar.Add(const AMsg: string; AKind: TMsgDlgType; const Answers: array of TModalResult; const Captions: array of string; const AKey: string);
var
  I: integer;
  Msg: TInfoBarMessage;
begin
  if csDesigning in ComponentState then Exit;
  I := IndexOfKey(AKey);
  if I >= 0 then Msg := TInfoBarMessage(FMessages[I])
  else
  begin
    Msg := TInfoBarMessage.Create;
    Msg.Key := AKey;
    Msg.Seq := FNextSeq;
    Inc(FNextSeq);
    if FMessages.Count = 0 then
    begin
      if FFocus <> nil then FFocus.RemoveFreeNotification(Self);
      FFocus := Screen.ActiveControl;
      if FFocus <> nil then FFocus.FreeNotification(Self);
    end;
    FMessages.Add(Msg);
  end;
  Msg.Text := AMsg;
  Msg.Kind := AKind;
  SetLength(Msg.Answers, Length(Answers));
  SetLength(Msg.Captions, Length(Answers));
  for I := 0 to High(Answers) do
  begin
    Msg.Answers[I] := Answers[I];
    Msg.Captions[I] := Captions[I];
  end;
  if Msg.Strip <> nil then Msg.Strip.Rebuild;
  Relayout;
end;

procedure TInfoBar.Remove(Index: integer);
var
  Msg: TInfoBarMessage;
begin
  Msg := TInfoBarMessage(FMessages[Index]);
  FMessages.Delete(Index);
  if Msg.Strip = nil then
  begin
    Msg.Free;
    Exit;
  end;
  // freed after the click that took it off has returned, with its message
  Msg.Strip.FOwnsMsg := True;
  Msg.Strip.Hide;
  Application.ReleaseComponent(Msg.Strip);
end;

// The first MaxVisible messages get a strip each: the first on the edge,
// each next one against the one before.
procedure TInfoBar.Relayout;
var
  Target, Prev: TControl;
  Host: TWinControl;
  I, Visible: integer;
  Msg: TInfoBarMessage;
  S: TInfoBarStrip;
begin
  if (FMessages = nil) or (csDesigning in ComponentState) then Exit;
  FMessages.Sort(@CompareMessages);
  Target := FControl;
  if Target = nil then
    if Owner is TControl then Target := GetParentForm(TControl(Owner))
    else
      Target := Application.MainForm;
  Host := nil;
  if Target <> nil then
    // a form holds the strips itself; any other control, its parent does
    if (Target is TWinControl) and (Target.Parent = nil) then Host := TWinControl(Target)
    else
      Host := Target.Parent;
  Visible := Min(FMaxVisible, FMessages.Count);
  if Host = nil then Visible := 0;
  Prev := nil;
  for I := 0 to FMessages.Count - 1 do
  begin
    Msg := TInfoBarMessage(FMessages[I]);
    if I >= Visible then
    begin
      // waiting
      if Msg.Strip <> nil then
      begin
        Msg.Strip.Hide;
        Application.ReleaseComponent(Msg.Strip);
        Msg.Strip := nil;
      end;
      Continue;
    end;
    if Msg.Strip = nil then
    begin
      Msg.Strip := TInfoBarStrip.Create(Self, Msg);
      Msg.Strip.FreeNotification(Self);
    end;
    S := Msg.Strip;
    S.Parent := Host;
    S.Anchors := [];
    S.AnchorSide[akTop].Control := nil;
    S.AnchorSide[akBottom].Control := nil;
    S.AnchorParallel(akLeft, 0, Target);
    S.AnchorParallel(akRight, 0, Target);
    if Prev = nil then
      if FEdge = ieTop then S.AnchorParallel(akTop, 0, Target)
      else
        S.AnchorParallel(akBottom, 0, Target)
    else if FEdge = ieTop then S.AnchorToNeighbour(akTop, 0, Prev)
    else
      S.AnchorToNeighbour(akBottom, 0, Prev);
    if I = Visible - 1 then S.FMore := FMessages.Count - Visible
    else
      S.FMore := 0;
    S.HandleNeeded;
    if Length(S.FButtonControls) <> Length(Msg.Answers) then S.Rebuild
    else
    begin
      S.UpdateHeight;
      S.Invalidate;
    end;
    S.Show;
    S.BringToFront;
    Prev := Msg.Strip;
  end;
end;

procedure TInfoBar.Hide;
begin
  while FMessages.Count > 0 do
    Remove(FMessages.Count - 1);
end;

procedure TInfoBar.Hide(const AKey: string);
var
  I: integer;
begin
  I := IndexOfKey(AKey);
  if I < 0 then Exit;
  Remove(I);
  Relayout;
end;

// A strip's button.  Help (mrNone) leaves the message up; anything else
// takes it away, brings up the next, and gives the focus back to where it
// was if the clicked button had it.
procedure TInfoBar.Answered(Msg: TObject; Answer: TModalResult);
var
  I: integer;
  Key: string;
  HadFocus: boolean;
begin
  I := FMessages.IndexOf(Msg);
  if I < 0 then Exit;
  Key := TInfoBarMessage(Msg).Key;
  if Answer <> mrNone then
  begin
    HadFocus := (Screen.ActiveControl <> nil) and (Screen.ActiveControl.Parent = TInfoBarMessage(Msg).Strip);
    Remove(I);
    Relayout;
    if HadFocus then
      if (FFocus <> nil) and FFocus.CanFocus then FFocus.SetFocus
      else if (FControl is TWinControl) and TWinControl(FControl).CanFocus then TWinControl(FControl).SetFocus;
  end;
  DoAnswer(Key, Answer);
end;

procedure TInfoBar.DoAnswer(const AKey: string; Answer: TModalResult);
begin
  if Assigned(FOnAnswer) then FOnAnswer(Self, AKey, Answer);
end;

end.
