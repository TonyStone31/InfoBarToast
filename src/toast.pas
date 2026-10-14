{ TToast

  A short message that rises into view over the bottom (or top) of a
  control - the form when Control is empty - stays a few seconds and goes
  away by itself.  "Saved", "Copied", "3 files added".  It can carry one action,
  such as "Undo".  Not the desktop's own notifications: those are
  TPopupNotifier and, in FPC's vcl-compat, TNotificationCenter.

  Copyright (c) 2026 Tony Stone. 0BSD; see LICENSE.
}
unit Toast;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  // LCL
  LCLType, LCLIntf, Controls, Forms, Graphics, ExtCtrls;

type
  TToastEdge = (teBottom, teTop);

  { TToast }

  TToast = class(TComponent)
  private
    FAction: string;
    FControl: TControl;
    FDuration: integer;
    FEdge: TToastEdge;
    FStrip: TCustomControl;
    FText: string;
    FTimer: TTimer;
    FStep: integer; // 0 at the edge to Steps in place
    FMoving: integer; // +1 coming, -1 going, 0 still
    FOnAction: TNotifyEvent;
    function GetShowing: boolean;
    procedure SetControl(AValue: TControl);
    procedure TimerTick(Sender: TObject);
    procedure Place;
    procedure Wait;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DoAction; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Shows the message, or replaces the one showing.
    procedure Show(const AText: string; const AAction: string = '');
    procedure Hide;
    property Showing: boolean read GetShowing;
    property Text: string read FText;
  published
    // What the toast shows over.  Empty: the form.
    property Control: TControl read FControl write SetControl;
    // Milliseconds in place; the mouse over it holds it there.
    property Duration: integer read FDuration write FDuration default 3000;
    property Edge: TToastEdge read FEdge write FEdge default teBottom;
    // The action was clicked.  The toast is already going.
    property OnAction: TNotifyEvent read FOnAction write FOnAction;
  end;

implementation

const
  Steps = 8;      // frames of the rise
  StepMs = 16;
  Margin = 16;    // at 96 PPI, from the edge
  Pad = 10;       // at 96 PPI, inside
  MaxWidth = 560; // at 96 PPI

type

  { TToastStrip - what is seen; made by the first Show }

  TToastStrip = class(TCustomControl)
  private
    FToast: TToast;
    FTarget: TControl;
    FHot: boolean;
    function ActionWidth: integer;
    function ActionRect: TRect;
    function TextBounds(AWidth: integer): TRect;
    function Colors(out Fore: TColor): TColor;
  protected
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: integer;
    {%H-}WithThemeSpace: boolean); override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure Paint; override;
  public
    constructor Create(AToast: TToast); reintroduce;
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

{ TToastStrip }

constructor TToastStrip.Create(AToast: TToast);
begin
  inherited Create(AToast);
  FToast := AToast;
  ControlStyle := ControlStyle - [csAcceptsControls, csSetCaption] + [csOpaque];
  AutoSize := True;
  Visible := False;
end;

// The window colors inverted and softened: dark on a light desktop, light
// on a dark one.
function TToastStrip.Colors(out Fore: TColor): TColor;
begin
  Result := MixColors(clWindowText, clWindow, 85);
  Fore := clWindow;
end;

function TToastStrip.ActionWidth: integer;
begin
  Result := 0;
  if FToast.FAction = '' then Exit;
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Result := Canvas.TextWidth(FToast.FAction) + Scale96ToFont(Pad) * 2;
end;

function TToastStrip.ActionRect: TRect;
begin
  Result := ClientRect;
  Result.Left := Result.Right - ActionWidth;
end;

// The message's size when it may be AWidth wide.
function TToastStrip.TextBounds(AWidth: integer): TRect;
begin
  Result := Rect(0, 0, Max(AWidth, 1), 0);
  Canvas.Font := Font;
  DrawText(Canvas.Handle, PChar(FToast.Text), Length(FToast.Text), Result,
    DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
end;

procedure TToastStrip.CalculatePreferredSize(var PreferredWidth, PreferredHeight: integer; WithThemeSpace: boolean);
var
  Room: integer;
  R: TRect;
begin
  if not HandleAllocated or (FTarget = nil) then Exit;
  Room := Min(Scale96ToFont(MaxWidth), FTarget.Width - Scale96ToFont(Margin) * 2);
  R := TextBounds(Room - Scale96ToFont(Pad) * 2 - ActionWidth);
  PreferredWidth := R.Width + Scale96ToFont(Pad) * 2 + ActionWidth;
  PreferredHeight := R.Height + Scale96ToFont(Pad) * 2;
end;

procedure TToastStrip.Paint;
var
  Back, Fore: TColor;
  R, ActionR: TRect;
begin
  // measured first: measuring sets the canvas font
  ActionR := ActionRect;
  Back := Colors(Fore);
  Canvas.Brush.Color := Back;
  Canvas.Pen.Color := MixColors(Fore, Back, 25);
  Canvas.Rectangle(ClientRect);

  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  Canvas.Font.Color := Fore;
  R := ClientRect;
  InflateRect(R, -Scale96ToFont(Pad), -Scale96ToFont(Pad));
  R.Right := ActionR.Left;
  DrawText(Canvas.Handle, PChar(FToast.Text), Length(FToast.Text), R, DT_WORDBREAK or DT_NOPREFIX);

  if FToast.FAction <> '' then
  begin
    Canvas.Font.Style := [fsBold];
    if FHot then Canvas.Font.Style := [fsBold, fsUnderline];
    DrawText(Canvas.Handle, PChar(FToast.FAction), Length(FToast.FAction), ActionR,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  end;
end;

procedure TToastStrip.MouseEnter;
begin
  inherited MouseEnter;
  // held while the mouse is on it
  FToast.FTimer.Enabled := FToast.FMoving <> 0;
end;

procedure TToastStrip.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  Invalidate;
  if FToast.FMoving = 0 then FToast.Wait;
end;

procedure TToastStrip.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Hot: boolean;
begin
  inherited MouseMove(Shift, X, Y);
  Hot := (FToast.FAction <> '') and PtInRect(ActionRect, Point(X, Y));
  if Hot = FHot then Exit;
  FHot := Hot;
  if Hot then Cursor := crHandPoint
  else
    Cursor := crDefault;
  Invalidate;
end;

// A click on the action runs it; a click anywhere sends the toast away.
procedure TToastStrip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  OnAction: boolean;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  OnAction := (FToast.FAction <> '') and PtInRect(ActionRect, Point(X, Y));
  FToast.Hide;
  if OnAction then FToast.DoAction;
end;

{ TToast }

constructor TToast.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDuration := 3000;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;
end;

destructor TToast.Destroy;
begin
  FTimer.Enabled := False;
  FreeAndNil(FStrip);
  inherited Destroy;
end;

procedure TToast.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then Exit;
  if AComponent = FControl then
  begin
    FControl := nil;
    Hide;
  end
  else if AComponent = FStrip then
    FStrip := nil;
end;

function TToast.GetShowing: boolean;
begin
  Result := (FStrip <> nil) and FStrip.Visible and (FMoving >= 0);
end;

procedure TToast.SetControl(AValue: TControl);
begin
  if FControl = AValue then Exit;
  if FControl <> nil then FControl.RemoveFreeNotification(Self);
  FControl := AValue;
  if FControl <> nil then FControl.FreeNotification(Self);
end;

procedure TToast.Show(const AText: string; const AAction: string);
var
  Target: TControl;
  Host: TWinControl;
  Strip: TToastStrip;
begin
  if csDesigning in ComponentState then Exit;
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

  FText := AText;
  FAction := AAction;
  if FStrip = nil then
  begin
    FStrip := TToastStrip.Create(Self);
    FStrip.FreeNotification(Self);
  end;
  Strip := TToastStrip(FStrip);
  Strip.FTarget := Target;
  Strip.FHot := False;
  Strip.Cursor := crDefault;
  if Strip.Parent <> Host then Strip.Parent := Host;
  Strip.Anchors := [];
  Strip.AnchorSide[akTop].Control := nil;
  Strip.AnchorSide[akBottom].Control := nil;
  Strip.AnchorHorizontalCenterTo(Target);
  if FEdge = teBottom then Strip.AnchorParallel(akBottom, 0, Target)
  else
    Strip.AnchorParallel(akTop, 0, Target);
  Strip.HandleNeeded;
  Strip.InvalidatePreferredSize;
  Strip.AdjustSize;
  Strip.Invalidate;
  if Strip.Visible then
  begin
    // already up: new text and the wait starts over; leaving: it comes back
    if FMoving = 0 then Wait
    else
      FMoving := 1;
    Exit;
  end;
  FStep := 0;
  FMoving := 1;
  Place;
  Strip.Show;
  Strip.BringToFront;
  FTimer.Interval := StepMs;
  FTimer.Enabled := True;
end;

procedure TToast.Hide;
begin
  if not Showing then Exit;
  FMoving := -1;
  FTimer.Interval := StepMs;
  FTimer.Enabled := True;
end;

procedure TToast.Wait;
begin
  FMoving := 0;
  FTimer.Enabled := False;
  FTimer.Interval := FDuration;
  FTimer.Enabled := True;
end;

// It rises from the edge to Margin above it.  Coming from beyond the edge
// would cross whatever lies below a control, and the LCL takes a negative
// border spacing as none anyway.
procedure TToast.Place;
var
  Space: integer;
begin
  Space := FStrip.Scale96ToFont(Margin) * FStep div Steps;
  if FEdge = teBottom then FStrip.BorderSpacing.Bottom := Space
  else
    FStrip.BorderSpacing.Top := Space;
end;

procedure TToast.TimerTick(Sender: TObject);
begin
  if FStrip = nil then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  case FMoving of
    0: Hide; // Duration is up
    1:
    begin
      Inc(FStep);
      Place;
      if FStep >= Steps then Wait;
    end;
    -1:
    begin
      Dec(FStep);
      Place;
      if FStep <= 0 then
      begin
        FTimer.Enabled := False;
        FMoving := 0;
        FStrip.Hide;
      end;
    end;
  end;
end;

procedure TToast.DoAction;
begin
  if Assigned(FOnAction) then FOnAction(Self);
end;

end.
