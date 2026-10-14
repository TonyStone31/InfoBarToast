program bartest;

{$mode objfpc}{$H+}
// Copyright (c) 2026 Tony Stone. 0BSD; see LICENSE.

{ Shows TInfoBar and TToast on a bare form, presses their buttons the way a
  click does, and checks what came back.  Exit code is the number of
  failures. }

uses
  {$ifdef unix}cthreads,{$endif}
  Interfaces,
  Forms,
  Controls,
  StdCtrls,
  Buttons,
  Dialogs,
  Classes,
  SysUtils,
  InfoBar,
  Toast;

type
  TRecorder = class
    Answers: TStringList;
    Actions: integer;
    LastKey: string;
    procedure Answered(Sender: TObject; const Key: string; Answer: TModalResult);
    procedure Acted(Sender: TObject);
  end;

var
  Form: TForm;
  Memo: TMemo;
  Bar: TInfoBar;
  Popup: TToast;
  Rec: TRecorder;
  Failures: integer = 0;

  procedure TRecorder.Answered(Sender: TObject; const Key: string; Answer: TModalResult);
  begin
    Answers.Add(IntToStr(Answer));
    LastKey := Key;
  end;

  procedure TRecorder.Acted(Sender: TObject);
  begin
    Inc(Actions);
  end;

  procedure Settle(Ms: integer = 300);
  var
    Deadline: QWord;
  begin
    Deadline := GetTickCount64 + Ms;
    while GetTickCount64 < Deadline do
    begin
      Application.ProcessMessages;
      Sleep(10);
    end;
  end;

  procedure Check(const What: string; Ok: boolean; const Detail: string = '');
  begin
    if Ok then WriteLn('ok    ', What)
    else
    begin
      WriteLn('FAIL  ', What, '  ', Detail);
      Inc(Failures);
    end;
  end;

  // The visible strip a bar or toast put on the form, the topmost one.
  function Strip(const AClassName: string): TWinControl;
  var
    I: integer;
  begin
    Result := nil;
    for I := 0 to Form.ControlCount - 1 do
      if (Form.Controls[I].ClassName = AClassName) and Form.Controls[I].Visible and ((Result = nil) or (Form.Controls[I].Top < Result.Top)) then
        Result := TWinControl(Form.Controls[I]);
  end;

  // The visible info bar strips, top to bottom, by the text they show.
  function Strips: string;
  var
    I, J: integer;
    L: TStringList;
  begin
    L := TStringList.Create;
    try
      for I := 0 to Form.ControlCount - 1 do
        if (Form.Controls[I].ClassName = 'TInfoBarStrip') and Form.Controls[I].Visible then
          L.AddObject(Format('%.5d', [Form.Controls[I].Top]), Form.Controls[I]);
      L.Sort;
      Result := '';
      for I := 0 to L.Count - 1 do
        for J := 0 to TWinControl(L.Objects[I]).ControlCount - 1 do
          if TWinControl(L.Objects[I]).Controls[J] is TButton then
          begin
            Result := Result + TWinControl(L.Objects[I]).Controls[J].Caption + '|';
            Break;
          end;
    finally
      L.Free;
    end;
  end;

  // The strip's button with this caption, as a user sees it.
  function Button(const Caption: string): TControl;
  var
    S: TWinControl;
    I: integer;
  begin
    Result := nil;
    S := Strip('TInfoBarStrip');
    if S = nil then Exit;
    for I := 0 to S.ControlCount - 1 do
      if StringReplace(S.Controls[I].Caption, '&', '', [rfReplaceAll]) = Caption then Exit(S.Controls[I]);
  end;

  procedure Press(const Caption: string);
  var
    B: TControl;
  begin
    B := Button(Caption);
    if B is TButton then TButton(B).Click
    else if B is TSpeedButton then TSpeedButton(B).Click;
    Settle(50);
  end;

  function LastAnswer: string;
  begin
    if Rec.Answers.Count = 0 then Result := '(none)'
    else
      Result := Rec.Answers[Rec.Answers.Count - 1];
  end;

  function Captions: string;
  var
    S: TWinControl;
    I: integer;
  begin
    Result := '';
    S := Strip('TInfoBarStrip');
    for I := 0 to S.ControlCount - 1 do
      if S.Controls[I] is TButton then Result := Result + S.Controls[I].Caption + '|';
  end;

begin
  Application.Initialize;
  Rec := TRecorder.Create;
  Rec.Answers := TStringList.Create;
  Form := TForm.CreateNew(nil);
  Form.SetBounds(10, 10, 640, 400);
  Memo := TMemo.Create(Form);
  Memo.SetBounds(200, 50, 400, 300);
  Memo.Parent := Form;
  Bar := TInfoBar.Create(Form);
  Bar.OnAnswer := @Rec.Answered;
  Popup := TToast.Create(Form);
  Popup.OnAction := @Rec.Acted;
  Form.Show;
  Settle;

  // the dialog's buttons, in the dialog's order, with the LCL's captions
  Bar.Show('Load the new version?', mtConfirmation, [mbYes, mbNo]);
  Settle;
  Check('shows', Bar.Showing);
  Check('covers the form''s width', (Strip('TInfoBarStrip') <> nil) and (Strip('TInfoBarStrip').Width = Form.ClientWidth),
    IntToStr(Strip('TInfoBarStrip').Width) + ' of ' + IntToStr(Form.ClientWidth));
  Check('lies at the top', Strip('TInfoBarStrip').Top = 0, IntToStr(Strip('TInfoBarStrip').Top));
  Check('Yes and No, in that order', Captions = 'Yes|No|', Captions);
  Press('Yes');
  Check('Yes answers mrYes', LastAnswer = IntToStr(mrYes), LastAnswer);
  Check('answering hides it', not Bar.Showing);

  // QuestionDlg's buttons: own captions, and a default one
  Bar.ShowQuestion('notes.md changed on disk.', mtWarning, [mrYes, '&Reload', mrNo, '&Keep mine', mrCancel]);
  Settle;
  Check('own captions', Captions = 'Reload|Keep mine|Cancel|', Captions);
  Press('Keep mine');
  Check('Keep mine answers mrNo', LastAnswer = IntToStr(mrNo), LastAnswer);

  // the close button
  Bar.Show('Just so you know.', mtInformation, []);
  Settle;
  Check('no buttons', Captions = '', Captions);
  Press('×');
  Check('close answers mrClose', LastAnswer = IntToStr(mrClose), LastAnswer);
  Check('closing hides it', not Bar.Showing);

  // Help answers and stays, as in a dialog
  Bar.Show('Something to read about.', mtInformation, [mbOK, mbHelp]);
  Settle;
  Press('Help');
  Check('Help answers mrNone', LastAnswer = IntToStr(mrNone), LastAnswer);
  Check('Help leaves it up', Bar.Showing);
  Bar.Hide;

  // the focus goes back where it was when the clicked button leaves
  Memo.SetFocus;
  Settle;
  if not Memo.Focused then WriteLn('skip  focus: this session cannot take the keyboard focus')
  else
  begin
    Bar.Show('Click OK.', mtInformation, [mbOK]);
    Settle;
    TButton(Button('OK')).SetFocus;
    Settle;
    Press('OK');
    Settle;
    Check('focus goes back to the memo', Memo.Focused);
  end;

  // pinned to the bottom of another control, at its width
  Bar.Control := Memo;
  Bar.Edge := ieBottom;
  Bar.Show('Could not save.', mtError, [mbRetry]);
  Settle;
  with Strip('TInfoBarStrip') do
  begin
    Check('takes the memo''s left and width', (Left = Memo.Left) and (Width = Memo.Width),
      Format('%d,%d', [Left, Width]));
    Check('lies on the memo''s bottom edge', Top + Height = Memo.Top + Memo.Height,
      Format('%d+%d vs %d', [Top, Height, Memo.Top + Memo.Height]));
  end;
  Memo.Width := 300;
  Settle;
  Check('follows the memo''s new width', Strip('TInfoBarStrip').Width = 300, IntToStr(Strip('TInfoBarStrip').Width));
  Memo.Width := 150;
  Settle;
  Check('narrow: the button goes under the text',
    Button('Retry').Top > Strip('TInfoBarStrip').Height div 2, IntToStr(Button('Retry').Top));

  // moved while up: another control, another edge
  Bar.Control := nil;
  Settle;
  with Strip('TInfoBarStrip') do
    Check('moves to the form while up', Visible and (Width = Form.ClientWidth) and (Top + Height = Form.ClientHeight),
      Format('%d,%d,%d', [Top, Width, Height]));
  Bar.Edge := ieTop;
  Settle;
  Check('and to its top', Strip('TInfoBarStrip').Top = 0, IntToStr(Strip('TInfoBarStrip').Top));
  Bar.Hide;

  // several stack, errors first, oldest first among the rest
  Bar.Control := nil;
  Bar.Edge := ieTop;
  Bar.Show('First.', mtInformation, [mbOK], 'one');
  Bar.Show('Second.', mtInformation, [mbYes], 'two');
  Bar.Show('Broken.', mtError, [mbRetry], 'three');
  Settle;
  Check('three stack, the error on top', Strips = 'Retry|OK|Yes|', Strips);
  Check('Count is three', Bar.Count = 3, IntToStr(Bar.Count));
  // the same key again replaces, it does not add
  Bar.Show('First, said again.', mtInformation, [mbOK], 'one');
  Settle;
  Check('the same key replaces', (Bar.Count = 3) and Bar.Has('one'), IntToStr(Bar.Count));
  // answering one takes it away and tells which
  Press('Retry');
  Check('answered with its key', Rec.LastKey = 'three', Rec.LastKey);
  Check('two left', Strips = 'OK|Yes|', Strips);
  // taken back without an answer
  Bar.Hide('one');
  Settle;
  Check('Hide by key', not Bar.Has('one') and (Strips = 'Yes|'), Strips);
  Bar.Hide;
  Settle;
  Check('Hide takes them all', Bar.Count = 0, IntToStr(Bar.Count));
  // one at a time: the others wait, counted on the strip
  Bar.MaxVisible := 1;
  Bar.Show('First.', mtInformation, [mbOK], 'one');
  Bar.Show('Second.', mtInformation, [mbYes], 'two');
  Bar.Show('Third.', mtInformation, [mbNo], 'three');
  Settle;
  Check('MaxVisible 1 shows one', Strips = 'OK|', Strips);
  Press('OK');
  Settle;
  Check('the next comes up', Strips = 'Yes|', Strips);
  Bar.Hide;
  Bar.MaxVisible := 3;
  Settle;

  // a toast comes, waits and goes
  Popup.Duration := 400;
  Popup.Show('Saved.');
  Settle(300);
  Check('toast shows', Popup.Showing and (Strip('TToastStrip') <> nil));
  Check('toast is centered on the form',
    Abs(Strip('TToastStrip').Left + Strip('TToastStrip').Width div 2 - Form.ClientWidth div 2) <= 1,
    IntToStr(Strip('TToastStrip').Left));
  Check('toast sits above the bottom edge',
    Strip('TToastStrip').Top + Strip('TToastStrip').Height < Form.ClientHeight,
    IntToStr(Strip('TToastStrip').Top));
  Settle(900);
  Check('toast goes by itself', Strip('TToastStrip') = nil);

  // showing again replaces the words and waits again
  Popup.Duration := 600;
  Popup.Show('First.');
  Settle(400);
  Popup.Show('Second.', 'Undo');
  Settle(400);
  Check('replaced, not gone', Popup.Showing and (Popup.Text = 'Second.'), Popup.Text);
  Popup.Hide;
  Settle(600);
  Check('Hide sends it away', Strip('TToastStrip') = nil);

  Form.Free;
  Rec.Answers.Free;
  Rec.Free;
  WriteLn(Failures, ' failed');
  Halt(Failures);
end.
