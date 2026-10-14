unit DemoMain;

{$mode objfpc}{$H+}
// Copyright (c) 2026 Tony Stone. 0BSD; see LICENSE.

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, InfoBar, Toast;

type

  { TDemoForm }

  TDemoForm = class(TForm)
    Buttons: TPanel;
    ErrorBarButton: TButton;
    FormBar: TInfoBar;
    FormBarButton: TButton;
    Memo: TMemo;
    MemoBar: TInfoBar;
    MemoBarButton: TButton;
    Notes: TListBox;
    Splitter: TSplitter;
    Toast: TToast;
    UndoToastButton: TButton;
    procedure ErrorBarButtonClick(Sender: TObject);
    procedure FormBarAnswer(Sender: TObject; Answer: TModalResult);
    procedure FormBarButtonClick(Sender: TObject);
    procedure MemoBarAnswer(Sender: TObject; Answer: TModalResult);
    procedure MemoBarButtonClick(Sender: TObject);
    procedure ToastAction(Sender: TObject);
    procedure UndoToastButtonClick(Sender: TObject);
  end;

var
  DemoForm: TDemoForm;

implementation

{$R *.lfm}

{ TDemoForm }

procedure TDemoForm.FormBarButtonClick(Sender: TObject);
begin
  FormBar.ShowQuestion('notes.md was changed by another program.', mtWarning,
    [mrYes, '&Reload', mrNo, '&Keep mine']);
end;

procedure TDemoForm.FormBarAnswer(Sender: TObject; Answer: TModalResult);
begin
  case Answer of
    mrYes: Toast.Show('Reloaded.');
    mrNo: Toast.Show('Kept yours.');
  end;
end;

procedure TDemoForm.MemoBarButtonClick(Sender: TObject);
begin
  MemoBar.Edge := ieTop;
  MemoBar.Show('This bar lies on the memo only. Drag the splitter and it follows.', mtInformation, [mbOK, mbHelp]);
end;

procedure TDemoForm.ErrorBarButtonClick(Sender: TObject);
begin
  MemoBar.Edge := ieBottom;
  MemoBar.Show('Could not save notes.md: the disk is full.', mtError, [mbRetry, mbCancel]);
end;

procedure TDemoForm.MemoBarAnswer(Sender: TObject; Answer: TModalResult);
begin
  // Help answers mrNone and leaves the bar up
  if Answer = mrNone then Toast.Show('Help was asked for.')
  else
    Toast.Show('Answered.');
end;

procedure TDemoForm.ToastAction(Sender: TObject);
begin
  Toast.Show('Undone.');
end;

procedure TDemoForm.UndoToastButtonClick(Sender: TObject);
begin
  Toast.Show('3 lines deleted.', 'Undo');
end;

end.
