unit InfoBarToastReg;

{$mode objfpc}{$H+}
// Copyright (c) 2026 Tony Stone. 0BSD; see LICENSE.

interface

procedure Register;

implementation

uses Classes, LResources, InfoBar, Toast;

procedure Register;
begin
  RegisterComponents('LazControls', [TInfoBar, TToast]);
end;

initialization
  {$I infobartoastpalette.lrs}
end.
