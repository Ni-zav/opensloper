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

// Versions of the user's file formats (issue #42). Each format has one
// reader, for its current version; a file of an older version is brought up
// to it first by upgrade steps on its parsed JSON, one step for each version,
// so version 1 goes through every step and the current version through none.
// Files are always written at the current version. No LCL dependency.
unit Sloper.Core.FileVersions;

{$mode ObjFPC}{$H+}

interface

uses
  fpjson;

type
  // Rewrites a file's JSON from one version into the next. False, with
  // ErrorMessage, when the file cannot be brought up to it.
  TFileUpgradeStep = function(Root: TJSONObject; out ErrorMessage: string): boolean;

  TFormatVersions = record
    // The version files are written at
    Current: integer;
    // Steps[0] takes version 1 to 2, Steps[1] version 2 to 3, and so on:
    // one fewer than Current
    Steps: array of TFileUpgradeStep;
  end;

  TVersionCheck = (vcCurrent, vcUpgraded, vcNewer, vcInvalid, vcFailed);

// Brings Root, a file of Version, up to Versions.Current, setting its
// "version" member as each step is taken. vcNewer for a version above Current
// and vcInvalid for one below 1 leave Root as it was; vcFailed has
// ErrorMessage from the step that failed. ErrorMessage says why for all three.
function UpgradeFile(Root: TJSONObject; Version: integer; const Versions: TFormatVersions; out ErrorMessage: string): TVersionCheck;

resourcestring
  rsFileVersionInvalid = 'The file says it is version %d, but versions start at 1';
  rsFileVersionNewer = 'This file was made by a newer version of OpenSloper (file version %d)';
  // The version a step failed to reach, and why
  rsFileVersionStepFailed = 'The file could not be brought up to version %d: %s';
  rsFileVersionNoStep = 'There is no way to bring the file up from version %d';

implementation

uses
  SysUtils;

function UpgradeFile(Root: TJSONObject; Version: integer; const Versions: TFormatVersions; out ErrorMessage: string): TVersionCheck;
var
  From: integer;
  Reason: string;
begin
  ErrorMessage := '';
  if Version > Versions.Current then
  begin
    ErrorMessage := Format(rsFileVersionNewer, [Version]);
    Exit(vcNewer);
  end;
  if Version < 1 then
  begin
    ErrorMessage := Format(rsFileVersionInvalid, [Version]);
    Exit(vcInvalid);
  end;
  if Version = Versions.Current then
    Exit(vcCurrent);
  for From := Version to Versions.Current - 1 do
  begin
    if (From > Length(Versions.Steps)) or not Assigned(Versions.Steps[From - 1]) then
    begin
      ErrorMessage := Format(rsFileVersionNoStep, [From]);
      Exit(vcFailed);
    end;
    if not Versions.Steps[From - 1](Root, Reason) then
    begin
      ErrorMessage := Format(rsFileVersionStepFailed, [From + 1, Reason]);
      Exit(vcFailed);
    end;
    Root.Integers['version'] := From + 1;
  end;
  Result := vcUpgraded;
end;

end.
