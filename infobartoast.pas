{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit InfoBarToast;

{$warn 5023 off : no warning about unused units}
interface

uses
  InfoBar, Toast, InfoBarToastReg, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('InfoBarToastReg', @InfoBarToastReg.Register);
end;

initialization
  RegisterPackage('InfoBarToast', @Register);
end.
