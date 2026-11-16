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

unit Sloper.Tests.AppPaths;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.AppPaths;

type
  TTestAppPaths = class(TOSTestCase)
  published
    procedure TestXdgAbsoluteValueIsUsed;
    procedure TestXdgEmptyValueFallsBack;
    procedure TestXdgRelativeValueIsIgnored;
    procedure TestFoldersEndWithAppName;
    procedure TestSettingsFileIsInConfigDir;
    procedure TestRecentFilesFileIsInStateDir;
    procedure TestNotPortableWithoutIni;
    procedure TestPortableBesideTheProgram;
    procedure TestPortableBesideTheBundle;
    procedure TestPortableFilesApartFromShippedData;
  end;

implementation

uses
  SysUtils, StrUtils;

procedure TTestAppPaths.TestXdgAbsoluteValueIsUsed;
var
  Dir: string;
begin
  Dir := PathDelim + ConcatPaths(['tmp', 'cfg']);
  AssertEquals(Dir, TAppPaths.ResolveXdgDir(Dir + PathDelim, PathDelim + 'home', '.config'));
end;

procedure TTestAppPaths.TestXdgEmptyValueFallsBack;
begin
  AssertEquals(ConcatPaths([PathDelim + 'home', '.config']),
    TAppPaths.ResolveXdgDir('', PathDelim + 'home', '.config'));
end;

procedure TTestAppPaths.TestXdgRelativeValueIsIgnored;
begin
  AssertEquals(ConcatPaths([PathDelim + 'home', '.cache']),
    TAppPaths.ResolveXdgDir('relative' + PathDelim + 'dir', PathDelim + 'home', '.cache'));
end;

procedure TTestAppPaths.TestFoldersEndWithAppName;
begin
  if TAppPaths.IsPortable then
    Exit;
  AssertTrue('config', AnsiEndsText('opensloper', TAppPaths.ConfigDir));
  AssertTrue('data', AnsiEndsText('opensloper', TAppPaths.DataDir));
  AssertTrue('documents', AnsiEndsText('opensloper', TAppPaths.DefaultDocumentsDir));
end;

procedure TTestAppPaths.TestSettingsFileIsInConfigDir;
begin
  AssertEquals(ConcatPaths([TAppPaths.ConfigDir, 'settings.json']), TAppPaths.SettingsFile);
end;

procedure TTestAppPaths.TestRecentFilesFileIsInStateDir;
begin
  AssertEquals(ConcatPaths([TAppPaths.StateDir, 'recent-files.json']), TAppPaths.RecentFilesFile);
end;

// Where the tests below make their folders
function TestRoot: string;
begin
  Result := ConcatPaths([GetTempDir, 'opensloper-portable-test-' + IntToStr(GetProcessID)]);
end;

// A folder in TestRoot, with portable.ini in it when WithIni
function PortableFolder(const Name: string; WithIni: boolean): string;
var
  Ini: TextFile;
begin
  Result := ConcatPaths([TestRoot, Name]);
  ForceDirectories(Result);
  if not WithIni then
    Exit;
  AssignFile(Ini, ConcatPaths([Result, 'portable.ini']));
  Rewrite(Ini);
  CloseFile(Ini);
end;

procedure RemoveTree(const Folder: string);
var
  Found: TSearchRec;
begin
  if FindFirst(ConcatPaths([Folder, AllFilesMask]), faAnyFile or faDirectory, Found) = 0 then
  try
    repeat
      if (Found.Name = '.') or (Found.Name = '..') then
        Continue;
      if (Found.Attr and faDirectory) <> 0 then
        RemoveTree(ConcatPaths([Folder, Found.Name]))
      else
        DeleteFile(ConcatPaths([Folder, Found.Name]));
    until FindNext(Found) <> 0;
  finally
    FindClose(Found);
  end;
  RemoveDir(Folder);
end;

procedure TTestAppPaths.TestNotPortableWithoutIni;
begin
  try
    AssertEquals('', TAppPaths.PortableRootIn(PortableFolder('plain', False)));
  finally
    RemoveTree(TestRoot);
  end;
end;

procedure TTestAppPaths.TestPortableBesideTheProgram;
var
  Folder: string;
begin
  try
    Folder := PortableFolder('stick', True);
    AssertEquals(Folder, TAppPaths.PortableRootIn(Folder));
    AssertEquals('a trailing delimiter', Folder, TAppPaths.PortableRootIn(Folder + PathDelim));
  finally
    RemoveTree(TestRoot);
  end;
end;

// Signing takes nothing new inside the bundle, so portable.ini lies beside it
procedure TTestAppPaths.TestPortableBesideTheBundle;
var
  Folder, Programs: string;
begin
  try
    Folder := PortableFolder('mac', True);
    Programs := ConcatPaths([Folder, 'OpenSloper.app', 'Contents', 'MacOS']);
    ForceDirectories(Programs);
    AssertEquals(Folder, TAppPaths.PortableRootIn(Programs));
    Programs := ConcatPaths([Folder, 'Other', 'Contents', 'MacOS']);
    ForceDirectories(Programs);
    AssertEquals('not a bundle', '', TAppPaths.PortableRootIn(Programs));
  finally
    RemoveTree(TestRoot);
  end;
end;

// The data folder beside the programs is what they ship with
procedure TTestAppPaths.TestPortableFilesApartFromShippedData;
var
  Root: string;
begin
  Root := PathDelim + 'stick';
  AssertEquals(ConcatPaths([Root, 'user', 'config']), TAppPaths.PortableDirIn(Root, 'config'));
  AssertEquals(ConcatPaths([Root, 'user', 'data']), TAppPaths.PortableDirIn(Root, 'data'));
end;

initialization
  RegisterTest(TTestAppPaths);

end.
