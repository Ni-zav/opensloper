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

// Help → User Guide in the three apps: the offline copy of the site that the
// downloads ship, else the site on the web.
unit Sloper.UI.Help;

{$mode ObjFPC}{$H+}

interface

procedure ShowUserGuide;

resourcestring
  rsMenuUserGuide = '&User Guide';
  rsUserGuideFailed = 'Could not open the user guide in a web browser. It is at %s';

implementation

uses
  SysUtils, Dialogs, LCLIntf, Sloper.Core.AppPaths, Sloper.Core.Version;

procedure ShowUserGuide;
var
  Page: string;
  Opened: boolean;
begin
  Page := TAppPaths.UserGuideFile;
  if Page <> '' then
    Opened := OpenDocument(Page)
  else
  begin
    Page := USER_GUIDE_URL;
    Opened := OpenURL(Page);
  end;
  if not Opened then
    MessageDlg(Format(rsUserGuideFailed, [Page]), mtError, [mbOK], 0);
end;

end.
