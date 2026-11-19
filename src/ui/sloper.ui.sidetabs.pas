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

// The side panel's tabs, one open at a time: a column of icons down the
// left, and the open tab beside it under a title with its icon and name.
// Clicking the open tab's icon folds the panel down to the column, giving
// the canvas the room; clicking any icon opens it again.
unit Sloper.UI.SideTabs;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections, Controls, ExtCtrls, Graphics, LCLType, Sloper.Core.IconSet;

type
  TSideTabs = class;
  TSideTabSection = class;

  // A tab's icon in the column: click it, or press Enter or Space on it, to
  // open its tab; Up and Down move to the next icon
  TSideTabButton = class(TCustomControl)
  private
    FTabs: TSideTabs;
    FSection: TSideTabSection;
    FHot: boolean;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(ATabs: TSideTabs; ASection: TSideTabSection); reintroduce;
  end;

  // The column the icons stand in
  TSideTabStrip = class(TCustomControl)
  private
    FTabs: TSideTabs;
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(ATabs: TSideTabs); reintroduce;
  end;

  // The open tab's icon and name, across the top of it
  TSideTabTitle = class(TCustomControl)
  private
    FTabs: TSideTabs;
  protected
    procedure Paint; override;
  public
    constructor Create(ATabs: TSideTabs); reintroduce;
  end;

  TSideTabSection = class
  private
    FImages: TImageList;
    FImageSize: integer;
  public
    // Names the tab in settings, whatever its caption
    Key: string;
    Caption: string;
    Icon: TAppIcon;
    // Kept at the foot of the column rather than in order from the top
    AtFoot: boolean;
    // Drawn on the icon when above 0, such as how many problems there are
    Count: integer;
    Button: TSideTabButton;
    // What the tab shows, the parent for its panel
    Content: TPanel;
    Shown: boolean;
    destructor Destroy; override;
    // The icon Size pixels square, drawn again only when the size changes
    function Images(Size: integer): TImageList;
  end;

  TSideTabSectionList = specialize TObjectList<TSideTabSection>;

  TSideTabs = class(TCustomControl)
  private
    FSections: TSideTabSectionList;
    FActive: TSideTabSection;
    FStrip: TSideTabStrip;
    // The open tab and its title, beside the column
    FBody: TPanel;
    FTitle: TSideTabTitle;
    FCollapsed: boolean;
    // The width to open out to again after folding
    FOpenWidth: integer;
    FOnCollapsedChange: TNotifyEvent;
    function TitleHeight: integer;
    function StripWidth: integer;
    function SectionOf(Content: TWinControl): TSideTabSection;
    function InColumnOrder: TSideTabSectionList;
    procedure ArrangeButtons;
    procedure Activate(Section: TSideTabSection);
    procedure ButtonClicked(Section: TSideTabSection);
    procedure FocusNextButton(Section: TSideTabSection; Step: integer);
    procedure SetCollapsed(ACollapsed: boolean);
    function GetActiveContent: TWinControl;
    procedure SetActiveContent(Content: TWinControl);
    function GetActiveKey: string;
    procedure SetActiveKey(const AKey: string);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // A new tab, after the others or, AtFoot, at the foot of the column;
    // closed unless it is the first. The result is the parent for its panel.
    function AddSection(const AKey, ACaption: string; AIcon: TAppIcon; AtFoot: boolean = False): TWinControl;
    // Leaves a tab out, icon and all, or brings it back; the open tab, once
    // left out, gives way to the first shown one
    procedure SetSectionShown(Content: TWinControl; Shown: boolean);
    // A new name for a tab, such as one with a count in it
    procedure SetSectionCaption(Content: TWinControl; const ACaption: string);
    // A number drawn on a tab's icon, or none for 0
    procedure SetSectionCount(Content: TWinControl; ACount: integer);
    // The open tab, by what AddSection gave; setting it opens the panel out
    property ActiveContent: TWinControl read GetActiveContent write SetActiveContent;
    // The open tab by its key; a key no shown tab has changes nothing
    property ActiveKey: string read GetActiveKey write SetActiveKey;
    // Folded down to the column of icons
    property Collapsed: boolean read FCollapsed write SetCollapsed;
    // After folding or opening out, so the form can hide its splitter
    property OnCollapsedChange: TNotifyEvent read FOnCollapsedChange write FOnCollapsedChange;
  end;

implementation

uses
  Math, Sloper.UI.Icons, Sloper.UI.SideTabsLayout;

const
  // At 96 pixels per inch
  BUTTON_SIZE96 = 36;
  BUTTON_ICON96 = 20;
  TITLE_HEIGHT96 = 30;
  TITLE_ICON96 = 18;
  TITLE_PADDING96 = 8;
  // The open tab's mark down the column's edge
  OPEN_MARK96 = 3;
  // The count on an icon: its height, and room either side of the number
  BADGE_HEIGHT96 = 14;
  BADGE_PADDING96 = 3;
  BADGE_FONT_SIZE = 7;
  // How much of the highlight colour tints an open or pointed-at icon
  OPEN_TINT = 0.18;
  HOT_TINT = 0.10;

// From First towards Second by Amount, 0 to 1
function Blend(First, Second: TColor; Amount: double): TColor;
var
  From, Towards: longint;
begin
  From := ColorToRGB(First);
  Towards := ColorToRGB(Second);
  Result := RGBToColor(Round(Red(From) + (Red(Towards) - Red(From)) * Amount), Round(Green(From) + (Green(Towards) - Green(From)) * Amount),
    Round(Blue(From) + (Blue(Towards) - Blue(From)) * Amount));
end;

{ TSideTabSection }

destructor TSideTabSection.Destroy;
begin
  FreeAndNil(FImages);
  inherited Destroy;
end;

function TSideTabSection.Images(Size: integer): TImageList;
begin
  if not Assigned(FImages) or (FImageSize <> Size) then
  begin
    FreeAndNil(FImages);
    FImages := CreateIconImages(nil, Size, clBtnText, [Icon]);
    FImageSize := Size;
  end;
  Result := FImages;
end;

{ TSideTabButton }

constructor TSideTabButton.Create(ATabs: TSideTabs; ASection: TSideTabSection);
begin
  inherited Create(ATabs);
  FTabs := ATabs;
  FSection := ASection;
  TabStop := True;
  ShowHint := True;
  ControlStyle := ControlStyle + [csOpaque];
end;

// Tinted when open or pointed at, the open one marked down its edge, with
// the count in a small badge at the top right
procedure TSideTabButton.Paint;
var
  Area, Badge: TRect;
  Open: boolean;
  IconSize, BadgeWidth: integer;
  Number: string;
begin
  Area := ClientRect;
  Open := (FSection = FTabs.FActive) and not FTabs.Collapsed;
  if Open then
    Canvas.Brush.Color := Blend(clBtnFace, clHighlight, OPEN_TINT)
  else if FHot then
    Canvas.Brush.Color := Blend(clBtnFace, clHighlight, HOT_TINT)
  else
    Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(Area);
  if Open then
  begin
    Canvas.Brush.Color := clHighlight;
    Canvas.FillRect(Rect(Area.Left, Area.Top, Area.Left + Scale96ToForm(OPEN_MARK96), Area.Bottom));
  end;
  IconSize := Scale96ToForm(BUTTON_ICON96);
  FSection.Images(IconSize).Draw(Canvas, (Area.Width - IconSize) div 2, (Area.Height - IconSize) div 2, 0);
  if FSection.Count > 0 then
  begin
    Number := IntToStr(FSection.Count);
    Canvas.Font := Font;
    Canvas.Font.Size := BADGE_FONT_SIZE;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := clHighlightText;
    BadgeWidth := Max(Scale96ToForm(BADGE_HEIGHT96), Canvas.TextWidth(Number) + 2 * Scale96ToForm(BADGE_PADDING96));
    Badge := Rect(Area.Right - BadgeWidth - 1, Area.Top + 1, Area.Right - 1, Area.Top + 1 + Scale96ToForm(BADGE_HEIGHT96));
    Canvas.Brush.Color := clHighlight;
    Canvas.Pen.Color := clHighlight;
    Canvas.RoundRect(Badge, Badge.Height, Badge.Height);
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(Badge.Left + (Badge.Width - Canvas.TextWidth(Number)) div 2, Badge.Top + (Badge.Height - Canvas.TextHeight(Number)) div 2, Number);
    Canvas.Brush.Style := bsSolid;
  end;
  if Focused then
    Canvas.DrawFocusRect(Rect(Area.Left + 2, Area.Top + 2, Area.Right - 2, Area.Bottom - 2));
end;

// A click opens the tab without taking the keyboard from the canvas
procedure TSideTabButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    FTabs.ButtonClicked(FSection);
end;

procedure TSideTabButton.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TSideTabButton.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  Invalidate;
end;

procedure TSideTabButton.KeyDown(var Key: word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_RETURN, VK_SPACE:
    begin
      FTabs.ButtonClicked(FSection);
      Key := 0;
    end;
    VK_UP:
    begin
      FTabs.FocusNextButton(FSection, -1);
      Key := 0;
    end;
    VK_DOWN:
    begin
      FTabs.FocusNextButton(FSection, 1);
      Key := 0;
    end;
  end;
end;

procedure TSideTabButton.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TSideTabButton.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

{ TSideTabStrip }

constructor TSideTabStrip.Create(ATabs: TSideTabs);
begin
  inherited Create(ATabs);
  FTabs := ATabs;
  ControlStyle := ControlStyle + [csOpaque];
end;

// A line down the side towards the open tab
procedure TSideTabStrip.Paint;
begin
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := clBtnShadow;
  Canvas.Line(ClientWidth - 1, 0, ClientWidth - 1, ClientHeight);
end;

procedure TSideTabStrip.Resize;
begin
  inherited Resize;
  FTabs.ArrangeButtons;
end;

{ TSideTabTitle }

constructor TSideTabTitle.Create(ATabs: TSideTabs);
begin
  inherited Create(ATabs);
  FTabs := ATabs;
  ControlStyle := ControlStyle + [csOpaque];
end;

procedure TSideTabTitle.Paint;
var
  Area: TRect;
  Padding, IconSize, Middle: integer;
  Section: TSideTabSection;
begin
  Area := ClientRect;
  Canvas.Brush.Color := Blend(clBtnFace, clHighlight, OPEN_TINT);
  Canvas.FillRect(Area);
  Canvas.Pen.Color := clBtnShadow;
  Canvas.Line(Area.Left, Area.Bottom - 1, Area.Right, Area.Bottom - 1);
  Section := FTabs.FActive;
  if not Assigned(Section) then
    Exit;
  Padding := Scale96ToForm(TITLE_PADDING96);
  IconSize := Scale96ToForm(TITLE_ICON96);
  Middle := (Area.Top + Area.Bottom) div 2;
  Section.Images(IconSize).Draw(Canvas, Padding, Middle - IconSize div 2, 0);
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  Canvas.Font.Color := clBtnText;
  Canvas.Font.Style := [fsBold];
  Canvas.TextOut(2 * Padding + IconSize, Middle - Canvas.TextHeight(Section.Caption) div 2, Section.Caption);
  Canvas.Brush.Style := bsSolid;
end;

{ TSideTabs }

constructor TSideTabs.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSections := TSideTabSectionList.Create(True);
  ControlStyle := ControlStyle + [csOpaque];
  FStrip := TSideTabStrip.Create(Self);
  FStrip.Align := alLeft;
  FStrip.Parent := Self;
  FBody := TPanel.Create(Self);
  FBody.BevelOuter := bvNone;
  FBody.Caption := '';
  FBody.Align := alClient;
  FBody.Parent := Self;
  FTitle := TSideTabTitle.Create(Self);
  FTitle.Align := alTop;
  FTitle.Parent := FBody;
end;

destructor TSideTabs.Destroy;
begin
  inherited Destroy;
  FreeAndNil(FSections);
end;

// Tall enough for the name in the widgetset's font
function TSideTabs.TitleHeight: integer;
begin
  Result := Scale96ToForm(TITLE_HEIGHT96);
  if HandleAllocated then
  begin
    Canvas.Font := Font;
    Result := Max(Result, Canvas.TextHeight('Ag') + Scale96ToForm(TITLE_PADDING96));
  end;
end;

function TSideTabs.StripWidth: integer;
begin
  Result := Scale96ToForm(BUTTON_SIZE96);
end;

function TSideTabs.AddSection(const AKey, ACaption: string; AIcon: TAppIcon; AtFoot: boolean): TWinControl;
var
  Section: TSideTabSection;
begin
  Section := TSideTabSection.Create;
  FSections.Add(Section);
  Section.Key := AKey;
  Section.Caption := ACaption;
  Section.Icon := AIcon;
  Section.AtFoot := AtFoot;
  Section.Shown := True;
  Section.Button := TSideTabButton.Create(Self, Section);
  Section.Button.Hint := ACaption;
  Section.Button.Parent := FStrip;
  Section.Content := TPanel.Create(Self);
  Section.Content.BevelOuter := bvNone;
  Section.Content.Caption := '';
  // Lighter than the column, as a tab page is
  Section.Content.Color := clWindow;
  Section.Content.Align := alClient;
  Section.Content.Visible := False;
  Section.Content.Parent := FBody;
  FStrip.Width := StripWidth;
  FTitle.Height := TitleHeight;
  if not Assigned(FActive) then
    Activate(Section)
  else
    ArrangeButtons;
  Result := Section.Content;
end;

function TSideTabs.SectionOf(Content: TWinControl): TSideTabSection;
begin
  for Result in FSections do
    if Result.Content = Content then
      Exit;
  Result := nil;
end;

// The shown tabs as the column has them: in order from the top, then those
// at the foot. The list does not own them.
function TSideTabs.InColumnOrder: TSideTabSectionList;
var
  Section: TSideTabSection;
  AtFoot: boolean;
begin
  Result := TSideTabSectionList.Create(False);
  for AtFoot := False to True do
    for Section in FSections do
      if Section.Shown and (Section.AtFoot = AtFoot) then
        Result.Add(Section);
end;

procedure TSideTabs.ArrangeButtons;
var
  Column: TSideTabSectionList;
  Tops: TButtonTops;
  Size, FootCount, Index: integer;
  Section: TSideTabSection;
begin
  Column := InColumnOrder;
  try
    FootCount := 0;
    for Section in Column do
      if Section.AtFoot then
        Inc(FootCount);
    Size := StripWidth;
    Tops := PlaceTabButtons(Column.Count - FootCount, FootCount, Size, FStrip.ClientHeight);
    for Index := 0 to Column.Count - 1 do
      // Short of the column's dividing line
      Column[Index].Button.SetBounds(0, Tops[Index], Size - 1, Size);
  finally
    FreeAndNil(Column);
  end;
end;

procedure TSideTabs.SetSectionShown(Content: TWinControl; Shown: boolean);
var
  Section, First: TSideTabSection;
begin
  Section := SectionOf(Content);
  if not Assigned(Section) or (Section.Shown = Shown) then
    Exit;
  Section.Shown := Shown;
  Section.Button.Visible := Shown;
  if Section = FActive then
  begin
    FActive := nil;
    for First in FSections do
      if First.Shown then
      begin
        Activate(First);
        Break;
      end;
    Section.Content.Visible := False;
    FTitle.Invalidate;
  end;
  ArrangeButtons;
end;

procedure TSideTabs.SetSectionCaption(Content: TWinControl; const ACaption: string);
var
  Section: TSideTabSection;
begin
  Section := SectionOf(Content);
  if not Assigned(Section) or (Section.Caption = ACaption) then
    Exit;
  Section.Caption := ACaption;
  Section.Button.Hint := ACaption;
  if Section = FActive then
    FTitle.Invalidate;
end;

procedure TSideTabs.SetSectionCount(Content: TWinControl; ACount: integer);
var
  Section: TSideTabSection;
begin
  Section := SectionOf(Content);
  if not Assigned(Section) or (Section.Count = ACount) then
    Exit;
  Section.Count := ACount;
  Section.Button.Invalidate;
end;

function TSideTabs.GetActiveContent: TWinControl;
begin
  Result := nil;
  if Assigned(FActive) then
    Result := FActive.Content;
end;

procedure TSideTabs.SetActiveContent(Content: TWinControl);
var
  Section: TSideTabSection;
begin
  Section := SectionOf(Content);
  if Assigned(Section) and Section.Shown then
    Activate(Section);
end;

function TSideTabs.GetActiveKey: string;
begin
  Result := '';
  if Assigned(FActive) then
    Result := FActive.Key;
end;

procedure TSideTabs.SetActiveKey(const AKey: string);
var
  Section: TSideTabSection;
begin
  for Section in FSections do
    if (Section.Key = AKey) and Section.Shown then
    begin
      Activate(Section);
      Exit;
    end;
end;

// The new tab is shown before the old one is hidden, so the panel never
// stands empty, and a field being typed in the old one commits as it goes.
// Opening a tab opens out a folded panel.
procedure TSideTabs.Activate(Section: TSideTabSection);
var
  Other: TSideTabSection;
begin
  FActive := Section;
  DisableAlign;
  try
    Section.Content.Visible := True;
    for Other in FSections do
    begin
      if Other <> Section then
        Other.Content.Visible := False;
      Other.Button.Invalidate;
    end;
  finally
    EnableAlign;
  end;
  FTitle.Invalidate;
  SetCollapsed(False);
end;

// The open tab's icon folds the panel, or opens it out again
procedure TSideTabs.ButtonClicked(Section: TSideTabSection);
begin
  if Section = FActive then
    SetCollapsed(not FCollapsed)
  else
    Activate(Section);
end;

procedure TSideTabs.FocusNextButton(Section: TSideTabSection; Step: integer);
var
  Column: TSideTabSectionList;
  Index: integer;
begin
  Column := InColumnOrder;
  try
    Index := Column.IndexOf(Section) + Step;
    if (Index >= 0) and (Index < Column.Count) and Column[Index].Button.CanFocus then
      Column[Index].Button.SetFocus;
  finally
    FreeAndNil(Column);
  end;
end;

procedure TSideTabs.SetCollapsed(ACollapsed: boolean);
var
  Section: TSideTabSection;
begin
  if FCollapsed = ACollapsed then
    Exit;
  FCollapsed := ACollapsed;
  DisableAlign;
  try
    if ACollapsed then
    begin
      FOpenWidth := Width;
      Width := StripWidth;
    end
    else if FOpenWidth > StripWidth then
      Width := FOpenWidth;
    FBody.Visible := not ACollapsed;
  finally
    EnableAlign;
  end;
  for Section in FSections do
    Section.Button.Invalidate;
  if Assigned(FOnCollapsedChange) then
    FOnCollapsedChange(Self);
end;

procedure TSideTabs.Paint;
begin
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(ClientRect);
end;

end.
