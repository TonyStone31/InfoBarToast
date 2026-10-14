# InfoBarToast

Two non-visual Lazarus components, plain LCL, for Linux, Windows and macOS.

- **TInfoBar** is MessageDlg without the dialog. It puts a strip with the
  message, the dialog icon and the buttons over the top or bottom edge of
  the form or of any control, and nothing waits for it.
- **TToast** shows a short message near the bottom of the form for a few
  seconds, with an optional action such as Undo.

![The demo on Linux](images/infobartoast-demo-linux.png)

## TInfoBar

```pascal
InfoBar1.Show('Load the new version of notes.md?', mtConfirmation, [mbYes, mbNo]);

// QuestionDlg style, for your own captions
InfoBar1.ShowQuestion('notes.md was changed by another program.', mtWarning,
  [mrYes, '&Reload', mrNo, '&Keep mine']);
```

The answer arrives in `OnAnswer` as the `ModalResult` MessageDlg would have
returned. Answering hides the bar, except Help, which answers `mrNone`. The
close button answers `mrClose`.

`Control` is what the bar lies on; leave it empty for the form. The bar
takes that control's width and follows it when the window or a splitter
moves. `Edge` is `ieTop` or `ieBottom`. The bar covers the control's edge
while it is up; it does not move anything else on the form.

## TToast

```pascal
Toast1.Show('Saved.');
Toast1.Show('3 lines deleted.', 'Undo');   // OnAction runs if Undo is clicked
```

It stays `Duration` milliseconds (3000), or longer while the mouse is on it.
A click sends it away. For the desktop's own notifications use
`TPopupNotifier`.

## Install

Open `infobartoast.lpk` in Lazarus, compile and install. Both components go
on the **LazControls** tab. `demo/` is the program in the picture; `tests/`
checks both on all three systems.

Tested on Linux (GTK3), Windows 10 and macOS 15, with Lazarus 4.8 and
FPC 3.2.4 as well as the development versions.

## License

[0BSD](LICENSE)
