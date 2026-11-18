{
  OpenSloper - parametric sewing pattern drafting
  Copyright (C) 2026 The OpenSloper authors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
}

// The command icons: every one has its file, and each takes the text colour.
unit Sloper.Tests.IconSet;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.AppPaths, Sloper.Core.IconSet;

type
  TTestIconSet = class(TOSTestCase)
  published
    procedure TestIconDirIsFound;
    procedure TestIconDirMissing;
    procedure TestIconDirFromAppFolder;
    procedure TestDataInAppBundleResources;
    procedure TestUserGuideMissing;
    procedure TestUserGuideInDataHelp;
    procedure TestEveryIconHasItsFile;
    procedure TestEveryIconTakesTheTextColour;
    procedure TestTintReplacesEveryCurrentColor;
    procedure TestEveryIconIsDescribed;
    procedure TestEveryCommandHasItsText;
  end;

implementation

uses
  SysUtils, Sloper.Core.JSON;

procedure TTestIconSet.TestIconDirIsFound;
begin
  AssertTrue('found from the tests folder', DirectoryExists(TAppPaths.IconDir));
end;

procedure TTestIconSet.TestIconDirMissing;
begin
  AssertEquals('', TAppPaths.IconDirIn(ConcatPaths([GetTempDir, 'no-such-opensloper-folder', 'bin'])));
end;

// The GUI apps are built in src/<app>, two folders below data/
procedure TTestIconSet.TestIconDirFromAppFolder;
var
  AppDir: string;
begin
  AppDir := ConcatPaths([ExtractFilePath(ParamStr(0)), '..', 'src', 'design']);
  AssertEquals(TAppPaths.IconDir, TAppPaths.IconDirIn(AppDir));
  AssertEquals(TAppPaths.CatalogueFile, TAppPaths.CatalogueFileIn(AppDir));
end;

// A macOS app bundle has its programs in Contents/MacOS and its data in
// Contents/Resources, since code signing takes only programs in MacOS
procedure TTestIconSet.TestDataInAppBundleResources;
var
  Bundle, Programs, Icons: string;
begin
  Bundle := ConcatPaths([GetTempDir, 'opensloper-bundle-test.app', 'Contents']);
  Programs := ConcatPaths([Bundle, 'MacOS']);
  Icons := ConcatPaths([Bundle, 'Resources', 'data', 'icons']);
  try
    AssertTrue('made', ForceDirectories(Programs) and ForceDirectories(Icons));
    AssertEquals(ExpandFileName(Icons), TAppPaths.IconDirIn(Programs));
  finally
    RemoveDir(Icons);
    RemoveDir(ExtractFileDir(Icons));
    RemoveDir(ConcatPaths([Bundle, 'Resources']));
    RemoveDir(Programs);
    RemoveDir(Bundle);
    RemoveDir(ExtractFileDir(Bundle));
  end;
end;

// The source tree has no offline copy of the site; the downloads do
procedure TTestIconSet.TestUserGuideMissing;
begin
  AssertEquals('', TAppPaths.UserGuideFileIn(ConcatPaths([GetTempDir, 'no-such-opensloper-folder', 'bin'])));
end;

procedure TTestIconSet.TestUserGuideInDataHelp;
var
  Root, Help, Page, Err: string;
begin
  Root := ConcatPaths([GetTempDir, 'opensloper-help-test']);
  Help := ConcatPaths([Root, 'data', 'help']);
  Page := ConcatPaths([Help, 'index.html']);
  try
    AssertTrue('made', ForceDirectories(Help));
    AssertTrue(Err, WriteTextFile(Page, '<html></html>', Err));
    AssertEquals(ExpandFileName(Page), TAppPaths.UserGuideFileIn(Root));
  finally
    DeleteFile(Page);
    RemoveDir(Help);
    RemoveDir(ExtractFileDir(Help));
    RemoveDir(Root);
  end;
end;

procedure TTestIconSet.TestEveryIconHasItsFile;
var
  Icon: TAppIcon;
begin
  for Icon := Low(TAppIcon) to High(TAppIcon) do
    AssertTrue(APP_ICON_NAMES[Icon], FileExists(IconFileName(TAppPaths.IconDir, Icon)));
end;

procedure TTestIconSet.TestEveryIconTakesTheTextColour;
var
  Icon: TAppIcon;
  Text, Err: string;
begin
  for Icon := Low(TAppIcon) to High(TAppIcon) do
  begin
    AssertTrue(Err, ReadTextFile(IconFileName(TAppPaths.IconDir, Icon), Text, Err));
    AssertTrue(APP_ICON_NAMES[Icon], Pos('currentColor', Text) > 0);
  end;
end;

procedure TTestIconSet.TestTintReplacesEveryCurrentColor;
var
  Text: string;
begin
  Text := TintedSVG('<svg stroke="currentColor"><path fill="currentColor"/></svg>', '#112233');
  AssertEquals('<svg stroke="#112233"><path fill="#112233"/></svg>', Text);
end;

// The Icons reference page lists every icon, so a new one needs a row there
procedure TTestIconSet.TestEveryIconIsDescribed;
var
  Icon: TAppIcon;
  Command: TIconCommand;
  Found: boolean;
begin
  for Icon := Low(TAppIcon) to High(TAppIcon) do
  begin
    Found := False;
    for Command in IconCommands do
      Found := Found or (Command.Icon = Icon);
    AssertTrue(APP_ICON_NAMES[Icon] + ' is on the Icons page', Found);
  end;
end;

procedure TTestIconSet.TestEveryCommandHasItsText;
var
  Command: TIconCommand;
begin
  for Command in IconCommands do
  begin
    AssertTrue(APP_ICON_NAMES[Command.Icon] + ' has a name', Command.Name <> '');
    AssertTrue(Command.Name + ' has a description', Command.Description <> '');
    AssertTrue(Command.Name + ' has a menu, unless it is in the properties', (Command.Menu <> '') = (Command.Place <> ipProperties));
  end;
end;

initialization
  RegisterTest(TTestIconSet);

end.
