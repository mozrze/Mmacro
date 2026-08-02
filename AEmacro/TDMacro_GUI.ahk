#SingleInstance Force
#NoEnv
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Screen
CoordMode, Pixel, Screen
DetectHiddenWindows, On
SendMode, Input

; ===================== НАСТРОЙКИ =====================
WinTitle := "ahk_exe RobloxPlayerBeta.exe"
GameAreaW := 1280
GameAreaH := 720
SidebarW  := 320

MapsDir := A_ScriptDir . "\maps"
ImagesDir := A_ScriptDir . "\images"
ConfigFile := A_ScriptDir . "\config.ini"
SettingsFile := A_ScriptDir . "\ahk\settings.ini"
PresetsIni := A_ScriptDir . "\ahk\presets.ini"
TempShot := A_ScriptDir . "\_preview.bmp"
IfNotExist, %MapsDir%
    FileCreateDir, %MapsDir%
IfNotExist, %ImagesDir%
    FileCreateDir, %ImagesDir%

MapList := ["Flower Forest", "Fairy King Forest", "King's Tomb", "Rose Kingdom", "School Grounds"]
MapCoords := {}   ; MapCoords[map] := [{num,x,y}, ...]

; Координаты кнопок (калибруются кликом по скриншоту)
UpgradeX := 0
UpgradeY := 0
AutoX := 0
AutoY := 0
StartGameX := 0
StartGameY := 0
RepeatStageX := 0
RepeatStageY := 0

; ---- настройки задержек (из ahk/settings.ini) ----
ClickDelay := 80
SlotClickDelay := 250
UpgradeClickDelay := 150
AutoClickDelay := 120
UnitSleepDelay := 200
StartGameDelay := 500
ImgVariation := 30
StartGameColor := 0x4ECD0C
StartGameColorVar := 30
StartGameCenterX := 640
StartGameCenterY := 500
StartGameRadius := 200

Running := false
Embedded := false
GameHwnd := 0
OrigStyle := 0
OrigExStyle := 0
OrigParent := 0
AutoNextStage := false

; ---- состояние окна разметки/калибровки ----
MarkMode := ""
MarkList := []
MarkGuiHwnd := 0
CalibGuiHwnd := 0
; =======================================================

TotalW := GameAreaW + SidebarW
TotalH := GameAreaH + 40

LoadConfig()
LoadSettings()
LoadAllMapCoords()

; ===================== GUI (тёмная тема) =====================
Gui, +HwndMainGuiHwnd
Gui, Color, 0x1E1E1E, 0x252526
Gui, Font, s10 cE0E0E0, Segoe UI

Gui, Add, Text, x0 y0 w%GameAreaW% h%GameAreaH% vGameArea 0x201 Border BackgroundBlack,
Gui, Add, Text, x0 y%GameAreaH% w%GameAreaW% h40 c808080 Center 0x201, Область встраивания Roblox — нажми "Встроить" справа

SbX := GameAreaW + 12
SbX2 := SbX + 143

Gui, Font, s12 cFFFFFF Bold, Segoe UI
Gui, Add, Text, x%SbX% y12 w%SidebarW%, TD MACRO

Gui, Font, s9 cE0E0E0 Norm, Segoe UI
Gui, Add, Text, x%SbX% y44 w280 c00CCFF, ОКНО ИГРЫ
Gui, Add, Button, x%SbX% y64 w280 h30 gBtnEmbed vEmbedBtn, Встроить Roblox сюда
Gui, Add, Text, x%SbX% y100 w280 h20 vWindowStatus c808080, Статус: не проверено

Gui, Add, Text, x%SbX% y128 w280 c00CCFF, КАРТА И РАЗМЕТКА
Gui, Add, DropDownList, x%SbX% y148 w280 vSelectedMapCtl gMapChanged, % JoinArr(MapList, "|")
Gui, Add, Button, x%SbX% y184 w280 h26 gBtnCaptureMap, Сделать снимок карты
Gui, Add, Button, x%SbX% y214 w280 h26 gBtnMarkSlots, Разметить слоты карты
   Gui, Add, Button, x%SbX% y244 w280 h26 gBtnClearMap, Очистить разметку карты
   Gui, Add, Text, x%SbX% y274 w280 h16 vOffsetStatus c808080, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ") Repeat(" RepeatStageX "," RepeatStageY ")"

Gui, Add, Text, x%SbX% y296 w280 c00CCFF, ФАРМ
Gui, Add, Button, x%SbX% y316 w280 h34 gBtnStartStop vStartStopBtn, Старт (F9)
Gui, Add, CheckBox, x%SbX% y356 w280 h20 vAutoNextStage cE0E0E0, Авто-следующая волна
Gui, Add, Text, x%SbX% y382 w280 h20 vFarmStatus c808080, Статус: остановлен

Gui, Add, Text, x%SbX% y412 w280 c00CCFF, ЛОГ
Gui, Add, Edit, x%SbX% y432 w280 h230 vLogBox ReadOnly -WantReturn Background151515 cB0B0B0,
Gui, Add, Button, x%SbX% y696 w137 h24 gBtnSettings, Настройки
Gui, Add, Button, x%SbX2% y696 w137 h24 gBtnOpenCalibration, Калибровка

Gui, Show, w%TotalW% h%TotalH%, TD Macro Control
return

; ===================== ЛОГ =====================
AddLog(msg) {
    Gui, 1:Default
    GuiControlGet, cur,, LogBox
    FormatTime, ts,, HH:mm:ss
    new := "[" ts "] " msg "`r`n" cur
    GuiControl,, LogBox, %new%
}

; ===================== КОНФИГ (координаты кнопок) =====================
LoadConfig() {
    global ConfigFile, UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    if !FileExist(ConfigFile)
        return
    IniRead, v, %ConfigFile%, Buttons, UpgradeX, %UpgradeX%
    UpgradeX := v
    IniRead, v, %ConfigFile%, Buttons, UpgradeY, %UpgradeY%
    UpgradeY := v
    IniRead, v, %ConfigFile%, Buttons, AutoX, %AutoX%
    AutoX := v
    IniRead, v, %ConfigFile%, Buttons, AutoY, %AutoY%
    AutoY := v
    IniRead, v, %ConfigFile%, Buttons, StartGameX, %StartGameX%
    StartGameX := v
    IniRead, v, %ConfigFile%, Buttons, StartGameY, %StartGameY%
    StartGameY := v
    IniRead, v, %ConfigFile%, Buttons, RepeatStageX, %RepeatStageX%
    RepeatStageX := v
    IniRead, v, %ConfigFile%, Buttons, RepeatStageY, %RepeatStageY%
    RepeatStageY := v
}

SaveConfig() {
    global ConfigFile, UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    IniWrite, %UpgradeX%,  %ConfigFile%, Buttons, UpgradeX
    IniWrite, %UpgradeY%,  %ConfigFile%, Buttons, UpgradeY
    IniWrite, %AutoX%,     %ConfigFile%, Buttons, AutoX
    IniWrite, %AutoY%,     %ConfigFile%, Buttons, AutoY
    IniWrite, %StartGameX%, %ConfigFile%, Buttons, StartGameX
    IniWrite, %StartGameY%, %ConfigFile%, Buttons, StartGameY
    IniWrite, %RepeatStageX%, %ConfigFile%, Buttons, RepeatStageX
    IniWrite, %RepeatStageY%, %ConfigFile%, Buttons, RepeatStageY
}

; ===================== НАСТРОЙКИ (ahk/settings.ini) =====================
LoadSettings() {
    global SettingsFile, ClickDelay, SlotClickDelay, UpgradeClickDelay
    global AutoClickDelay, UnitSleepDelay, StartGameDelay, ImgVariation
    global StartGameColor, StartGameColorVar, StartGameCenterX, StartGameCenterY, StartGameRadius
    if !FileExist(SettingsFile)
        return
    IniRead, v, %SettingsFile%, Delays, ClickDelay, %ClickDelay%
    ClickDelay := v
    IniRead, v, %SettingsFile%, Delays, SlotClickDelay, %SlotClickDelay%
    SlotClickDelay := v
    IniRead, v, %SettingsFile%, Delays, UpgradeClickDelay, %UpgradeClickDelay%
    UpgradeClickDelay := v
    IniRead, v, %SettingsFile%, Delays, AutoClickDelay, %AutoClickDelay%
    AutoClickDelay := v
    IniRead, v, %SettingsFile%, Delays, UnitSleepDelay, %UnitSleepDelay%
    UnitSleepDelay := v
    IniRead, v, %SettingsFile%, Delays, StartGameDelay, %StartGameDelay%
    StartGameDelay := v
    IniRead, v, %SettingsFile%, ImageSearch, Variation, %ImgVariation%
    ImgVariation := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameColor, %StartGameColor%
    StartGameColor := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameColorVar, %StartGameColorVar%
    StartGameColorVar := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameCenterX, %StartGameCenterX%
    StartGameCenterX := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameCenterY, %StartGameCenterY%
    StartGameCenterY := v
    IniRead, v, %SettingsFile%, PixelSearch, StartGameRadius, %StartGameRadius%
    StartGameRadius := v
}

SaveSettings() {
    global SettingsFile, ClickDelay, SlotClickDelay, UpgradeClickDelay
    global AutoClickDelay, UnitSleepDelay, StartGameDelay, ImgVariation
    global StartGameColor, StartGameColorVar, StartGameCenterX, StartGameCenterY, StartGameRadius
    IniWrite, %ClickDelay%, %SettingsFile%, Delays, ClickDelay
    IniWrite, %SlotClickDelay%, %SettingsFile%, Delays, SlotClickDelay
    IniWrite, %UpgradeClickDelay%, %SettingsFile%, Delays, UpgradeClickDelay
    IniWrite, %AutoClickDelay%, %SettingsFile%, Delays, AutoClickDelay
    IniWrite, %UnitSleepDelay%, %SettingsFile%, Delays, UnitSleepDelay
    IniWrite, %StartGameDelay%, %SettingsFile%, Delays, StartGameDelay
    IniWrite, %ImgVariation%, %SettingsFile%, ImageSearch, Variation
    IniWrite, %StartGameColor%, %SettingsFile%, PixelSearch, StartGameColor
    IniWrite, %StartGameColorVar%, %SettingsFile%, PixelSearch, StartGameColorVar
    IniWrite, %StartGameCenterX%, %SettingsFile%, PixelSearch, StartGameCenterX
    IniWrite, %StartGameCenterY%, %SettingsFile%, PixelSearch, StartGameCenterY
    IniWrite, %StartGameRadius%, %SettingsFile%, PixelSearch, StartGameRadius
}

; ===================== КООРДИНАТЫ КАРТ (слоты) =====================
SafeMapName(name) {
    n := name
    StringReplace, n, n, %A_Space%, _, All
    StringReplace, n, n, ', , All
    return n
}

MapSlotsFile(mapName) {
    global MapsDir
    return MapsDir . "\" . SafeMapName(mapName) . "_slots.ini"
}

LoadAllMapCoords() {
    global MapList
    for i, m in MapList
        LoadMapCoordsOne(m)
}

LoadMapCoordsOne(mapName) {
    global MapCoords
    f := MapSlotsFile(mapName)
    if !FileExist(f) {
        MapCoords.Delete(mapName)
        return
    }
    IniRead, cnt, %f%, Meta, Count, 0
    list := []
    Loop, %cnt% {
        IniRead, line, %f%, Slots, %A_Index%, ""
        if (line = "")
            continue
        StringSplit, p, line, `,
        list.Push({num: p1, x: p2, y: p3})
    }
    if (list.Length() > 0)
        MapCoords[mapName] := list
    else
        MapCoords.Delete(mapName)
}

SaveMapSlots(mapName, list) {
    f := MapSlotsFile(mapName)
    if FileExist(f)
        FileDelete, %f%
    IniWrite, % list.Length(), %f%, Meta, Count
    for i, s in list {
        line := s.num . "," . s.x . "," . s.y
        IniWrite, %line%, %f%, Slots, %i%
    }
}

; ===================== ФУНКЦИИ ОКНА / ВСТРАИВАНИЯ =====================
ToScreen(x, y) {
    global MainGuiHwnd, TS_X, TS_Y
    if (!MainGuiHwnd || !DllCall("IsWindow", "ptr", MainGuiHwnd)) {
        AddLog("ToScreen: MainGuiHwnd некорректен (" MainGuiHwnd ")")
        TS_X := x
        TS_Y := y
        return
    }
    VarSetCapacity(pt, 8, 0)
    NumPut(x, pt, 0, "Int")
    NumPut(y, pt, 4, "Int")
    DllCall("ClientToScreen", "ptr", MainGuiHwnd, "ptr", &pt)
    TS_X := NumGet(pt, 0, "Int")
    TS_Y := NumGet(pt, 4, "Int")
}

GetClientSize(hwnd, ByRef cw, ByRef ch) {
    VarSetCapacity(rect, 16, 0)
    DllCall("GetClientRect", "ptr", hwnd, "ptr", &rect)
    cw := NumGet(rect, 8, "Int")
    ch := NumGet(rect, 12, "Int")
}

; ===================== ПОИСК ИЗОБРАЖЕНИЙ (fallback) =====================
FindGameButton(imageFile, ByRef foundX, ByRef foundY) {
    global MainGuiHwnd, GameAreaW, GameAreaH, ImgVariation
    if (!MainGuiHwnd || !DllCall("IsWindow", "ptr", MainGuiHwnd))
        return false
    VarSetCapacity(pt, 8, 0)
    NumPut(0, pt, 0, "Int")
    NumPut(0, pt, 4, "Int")
    DllCall("ClientToScreen", "ptr", MainGuiHwnd, "ptr", &pt)
    sx := NumGet(pt, 0, "Int")
    sy := NumGet(pt, 4, "Int")
    ex := sx + GameAreaW
    ey := sy + GameAreaH
    ImageSearch, foundX, foundY, sx, sy, ex, ey, *%ImgVariation% %imageFile%
    if (ErrorLevel = 0)
        return true
    ImageSearch, foundX, foundY, sx, sy, ex, ey, *100 %imageFile%
    if (ErrorLevel = 0)
        return true
    return false
}

FindGameButtonByColor(color, variation, ByRef foundX, ByRef foundY) {
    global MainGuiHwnd, StartGameCenterX, StartGameCenterY, StartGameRadius
    if (!MainGuiHwnd || !DllCall("IsWindow", "ptr", MainGuiHwnd))
        return false
    VarSetCapacity(pt, 8, 0)
    NumPut(StartGameCenterX, pt, 0, "Int")
    NumPut(StartGameCenterY, pt, 4, "Int")
    DllCall("ClientToScreen", "ptr", MainGuiHwnd, "ptr", &pt)
    cx := NumGet(pt, 0, "Int")
    cy := NumGet(pt, 4, "Int")
    sx := cx - StartGameRadius
    sy := cy - StartGameRadius
    ex := cx + StartGameRadius
    ey := cy + StartGameRadius
    PixelSearch, foundX, foundY, sx, sy, ex, ey, %color%, %variation%, Fast RGB
    return (ErrorLevel = 0)
}

ClickGameButton(imageFile, delayAfter := 0) {
    global ImagesDir, StartGameColor, StartGameColorVar
    full := ImagesDir . "\" . imageFile
    if FileExist(full) {
        if (FindGameButton(full, btnX, btnY)) {
            MouseMove, % btnX, % btnY, 0
            Click
            if (delayAfter > 0)
                Sleep, %delayAfter%
            return true
        }
    }
    if (StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
        if (FindGameButtonByColor(StartGameColor, StartGameColorVar, btnX, btnY)) {
            MouseMove, % btnX, % btnY, 0
            Click
            if (delayAfter > 0)
                Sleep, %delayAfter%
            return true
        }
    }
    return false
}

BtnEmbed:
    Gui, Submit, NoHide
    if (Embedded) {
        UnembedGameWindow()
        GuiControl,, EmbedBtn, Встроить Roblox сюда
        Embedded := false
        return
    }
    if !WinExist(WinTitle) {
        GuiControl,, WindowStatus, Статус: игра не найдена
        AddLog("Ошибка встраивания: окно Roblox не найдено")
        return
    }
    GameHwnd := WinExist(WinTitle)
    WinGet, OrigStyle, Style, ahk_id %GameHwnd%
    WinGet, OrigExStyle, ExStyle, ahk_id %GameHwnd%
    OrigParent := DllCall("GetParent", "ptr", GameHwnd, "ptr")
    GuiControlGet, ContainerHwnd, Hwnd, GameArea
    WinSet, Style, -0xC00000, ahk_id %GameHwnd%
    WinSet, Style, -0x800000, ahk_id %GameHwnd%
    WinSet, Style, -0x40000,  ahk_id %GameHwnd%
    DllCall("SetParent", "ptr", GameHwnd, "ptr", ContainerHwnd)
    WinMove, ahk_id %GameHwnd%,, 0, 0, %GameAreaW%, %GameAreaH%
    Sleep, 150
    GetClientSize(GameHwnd, RealW, RealH)
    Embedded := true
    GuiControl,, EmbedBtn, Вернуть Roblox обратно
    GuiControl,, WindowStatus, % "Статус: встроено, размер " RealW "x" RealH
    AddLog("Roblox встроен, зафиксированный размер игры: " RealW "x" RealH)
return

UnembedGameWindow() {
    global GameHwnd, OrigStyle, OrigExStyle, OrigParent
    if (!GameHwnd || !WinExist("ahk_id " . GameHwnd))
        return
    DllCall("SetParent", "ptr", GameHwnd, "ptr", OrigParent)
    WinSet, Style, %OrigStyle%, ahk_id %GameHwnd%
    WinSet, ExStyle, %OrigExStyle%, ahk_id %GameHwnd%
    WinMove, ahk_id %GameHwnd%,, 100, 100, 1280, 720
    GuiControl,, WindowStatus, Статус: возвращено в обычный режим
    AddLog("Roblox возвращён в обычное окно")
}

; ===================== ВЫБОР КАРТЫ =====================
JoinArr(arr, sep) {
    out := ""
    for i, v in arr
        out .= (i = 1 ? "" : sep) . v
    return out
}

MapChanged:
    Gui, Submit, NoHide
    if (MapCoords.HasKey(SelectedMapCtl))
        AddLog("Карта """ SelectedMapCtl """: " MapCoords[SelectedMapCtl].Length() " слот(ов) размечено")
    else
        AddLog("Карта """ SelectedMapCtl """ ещё НЕ размечена")
return

BtnClearMap:
    Gui, Submit, NoHide
    if (SelectedMapCtl = "") {
        AddLog("Сначала выбери карту")
        return
    }
    f := MapSlotsFile(SelectedMapCtl)
    if FileExist(f)
        FileDelete, %f%
    MapCoords.Delete(SelectedMapCtl)
    AddLog("Разметка карты """ SelectedMapCtl """ очищена")
return

; ===================== СНИМОК КАРТЫ =====================
BtnCaptureMap:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureGameArea(TempShot)
    AddLog("Снимок сделан, открываю превью...")
    ShowSnapshotPreview()
return

ShowSnapshotPreview() {
    global TempShot
    Gui, Snap:New, , Снимок карты — превью
    Gui, Snap:Color, 0x1E1E1E
    Gui, Snap:Font, s10 cE0E0E0, Segoe UI
    Gui, Snap:Add, Picture, x10 y10 w640 h360, %TempShot%
    Gui, Snap:Add, Button, x10 y380 w310 h34 gSnapConfirm, Подтвердить снимок
    Gui, Snap:Add, Button, x340 y380 w310 h34 gSnapCancel, Отмена
    Gui, Snap:Show, w660 h424, Снимок карты — превью
}

SnapConfirm:
    Gui, Snap:Destroy
    InputBox, ShotName, Название снимка, Введи имя для этого снимка карты (например: FlowerForest_start), , 300, 140
    if (ErrorLevel) {
        AddLog("Сохранение снимка отменено")
        return
    }
    if (ShotName = "") {
        AddLog("Имя не указано, снимок не сохранён")
        return
    }
    FinalPath := MapsDir . "\" . ShotName . ".bmp"
    FileCopy, %TempShot%, %FinalPath%, 1
    AddLog("Снимок карты сохранён: maps\" . ShotName . ".bmp")
return

SnapCancel:
    Gui, Snap:Destroy
    AddLog("Снимок отклонён, не сохранён")
return

; ===================== СКРИНШОТ ОБЛАСТИ ИГРЫ =====================
CaptureGameArea(filepath) {
    global MainGuiHwnd
    GuiControlGet, AreaPos, Pos, GameArea
    VarSetCapacity(pt, 8, 0)
    NumPut(AreaPosX, pt, 0, "Int")
    NumPut(AreaPosY, pt, 4, "Int")
    DllCall("ClientToScreen", "ptr", MainGuiHwnd, "ptr", &pt)
    ScreenX := NumGet(pt, 0, "Int")
    ScreenY := NumGet(pt, 4, "Int")
    CaptureScreenshot(ScreenX, ScreenY, AreaPosW, AreaPosH, filepath)
}

CaptureScreenshot(x, y, w, h, filepath) {
    hDesktopDC := DllCall("GetDC", "ptr", 0, "ptr")
    hCaptureDC := DllCall("CreateCompatibleDC", "ptr", hDesktopDC, "ptr")
    hBitmap := DllCall("CreateCompatibleBitmap", "ptr", hDesktopDC, "int", w, "int", h, "ptr")
    hOld := DllCall("SelectObject", "ptr", hCaptureDC, "ptr", hBitmap, "ptr")
    DllCall("BitBlt", "ptr", hCaptureDC, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", hDesktopDC, "int", x, "int", y, "uint", 0x00CC0020)
    DllCall("SelectObject", "ptr", hCaptureDC, "ptr", hOld)
    DllCall("DeleteDC", "ptr", hCaptureDC)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hDesktopDC)
    SaveHBITMAPToBMP(hBitmap, filepath, w, h)
    DllCall("DeleteObject", "ptr", hBitmap)
}

SaveHBITMAPToBMP(hBitmap, filepath, w, h) {
    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    VarSetCapacity(bi, 40, 0)
    NumPut(40, bi, 0, "UInt")
    NumPut(w, bi, 4, "Int")
    NumPut(-h, bi, 8, "Int")
    NumPut(1, bi, 12, "UShort")
    NumPut(24, bi, 14, "UShort")
    NumPut(0, bi, 16, "UInt")
    stride := ((w*3+3)//4)*4
    imageSize := stride*h
    VarSetCapacity(pixels, imageSize, 0)
    DllCall("GetDIBits", "ptr", hdc, "ptr", hBitmap, "uint", 0, "uint", h
        , "ptr", &pixels, "ptr", &bi, "uint", 0)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    VarSetCapacity(fh, 14, 0)
    NumPut(0x4D42, fh, 0, "UShort")
    fileSize := 14 + 40 + imageSize
    NumPut(fileSize, fh, 2, "UInt")
    NumPut(14 + 40, fh, 10, "UInt")
    if FileExist(filepath)
        FileDelete, %filepath%
    file := FileOpen(filepath, "w")
    file.RawWrite(&fh, 14)
    file.RawWrite(&bi, 40)
    file.RawWrite(&pixels, imageSize)
    file.Close()
}

; ===================== РАЗМЕТКА СЛОТОВ КАРТЫ =====================
BtnMarkSlots:
    Gui, Submit, NoHide
    if (SelectedMapCtl = "") {
        AddLog("Сначала выбери карту в списке")
        return
    }
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureGameArea(TempShot)
    MarkMode := "slots"
    MarkList := []
    OpenMarkGui("Кликай по местам постановки юнитов (номер юнита спросит после каждого клика)")
return

; ===================== КАЛИБРОВКА UPGRADE =====================
BtnCalibrateUpgrade:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureGameArea(TempShot)
    MarkMode := "abs_upgrade"
    OpenMarkGui("Кликни на кнопку Upgrade")
return

; ===================== КАЛИБРОВКА AUTOUPGRADE =====================
BtnCalibrateAuto:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureGameArea(TempShot)
    MarkMode := "abs_auto"
    OpenMarkGui("Кликни на кнопку AutoUpgrade")
return

; ===================== КАЛИБРОВКА START GAME =====================
BtnCalibrateStartGame:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureGameArea(TempShot)
    MarkMode := "abs_startgame"
    OpenMarkGui("Кликни на кнопку Start Game")
return

; ===================== КАЛИБРОВКА REPEAT STAGE =====================
BtnCalibrateRepeatStage:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureGameArea(TempShot)
    MarkMode := "abs_repeatstage"
    OpenMarkGui("Кликни на кнопку Repeat Stage")
return

OpenMarkGui(promptText) {
    global TempShot, MarkPrompt, MarkPic, MarkListBox, MarkGuiHwnd
    Gui, Mark:New, +HwndMarkGuiHwnd, Разметка
    Gui, Mark:Color, 0x1E1E1E
    Gui, Mark:Font, s10 cE0E0E0, Segoe UI
    Gui, Mark:Add, Text, x10 y10 w1280 vMarkPrompt, % promptText
    Gui, Mark:Add, Picture, x10 y36 w1280 h720 gMarkClick vMarkPic, %TempShot%
    Gui, Mark:Add, ListBox, x1300 y36 w260 h620 vMarkListBox,
    Gui, Mark:Add, Button, x1300 y662 w260 h26 gMarkUndo, Отменить последнее
    Gui, Mark:Add, Button, x1300 y692 w126 h30 gMarkDone, Готово / Сохранить
    Gui, Mark:Add, Button, x1436 y692 w124 h30 gMarkCancel, Отмена
    Gui, Mark:Show, w1576 h730, Разметка
}

MarkClick:
    if (A_GuiControl != "MarkPic")
        return
    if (!MarkGuiHwnd) {
        AddLog("MarkClick: MarkGuiHwnd не задан")
        return
    }
    CoordMode, Mouse, Screen
    MouseGetPos, sx, sy
    VarSetCapacity(mpt, 8, 0)
    NumPut(sx, mpt, 0, "Int")
    NumPut(sy, mpt, 4, "Int")
    DllCall("ScreenToClient", "ptr", MarkGuiHwnd, "ptr", &mpt)
    wx := NumGet(mpt, 0, "Int")
    wy := NumGet(mpt, 4, "Int")
    px := wx - 10
    py := wy - 36
    if (px < 0 || py < 0 || px > 1280 || py > 720) {
        AddLog("Клик мимо картинки разметки, игнорирую (" px "," py ")")
        return
    }

    if (MarkMode = "slots") {
        InputBox, num, Номер юнита, Какой цифрой (1-6) ставится юнит в эту точку?, , 260, 130
        if (ErrorLevel || num = "" || num < 1 || num > 6) {
            AddLog("Отменено: номер юнита не указан")
            return
        }
        MarkList.Push({num: num, x: px, y: py})
        GuiControl, Mark:, MarkListBox, % "Слот " MarkList.Length() ": юнит " num " -> (" px "," py ")"
    }
    else if (MarkMode = "abs_upgrade") {
        UpgradeX := px
        UpgradeY := py
        GuiControl, Mark:, MarkListBox, % "Upgrade: (" px "," py ")"
        GuiControl, Mark:, MarkPrompt, Готово — нажми "Готово / Сохранить"
    }
    else if (MarkMode = "abs_auto") {
        AutoX := px
        AutoY := py
        GuiControl, Mark:, MarkListBox, % "AutoUpgrade: (" px "," py ")"
        GuiControl, Mark:, MarkPrompt, Готово — нажми "Готово / Сохранить"
    }
    else if (MarkMode = "abs_startgame") {
        StartGameX := px
        StartGameY := py
        GuiControl, Mark:, MarkListBox, % "Start Game: (" px "," py ")"
        GuiControl, Mark:, MarkPrompt, Готово — нажми "Готово / Сохранить"
    }
    else if (MarkMode = "abs_repeatstage") {
        RepeatStageX := px
        RepeatStageY := py
        GuiControl, Mark:, MarkListBox, % "RepeatStage: (" px "," py ")"
        GuiControl, Mark:, MarkPrompt, Готово — нажми "Готово / Сохранить"
    }
return

MarkUndo:
    if (MarkMode = "slots") {
        if (MarkList.Length() > 0) {
            MarkList.Pop()
            GuiControl, Mark:, MarkListBox, |
            for i, s in MarkList
                GuiControl, Mark:, MarkListBox, % "Слот " i ": юнит " s.num " -> (" s.x "," s.y ")"
        }
    } else if (MarkMode = "abs_upgrade") {
        GuiControl, Mark:, MarkListBox, |
        GuiControl, Mark:, MarkPrompt, Кликни на кнопку Upgrade
    } else if (MarkMode = "abs_auto") {
        GuiControl, Mark:, MarkListBox, |
        GuiControl, Mark:, MarkPrompt, Кликни на кнопку AutoUpgrade
    } else if (MarkMode = "abs_startgame") {
        GuiControl, Mark:, MarkListBox, |
        GuiControl, Mark:, MarkPrompt, Кликни на кнопку Start Game
    } else if (MarkMode = "abs_repeatstage") {
        GuiControl, Mark:, MarkListBox, |
        GuiControl, Mark:, MarkPrompt, Кликни на кнопку Repeat Stage
    }
return

MarkDone:
    Gui, 1:Default
    if (MarkMode = "slots") {
        if (MarkList.Length() = 0) {
            AddLog("Разметка отменена: слотов не добавлено")
        } else {
            SaveMapSlots(SelectedMapCtl, MarkList)
            LoadMapCoordsOne(SelectedMapCtl)
            AddLog("Сохранено " MarkList.Length() " слотов для """ SelectedMapCtl """")
        }
    } else if (MarkMode = "abs_upgrade") {
        SaveConfig()
        GuiControl,, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ")"
        AddLog("Калибровка Upgrade сохранена: (" UpgradeX "," UpgradeY ")")
    } else if (MarkMode = "abs_auto") {
        SaveConfig()
        GuiControl,, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ")"
        AddLog("Калибровка AutoUpgrade сохранена: (" AutoX "," AutoY ")")
    } else if (MarkMode = "abs_startgame") {
        SaveConfig()
        GuiControl,, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ") Repeat(" RepeatStageX "," RepeatStageY ")"
        AddLog("Калибровка Start Game сохранена: (" StartGameX "," StartGameY ")")
    } else if (MarkMode = "abs_repeatstage") {
        SaveConfig()
        GuiControl,, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ") Repeat(" RepeatStageX "," RepeatStageY ")"
        AddLog("Калибровка RepeatStage сохранена: (" RepeatStageX "," RepeatStageY ")")
    }
    MarkMode := ""
    Gui, Mark:Destroy
    UpdateCalibStatus()
return

MarkCancel:
    MarkMode := ""
    AddLog("Разметка/калибровка отменена пользователем")
    Gui, Mark:Destroy
return

; ===================== НАСТРОЙКИ (диалог) =====================
BtnSettings:
    OpenSettingsGui()
return

OpenSettingsGui() {
    global ClickDelay, SlotClickDelay, UpgradeClickDelay
    global AutoClickDelay, UnitSleepDelay, StartGameDelay, ImgVariation
    global StartGameColor, StartGameColorVar, StartGameCenterX, StartGameCenterY, StartGameRadius
    Gui, Settings:New, , Настройки
    Gui, Settings:Color, 0x1E1E1E
    Gui, Settings:Font, s10 cE0E0E0, Segoe UI

    Gui, Settings:Add, Text, x10 y10 w380 c00CCFF, Задержки между кликами (мс)

    Gui, Settings:Add, Text, x10 y40 w280, КД после номера юнита:
    Gui, Settings:Add, Edit, x300 y40 w80 vSetClickDelay, %ClickDelay%

    Gui, Settings:Add, Text, x10 y70 w280, КД после клика по слоту:
    Gui, Settings:Add, Edit, x300 y70 w80 vSetSlotClickDelay, %SlotClickDelay%

    Gui, Settings:Add, Text, x10 y100 w280, КД после клика Upgrade:
    Gui, Settings:Add, Edit, x300 y100 w80 vSetUpgradeClickDelay, %UpgradeClickDelay%

    Gui, Settings:Add, Text, x10 y130 w280, КД между кликами AutoUpgrade:
    Gui, Settings:Add, Edit, x300 y130 w80 vSetAutoClickDelay, %AutoClickDelay%

    Gui, Settings:Add, Text, x10 y160 w280, КД между юнитами:
    Gui, Settings:Add, Edit, x300 y160 w80 vSetUnitSleepDelay, %UnitSleepDelay%

    Gui, Settings:Add, Text, x10 y190 w280, КД после Start Game:
    Gui, Settings:Add, Edit, x300 y190 w80 vSetStartGameDelay, %StartGameDelay%

    Gui, Settings:Add, Text, x10 y220 w280, Допуск цвета (ImageSearch, 0-255):
    Gui, Settings:Add, Edit, x300 y220 w80 vSetImgVariation, %ImgVariation%

    Gui, Settings:Add, Text, x10 y250 w280, Цвет Start Game (0xRRGGBB):
    Gui, Settings:Add, Edit, x300 y250 w80 vSetStartGameColor, %StartGameColor%

    Gui, Settings:Add, Text, x10 y280 w280, Допуск PixelSearch (0-255):
    Gui, Settings:Add, Edit, x300 y280 w80 vSetStartGameColorVar, %StartGameColorVar%

    Gui, Settings:Add, Text, x10 y310 w280, Центр X (0-1280):
    Gui, Settings:Add, Edit, x300 y310 w80 vSetStartGameCenterX, %StartGameCenterX%

    Gui, Settings:Add, Text, x10 y340 w280, Центр Y (0-720):
    Gui, Settings:Add, Edit, x300 y340 w80 vSetStartGameCenterY, %StartGameCenterY%

    Gui, Settings:Add, Text, x10 y370 w280, Радиус поиска (пиксели):
    Gui, Settings:Add, Edit, x300 y370 w80 vSetStartGameRadius, %StartGameRadius%

    Gui, Settings:Add, Button, x10 y410 w180 h30 gSettingsSave, Сохранить
    Gui, Settings:Add, Button, x200 y410 w180 h30 gSettingsCancel, Отмена

    Gui, Settings:Show, w400 h450, Настройки
}

SettingsSave:
    Gui, 1:Default
    Gui, Settings:Submit, NoHide
    ClickDelay := SetClickDelay
    SlotClickDelay := SetSlotClickDelay
    UpgradeClickDelay := SetUpgradeClickDelay
    AutoClickDelay := SetAutoClickDelay
    UnitSleepDelay := SetUnitSleepDelay
    StartGameDelay := SetStartGameDelay
    ImgVariation := SetImgVariation
    StartGameColor := SetStartGameColor
    StartGameColorVar := SetStartGameColorVar
    StartGameCenterX := SetStartGameCenterX
    StartGameCenterY := SetStartGameCenterY
    StartGameRadius := SetStartGameRadius
    SaveSettings()
    AddLog("Настройки сохранены в ahk\settings.ini")
    Gui, Settings:Destroy
return

SettingsCancel:
    Gui, Settings:Destroy
return

; ===================== КАЛИБРОВКА (отдельное окно с пресетами) =====================
BtnOpenCalibration:
    if (CalibGuiHwnd && DllCall("IsWindow", "ptr", CalibGuiHwnd)) {
        Gui, Calib:Show
        return
    }
    OpenCalibrationGui()
return

OpenCalibrationGui() {
    global CalibGuiHwnd, PresetsIni, CalibStatus   ; <-- добавили CalibStatus
    Gui, Calib:New, +HwndCalibGuiHwnd, Калибровка координат
    Gui, Calib:Color, 0x1E1E1E, 0x252526
    Gui, Calib:Font, s10 cE0E0E0, Segoe UI

    Gui, Calib:Font, s10 c00CCFF Bold, Segoe UI
    Gui, Calib:Add, Text, x14 y14 w520 h24, Калибровка координат кнопок TD
    Gui, Calib:Font, s10 cE0E0E0, Segoe UI

    Gui, Calib:Add, Text, x14 y44 w520 h20 vCalibStatus, % CalibStatusText()   ; обернули в %

    ; ---- группа: калибровка кнопок ----
    Gui, Calib:Add, GroupBox, x14 y74 w640 h140, Калибровка кнопок
    Gui, Calib:Add, Button, x34 y104 w160 h28 gBtnCalibrateUpgrade, Калибровать Upgrade
    Gui, Calib:Add, Button, x204 y104 w160 h28 gBtnCalibrateAuto, Калибровать AutoUpgrade
    Gui, Calib:Add, Button, x374 y104 w160 h28 gBtnCalibrateStartGame, Калибровать Start Game
    Gui, Calib:Add, Button, x34 y138 w160 h28 gBtnCalibrateRepeatStage, Калибровать Repeat Stage
    Gui, Calib:Add, Text, x204 y146 w330 h20 c808080, Клик по скриншоту разметит кнопку

    ; ---- группа: экспорт / импорт ----
    Gui, Calib:Add, GroupBox, x14 y224 w640 h80, Конфигурация
    Gui, Calib:Add, Button, x34 y250 w140 h28 gBtnCalibSaveConfig, Сохранить в config.ini
    Gui, Calib:Add, Button, x184 y250 w140 h28 gBtnCalibLoadConfig, Загрузить из config.ini

    ; ---- группа: пресеты ----
    Gui, Calib:Add, GroupBox, x14 y314 w640 h170, Пресеты координат
    Gui, Calib:Add, Text, x34 y336 w260, Имя пресета:
    Gui, Calib:Add, Edit, x304 y336 w180 h20 vCalibPresetName,
    Gui, Calib:Add, Button, x494 y336 w140 h26 gBtnCalibSavePreset, Сохранить пресет
    Gui, Calib:Add, Button, x494 y366 w140 h26 gBtnCalibLoadPreset, Загрузить пресет
    Gui, Calib:Add, Button, x494 y396 w140 h26 gBtnCalibDeletePreset, Удалить пресет
    Gui, Calib:Add, Text, x34 y366 w260, Список пресетов:
    Gui, Calib:Add, ListBox, x304 y362 w180 h110 vCalibPresetList gCalibPresetSelect,
    Gui, Calib:Add, Button, x34 y396 w140 h26 gBtnCalibRefreshPresets, Обновить список

    Gui, Calib:Add, Button, x494 y444 w140 h28 gBtnCalibClose, Закрыть

    Gui, Calib:Show, w668 h484, Калибровка координат
    LoadPresetsList()
}

CalibStatusText() {
    global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    return "Up(" UpgradeX "," UpgradeY ")  Auto(" AutoX "," AutoY ")  Start(" StartGameX "," StartGameY ")  Repeat(" RepeatStageX "," RepeatStageY ")"
}

UpdateCalibStatus() {
    global CalibStatus   ; <-- добавили
    if (CalibGuiHwnd && DllCall("IsWindow", "ptr", CalibGuiHwnd))
        GuiControl, Calib:, CalibStatus, % CalibStatusText()
}

BtnCalibSaveConfig:
    SaveConfig()
    AddLog("Координаты сохранены в config.ini")
    UpdateCalibStatus()
return

BtnCalibLoadConfig:
    LoadConfig()
    GuiControl, 1:, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ") Repeat(" RepeatStageX "," RepeatStageY ")"
    UpdateCalibStatus()
    AddLog("Координаты загружены из config.ini")
return

; ---------- пресеты ----------
CalibPresetSelect:
    Gui, Calib:Submit, NoHide
    GuiControl, Calib:, CalibPresetName, % CalibPresetList
return

BtnCalibSavePreset:
    Gui, Calib:Submit, NoHide
    if (CalibPresetName = "") {
        MsgBox, 48, Ошибка, Введи имя пресета.
        return
    }
    IniWrite, %UpgradeX%,    %PresetsIni%, %CalibPresetName%, UpgradeX
    IniWrite, %UpgradeY%,    %PresetsIni%, %CalibPresetName%, UpgradeY
    IniWrite, %AutoX%,       %PresetsIni%, %CalibPresetName%, AutoX
    IniWrite, %AutoY%,       %PresetsIni%, %CalibPresetName%, AutoY
    IniWrite, %StartGameX%,  %PresetsIni%, %CalibPresetName%, StartGameX
    IniWrite, %StartGameY%,  %PresetsIni%, %CalibPresetName%, StartGameY
    IniWrite, %RepeatStageX%, %PresetsIni%, %CalibPresetName%, RepeatStageX
    IniWrite, %RepeatStageY%, %PresetsIni%, %CalibPresetName%, RepeatStageY
    AddLog("Пресет """ CalibPresetName """ сохранён")
    LoadPresetsList()
return

BtnCalibLoadPreset:
    Gui, Calib:Submit, NoHide
    Gui, Calib:Default
    if (CalibPresetName = "") {
        GuiControlGet, sel, , CalibPresetList
        if (sel = "") {
            MsgBox, 48, Ошибка, Выбери пресет из списка или введи имя.
            return
        }
        CalibPresetName := sel
    }
    IniRead, v, %PresetsIni%, %CalibPresetName%, UpgradeX, __NONE__
    if (v = "__NONE__") {
        MsgBox, 48, Ошибка, Пресет """ CalibPresetName """ не найден.
        return
    }
    IniRead, v, %PresetsIni%, %CalibPresetName%, UpgradeX, 0
    UpgradeX := v
    IniRead, v, %PresetsIni%, %CalibPresetName%, UpgradeY, 0
    UpgradeY := v
    IniRead, v, %PresetsIni%, %CalibPresetName%, AutoX, 0
    AutoX := v
    IniRead, v, %PresetsIni%, %CalibPresetName%, AutoY, 0
    AutoY := v
    IniRead, v, %PresetsIni%, %CalibPresetName%, StartGameX, 0
    StartGameX := v
    IniRead, v, %PresetsIni%, %CalibPresetName%, StartGameY, 0
    StartGameY := v
    IniRead, v, %PresetsIni%, %CalibPresetName%, RepeatStageX, 0
    RepeatStageX := v
    IniRead, v, %PresetsIni%, %CalibPresetName%, RepeatStageY, 0
    RepeatStageY := v
    GuiControl, 1:, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ") Repeat(" RepeatStageX "," RepeatStageY ")"
    UpdateCalibStatus()
    AddLog("Пресет """ CalibPresetName """ загружен")
return

BtnCalibDeletePreset:
    Gui, Calib:Submit, NoHide
    Gui, Calib:Default
    if (CalibPresetName = "") {
        GuiControlGet, sel, , CalibPresetList
        if (sel = "") {
            MsgBox, 48, Ошибка, Введи или выбери имя пресета для удаления.
            return
        }
        CalibPresetName := sel
    }
    IniDelete, %PresetsIni%, %CalibPresetName%
    GuiControl, Calib:, CalibPresetName,
    AddLog("Пресет """ CalibPresetName """ удалён")
    LoadPresetsList()
return

BtnCalibRefreshPresets:
    LoadPresetsList()
return

LoadPresetsList() {
    global PresetsIni
    GuiControl, Calib:, CalibPresetList, |
    if (!FileExist(PresetsIni))
        return
    FileRead, content, %PresetsIni%
    Loop, Parse, content, `n, `r
    {
        line := A_LoopField
        if (SubStr(line, 1, 1) = "[" && SubStr(line, 0, 1) = "]") {
            name := Trim(SubStr(line, 2, -1))
            GuiControl, Calib:, CalibPresetList, %name%
        }
    }
}

BtnCalibClose:
CalibGuiClose:
    Gui, Calib:Destroy
    CalibGuiHwnd := 0
return

; ===================== СТАРТ / СТОП ФАРМА =====================
BtnStartStop:
F9::
    Gui, Submit, NoHide
    if (SelectedMapCtl = "") {
        GuiControl,, FarmStatus, Статус: сначала выбери карту
        return
    }
    if (!MapCoords.HasKey(SelectedMapCtl)) {
        GuiControl,, FarmStatus, Статус: карта не размечена
        AddLog("Нельзя запустить: """ SelectedMapCtl """ не размечена")
        return
    }
    if !WinExist(WinTitle) {
        GuiControl,, FarmStatus, Статус: игра не найдена
        return
    }
    Running := !Running
    if (Running) {
        GuiControl,, StartStopBtn, Стоп (F9)
        GuiControl,, FarmStatus, Статус: расстановка...
        AddLog("Старт фарма: " SelectedMapCtl)
        SetTimer, RunPlacementSequence, -100
    } else {
        GuiControl,, StartStopBtn, Старт (F9)
        GuiControl,, FarmStatus, Статус: остановлен
        AddLog("Фарм остановлен")
        SetTimer, WatchNextStage, Off
    }
return

; ---- Разовая расстановка всех юнитов по размеченным слотам ----
RunPlacementSequence:
    slots := MapCoords[SelectedMapCtl]
    AddLog("Слотов загружено: " slots.Length() " для """ SelectedMapCtl """")
    ; Кликаем по центру области игры для фокуса
    ToScreen(640, 360)
    MouseMove, % TS_X, % TS_Y, 0
    Click
    Sleep, 200
    for i, s in slots {
        if (!Running)
            break
        Send, % s.num
        Sleep, %ClickDelay%
        ToScreen(s.x, s.y)
        AddLog("Слот " i ": юнит " s.num " client(" s.x "," s.y ") -> screen(" TS_X "," TS_Y ")")
        MouseMove, % TS_X, % TS_Y, 0
        Click
        Sleep, %SlotClickDelay%

        ToScreen(UpgradeX, UpgradeY)
        MouseMove, % TS_X, % TS_Y, 0
        Click
        Sleep, %UpgradeClickDelay%

        ToScreen(AutoX, AutoY)
        Loop, 6 {
            MouseMove, % TS_X, % TS_Y, 0
            Click
            Sleep, %AutoClickDelay%
        }
        AddLog("Юнит " s.num " поставлен и настроена автопрокачка (слот " i ")")
        Sleep, %UnitSleepDelay%
    }
    if (Running) {
        GuiControl,, FarmStatus, Статус: расстановка завершена, нажимаю Start Game...
        AddLog("Расстановка завершена, нажимаю Start Game...")
        ; Если Start Game откалиброван — кликаем по координатам
        if (StartGameX > 0 && StartGameY > 0) {
            ToScreen(StartGameX, StartGameY)
            MouseMove, % TS_X, % TS_Y, 0
            Click
            Sleep, %StartGameDelay%
            AddLog("Start Game нажата: (" StartGameX "," StartGameY ") -> screen(" TS_X "," TS_Y ")")
        } else {
            ; Fallback: пробуем ImageSearch/PixelSearch
            AddLog("Start Game не откалиброван, пробую поиск...")
            ClickGameButton("StartGame.png", StartGameDelay)
        }
        GuiControl,, FarmStatus, Статус: игра запущена, наблюдение
        SetTimer, WatchNextStage, 1000
    }
return

; ---- Наблюдение за окончанием волны / победы / поражения ----
WatchNextStage:
    if !WinExist(WinTitle) {
        GuiControl,, FarmStatus, Статус: окно игры потеряно
        AddLog("Окно Roblox пропало, остановка")
        SetTimer, WatchNextStage, Off
        Running := false
        GuiControl,, StartStopBtn, Старт (F9)
        return
    }
    ; 1) Проверяем поражение — ищем изображение Defeat.png
    if (DetectDefeat()) {
        AddLog("Обнаружено поражение! Кликаю Repeat Stage...")
        ClickRepeatStage()
        GuiControl,, FarmStatus, Статус: поражение, перезапуск...
        return
    }
    ; 2) Проверяем окончание волны — Next Stage
    if (AutoNextStage && DetectNextStage()) {
        AddLog("Обнаружено 'Next Stage', клик...")
        ClickNextStage()
    }
return

; ---- Детект поражения (Defeat) ----
DetectDefeat() {
    global Embedded, ImagesDir, ImgVariation
    if (!Embedded)
        return false
    full := ImagesDir . "\Defeat.png"
    if (FileExist(full)) {
        if (FindGameButton(full, bx, by))
            return true
    }
    ; Fallback: ищем по тексту в окне (если есть)
    return false
}

; ---- Детект кнопки Next Stage ----
DetectNextStage() {
    global Embedded, ImagesDir, ImgVariation
    if (!Embedded)
        return false
    full := ImagesDir . "\NextStage.png"
    if (FileExist(full)) {
        if (FindGameButton(full, bx, by))
            return true
    }
    return false
}

; ---- Клик по кнопке Repeat Stage ----
ClickRepeatStage() {
    global RepeatStageX, RepeatStageY, ImagesDir, ImgVariation, StartGameColor, StartGameColorVar
    if (RepeatStageX > 0 && RepeatStageY > 0) {
        ToScreen(RepeatStageX, RepeatStageY)
        MouseMove, % TS_X, % TS_Y, 0
        Click
        Sleep, 500
        AddLog("Repeat Stage нажата по калиброванным координатам: (" RepeatStageX "," RepeatStageY ")")
        return
    }
    ; Fallback: ImageSearch по RepeatStage.png
    full := ImagesDir . "\RepeatStage.png"
    if (FileExist(full)) {
        if (FindGameButton(full, bx, by)) {
            MouseMove, % bx, % by, 0
            Click
            Sleep, 500
            AddLog("Repeat Stage нажата по поиску изображения")
            return
        }
    }
    ; Fallback: ищем по цвету StartGame
    if (StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
        full := ImagesDir . "\RepeatStage.png"
        if (!FileExist(full)) {
            if (FindGameButtonByColor(StartGameColor, StartGameColorVar, bx, by)) {
                MouseMove, % bx, % by, 0
                Click
                Sleep, 500
                AddLog("Повторить по цвету StartGame (fallback)")
                return
            }
        }
    }
    AddLog("Repeat Stage: не удалось найти кнопку. Откалибруйте координаты.")
}

; ---- Клик по кнопке Next Stage ----
ClickNextStage() {
    global ImagesDir, ImgVariation
    full := ImagesDir . "\NextStage.png"
    if (FileExist(full)) {
        if (FindGameButton(full, bx, by)) {
            MouseMove, % bx, % by, 0
            Click
            AddLog("Next Stage нажата")
            return true
        }
    }
    return false
}

GuiClose:
    if (Embedded)
        UnembedGameWindow()
    ExitApp