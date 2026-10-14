{ TInfoBar

  MessageDlg without the dialog: a strip with a message, the dialog's icon
  for its type and the dialog's buttons, lying over the top or bottom edge
  of a control - the form when Control is empty - at that control's width.
  Nothing waits for it.  The answer comes to OnAnswer as the ModalResult
  MessageDlg would have returned, and answering hides the bar.

    InfoBar1.Show('notes.md changed on disk. Load it?', mtConfirmation, [mbYes, mbNo]);
    InfoBar1.ShowQuestion('notes.md changed on disk.', mtWarning, [mrYes, '&Reload', mrNo, '&Keep mine']);

  Copyright (c) 2026 Tony Stone. 0BSD; see LICENSE.
}
unit InfoBar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  // LCL
  LCLType, LCLIntf, Controls, Forms, Graphics, StdCtrls, Buttons, Dialogs, DialogRes;

type
  TInfoBarEdge = (ieTop, ieBottom);

  TInfoBarAnswerEvent = procedure(Sender: TObject; Answer: TModalResult) of object;

  { TInfoBar }

  TInfoBar = class(TComponent)
  private
    FButtons: TMsgDlgButtons;
    FControl: TControl;
    FEdge: TInfoBarEdge;
    FKind: TMsgDlgType;
    FShowCloseButton: boolean;
    FStrip: TCustomControl;
    FFocus: TWinControl; // had the focus when the bar came up
    FText: string;
    FOnAnswer: TInfoBarAnswerEvent;
    function GetShowing: boolean;
    procedure SetControl(AValue: TControl);
    procedure SetEdge(AValue: TInfoBarEdge);
    function Pin: boolean;
    procedure ShowStrip(const Answers: array of TModalResult; const Captions: array of string);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function AccentColor: TColor; virtual;
    procedure DoAnswer(Answer: TModalResult); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Shows Text with Kind and Buttons; showing again replaces what is up.
    procedure Show; overload;
    procedure Show(const AMsg: string; AKind: TMsgDlgType; AButtons: TMsgDlgButtons); overload;
    // QuestionDlg's buttons: ModalResults, each with an optional caption.
    procedure ShowQuestion(const AMsg: string; AKind: TMsgDlgType; const AButtons: array of const);
    procedure Hide;
    property Showing: boolean read GetShowing;
  published
    property Buttons: TMsgDlgButtons read FButtons write FButtons default [];
    // What the bar lies on.  Empty: the form.  Changing it, or Edge, while
    // the bar is up moves it.
    property Control: TControl read FControl write SetControl;
    property Edge: TInfoBarEdge read FEdge write SetEdge default ieTop;
    // The dialog type: its icon and color.  mtCustom has no icon.
    property Kind: TMsgDlgType read FKind write FKind default mtInformation;
    property ShowCloseButton: boolean read FShowCloseButton write FShowCloseButton default True;
    property Text: string read FText write FText;
    // A button's ModalResult, or mrClose for the close button.  The bar is
    // already hidden, except for Help (mrNone); Show it again to keep it.
    property OnAnswer: TInfoBarAnswerEvent read FOnAnswer write FOnAnswer;
  end;

implementation

const
  IconSize = 16; // at 96 PPI
  Gap = 8;       // at 96 PPI, between everything
  MinText = 160; // at 96 PPI, the narrowest the message gets beside the buttons

type

  { TInfoBarStrip - what is seen; made by the first Show }

  TInfoBarStrip = class(TCustomControl)
  private
    FBar: TInfoBar;
    FButtonControls: array of TButton;
    FCloseButton: TSpeedButton;
    procedure ButtonClick(Sender: TObject);
    procedure ButtonRow(out RowWidth, RowHeight: integer);
    function CloseSpace: integer;
    function IconSpace: integer;
    function Stacked: boolean;
    function TextRect: TRect;
    function TextHeight(AWidth: integer): integer;
    function TopRowHeight: integer;
    function NeededHeight: integer;
  protected
    procedure AlignControls(AControl: TControl; var RemainingClientRect: TRect); override;
    procedure DoSetBounds(ALeft, ATop, AWidth, AHeight: integer); override;
    procedure Paint; override;
  public
    constructor Create(ABar: TInfoBar); reintroduce;
    procedure Rebuild(const Answers: array of TModalResult; const Captions: array of string);
    procedure UpdateHeight;
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

{ TInfoBarStrip }

constructor TInfoBarStrip.Create(ABar: TInfoBar);
begin
  inherited Create(ABar);
  FBar := ABar;
  ControlStyle := ControlStyle - [csAcceptsControls, csSetCaption] + [csOpaque];
  Visible := False;
  FCloseButton := TSpeedButton.Create(Self);
  FCloseButton.Flat := True;
  FCloseButton.Caption := '×';
  FCloseButton.Tag := mrClose;
  FCloseButton.OnClick := @ButtonClick;
  FCloseButton.Parent := Self;
end;

// One button per answer, in order, left of the close button.
procedure TInfoBarStrip.Rebuild(const Answers: array of TModalResult; const Captions: array of string);
var
  I: integer;
begin
  for I := 0 to High(FButtonControls) do
    FButtonControls[I].Free;
  SetLength(FButtonControls, Length(Answers));
  FCloseButton.Visible := FBar.ShowCloseButton;
  FCloseButton.Width := Canvas.TextHeight('Xg') + Scale96ToFont(Gap);
  FCloseButton.Height := FCloseButton.Width;
  for I := 0 to High(Answers) do
  begin
    FButtonControls[I] := TButton.Create(Self);
    FButtonControls[I].Caption := Captions[I];
    // the answer goes in Tag: a ModalResult would close a modal form
    FButtonControls[I].Tag := Answers[I];
    FButtonControls[I].OnClick := @ButtonClick;
    FButtonControls[I].Parent := Self;
  end;
  UpdateHeight;
  ReAlign;
  Invalidate;
end;

// Help answers mrNone and, as in a dialog, leaves the bar up.
procedure TInfoBarStrip.ButtonClick(Sender: TObject);
begin
  if TControl(Sender).Tag <> mrNone then FBar.Hide;
  FBar.DoAnswer(TControl(Sender).Tag);
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
  if FBar.Kind = mtCustom then Result := 0
  else
    Result := Scale96ToFont(IconSize + Gap);
end;

// Too narrow for the text beside the buttons: the buttons go below it.
function TInfoBarStrip.Stacked: boolean;
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
  if not Stacked and (Length(FButtonControls) > 0) then
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
begin
  if FBar.Text = '' then Exit(0);
  DC := GetDC(0);
  try
    OldFont := SelectObject(DC, HGDIOBJ(Font.Reference.Handle));
    R := Rect(0, 0, Max(AWidth, 1), 0);
    DrawText(DC, PChar(FBar.Text), Length(FBar.Text), R, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    SelectObject(DC, OldFont);
  finally
    ReleaseDC(0, DC);
  end;
  Result := R.Bottom - R.Top;
end;

// The message, the icon and the close button; the buttons too unless stacked.
function TInfoBarStrip.TopRowHeight: integer;
var
  RowW, RowH: integer;
begin
  Result := TextHeight(TextRect.Width);
  if IconSpace > 0 then Result := Max(Result, Scale96ToFont(IconSize));
  if FCloseButton.Visible then Result := Max(Result, FCloseButton.Height);
  if not Stacked then
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
  if Stacked then
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
// at the right, the buttons left of it or, stacked, under the message.
procedure TInfoBarStrip.AlignControls(AControl: TControl; var RemainingClientRect: TRect);
var
  I, X, Y, W, H, RowTop, RowW, RowH: integer;
  IsStacked: boolean;
begin
  DisableAlign;
  try
    IsStacked := Stacked;
    RowTop := TopRowHeight;
    ButtonRow(RowW, RowH);
    W := FCloseButton.Width;
    if IsStacked then Y := Scale96ToFont(Gap) div 2 + (RowTop - W) div 2
    else
      Y := (RemainingClientRect.Height - W) div 2;
    FCloseButton.SetBounds(RemainingClientRect.Right - Scale96ToFont(Gap) - W, Y, W, W);

    X := RemainingClientRect.Right - Scale96ToFont(Gap);
    if not IsStacked then Dec(X, CloseSpace);
    for I := High(FButtonControls) downto 0 do
    begin
      W := 0;
      H := 0;
      FButtonControls[I].GetPreferredSize(W, H);
      Dec(X, W);
      if IsStacked then Y := RemainingClientRect.Bottom - Scale96ToFont(Gap) div 2 - RowH + (RowH - H) div 2
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
begin
  Canvas.Brush.Color := MixColors(FBar.AccentColor, clWindow, 15);
  Canvas.Pen.Color := MixColors(FBar.AccentColor, clWindow, 50);
  Canvas.Rectangle(ClientRect);

  // the top row's middle, which is the bar's middle unless stacked
  if Stacked then Middle := Scale96ToFont(Gap) div 2 + TopRowHeight div 2
  else
    Middle := Height div 2;

  if IconSpace > 0 then
    DialogGlyphs.ResolutionForControl[IconSize, Self].Draw(Canvas, Scale96ToFont(Gap),
      Middle - Scale96ToFont(IconSize) div 2, DialogGlyphs.DialogIcon[Icons[FBar.Kind]]);

  R := TextRect;
  Y := TextHeight(R.Width);
  R.Top := Middle - Y div 2;
  R.Bottom := R.Top + Y;
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  if Canvas.Font.Color = clDefault then Canvas.Font.Color := clWindowText;
  DrawText(Canvas.Handle, PChar(FBar.Text), Length(FBar.Text), R, DT_WORDBREAK or DT_NOPREFIX);
end;

{ TInfoBar }

constructor TInfoBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := mtInformation;
  FShowCloseButton := True;
end;

destructor TInfoBar.Destroy;
begin
  FreeAndNil(FStrip);
  inherited Destroy;
end;

procedure TInfoBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then Exit;
  if AComponent = FControl then
  begin
    FControl := nil;
    Hide;
  end
  else if AComponent = FStrip then
    FStrip := nil
  else if AComponent = FFocus then
    FFocus := nil;
end;

function TInfoBar.AccentColor: TColor;
begin
  case FKind of
    mtWarning: Result := RGBToColor(219, 154, 4);
    mtError: Result := RGBToColor(207, 34, 46);
    mtCustom: Result := clBtnShadow;
    else
      Result := clHighlight;
  end;
end;

function TInfoBar.GetShowing: boolean;
begin
  Result := (FStrip <> nil) and FStrip.Visible;
end;

procedure TInfoBar.SetControl(AValue: TControl);
begin
  if FControl = AValue then Exit;
  if FControl <> nil then FControl.RemoveFreeNotification(Self);
  FControl := AValue;
  if FControl <> nil then FControl.FreeNotification(Self);
  if Showing then Pin;
end;

procedure TInfoBar.SetEdge(AValue: TInfoBarEdge);
begin
  if FEdge = AValue then Exit;
  FEdge := AValue;
  if Showing then Pin;
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
  ShowStrip(Answers, Captions);
end;

procedure TInfoBar.Show(const AMsg: string; AKind: TMsgDlgType; AButtons: TMsgDlgButtons);
begin
  FText := AMsg;
  FKind := AKind;
  FButtons := AButtons;
  Show;
end;

procedure TInfoBar.ShowQuestion(const AMsg: string; AKind: TMsgDlgType; const AButtons: array of const);
var
  I: integer;
  Answers: array of TModalResult;
  Captions: array of string;
begin
  FText := AMsg;
  FKind := AKind;
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
  ShowStrip(Answers, Captions);
end;

// Lays the strip over the edge of Control, or of the form.
function TInfoBar.Pin: boolean;
var
  Target: TControl;
  Host: TWinControl;
begin
  Result := False;
  Target := FControl;
  if Target = nil then
    if Owner is TControl then Target := GetParentForm(TControl(Owner))
    else
      Target := Application.MainForm;
  if Target = nil then Exit;
  // a form holds the strip itself; any other control, its parent does
  if (Target is TWinControl) and (Target.Parent = nil) then Host := TWinControl(Target)
  else
    Host := Target.Parent;
  if Host = nil then Exit;
  if FStrip = nil then
  begin
    FStrip := TInfoBarStrip.Create(Self);
    FStrip.FreeNotification(Self);
  end;
  FStrip.Parent := Host;
  FStrip.Anchors := [];
  FStrip.AnchorSide[akTop].Control := nil;
  FStrip.AnchorSide[akBottom].Control := nil;
  FStrip.AnchorParallel(akLeft, 0, Target);
  FStrip.AnchorParallel(akRight, 0, Target);
  if FEdge = ieTop then FStrip.AnchorParallel(akTop, 0, Target)
  else
    FStrip.AnchorParallel(akBottom, 0, Target);
  FStrip.BringToFront;
  Result := True;
end;

procedure TInfoBar.ShowStrip(const Answers: array of TModalResult; const Captions: array of string);
begin
  if csDesigning in ComponentState then Exit;
  if FStrip <> nil then FStrip.Hide;
  if not Pin then Exit;
  if (Screen.ActiveControl <> nil) and (Screen.ActiveControl.Parent <> FStrip) then
  begin
    if FFocus <> nil then FFocus.RemoveFreeNotification(Self);
    FFocus := Screen.ActiveControl;
    FFocus.FreeNotification(Self);
  end;
  FStrip.HandleNeeded;
  TInfoBarStrip(FStrip).Rebuild(Answers, Captions);
  FStrip.Show;
  FStrip.BringToFront;
end;

// A clicked button leaves with the bar, so the focus goes back to where it
// was, or else to Control.
procedure TInfoBar.Hide;
var
  HadFocus: boolean;
begin
  if FStrip = nil then Exit;
  HadFocus := (Screen.ActiveControl <> nil) and (Screen.ActiveControl.Parent = FStrip);
  FStrip.Hide;
  if not HadFocus then Exit;
  if (FFocus <> nil) and FFocus.CanFocus then FFocus.SetFocus
  else if (FControl is TWinControl) and TWinControl(FControl).CanFocus then TWinControl(FControl).SetFocus;
end;

procedure TInfoBar.DoAnswer(Answer: TModalResult);
begin
  if Assigned(FOnAnswer) then FOnAnswer(Self, Answer);
end;

end.
