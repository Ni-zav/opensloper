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

// opensloper-drape: places pattern pieces on a body in 3D, for draping in Blender.
program opensloper_drape;

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Sloper.Core.CodePage,
  Interfaces,
  Forms,
  Sloper.UI.HintPlacement,
  Sloper.Drape.MainForm;

  // The application icon, from opensloper_drape.ico
  {$R *.res}

var
  DrapeForm: TDrapeForm;

begin
  // The window is built in code, so it has no form file
  RequireDerivedFormResource := False;
  Application.Title := rsDrapeTitle;
  Application.Scaled := True;
  Application.Initialize;
  PlaceHintsAboveCursor;
  Application.CreateForm(TDrapeForm, DrapeForm);
  Application.Run;
end.
