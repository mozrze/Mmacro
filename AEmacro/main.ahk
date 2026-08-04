#SingleInstance Off
#NoEnv
#Include %A_ScriptDir%\ahk\drag_select.ahk
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Screen
CoordMode, Pixel, Screen
DetectHiddenWindows, On
SendMode, Input

; ---- Автоперезапуск: если старый экземпляр уже запущен — убиваем его ----
; #SingleInstance Force не перезагружает код, а лишь показывает старое окно.
; Поэтому вручную ищем старый процесс этого же скрипта и завершаем его,
; чтобы каждый запуск гарантированно загружал свежий код с диска.
DetectHiddenWindows, On
WinGet, thisHwnd, ID, ahk_class AutoHotkey
; Ищем другие окна AHK с тем же именем скрипта (A_ScriptName)
WinGet, id, List, ahk_class AutoHotkey
Loop, %id% {
    hwnd := id%A_Index%
    if (hwnd = thisHwnd)
        continue
    WinGetTitle, t, ahk_id %hwnd%
    if (t = A_ScriptName) {
        WinGet, otherPid, PID, ahk_id %hwnd%
        if (otherPid > 0) {
            Process, Close, %otherPid%
            Sleep, 300
        }
    }
}

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

MapList := []      ; Список карт: имена формируются из снимков в maps\*.bmp
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
HoverDelay := 200   ; КД после наведения на место перед выбором юнита
MouseSpeed := 70    ; скорость движения мыши (0-100, выше = быстрее)
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
; Автопрокачка юнитов: приоритет = сколько раз кликнуть по кнопке AutoUpgrade
AutoUpgradeEnabled := false
AutoUpgradePriority := {1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1}
AutoUpgradeUnitOffsetY := 20   ; смещение вверх при клике по юниту
AutoUpgradeGuiHwnd := 0

; ---- состояние окна разметки/калибровки ----
MarkMode := ""
MarkList := []
TemplateName := ""   ; заранее заданное имя шаблона (например "StartGame") или "" = спрашивать
MarkGuiHwnd := 0
CalibGuiHwnd := 0
PresetGuiHwnd := 0
ModalHwnd := 0

; ---- drag-select для захвата шаблонов ----
DragActive := false
DragStartSX := 0, DragStartSY := 0
DragCurSX := 0, DragCurSY := 0
DragPrevRect := ""
DragOverlayHwnd := 0

; Обработчики мыши: только для MarkMode = "template" (drag-select области)
OnMessage(0x201, "OnTemplateLButtonDown")   ; WM_LBUTTONDOWN
OnMessage(0x200, "OnTemplateMouseMove")       ; WM_MOUSEMOVE
OnMessage(0x202, "OnTemplateLButtonUp")       ; WM_LBUTTONUP
; =======================================================

TotalW := GameAreaW + SidebarW
TotalH := GameAreaH

LoadConfig()
LoadSettings()
ReloadMapList()
LoadAllMapCoords()

; ===================== GUI (тёмная тема + HTML на всё окно) =====================
Gui, +HwndMainGuiHwnd -Caption
Gui, Color, 0x121212

; ---- 1. HTML-панель на ВСЁ окно (первой — будет снизу) ----
; Включаем IE11 Edge Mode
RegRead, ieEmu, HKEY_CURRENT_USER, SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION, %A_ScriptName%
if (ErrorLevel || ieEmu < 11001)
    RegWrite, REG_DWORD, HKEY_CURRENT_USER, SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION, %A_ScriptName%, 11001

htmlDir := A_ScriptDir . "\..\UI"
Loop, %htmlDir%, 0, 0
    htmlDir := A_LoopFileLongPath
htmlPath := htmlDir . "\index.html"
StringReplace, htmlPath, htmlPath, \, /, All
htmlURL := "file:///" . htmlPath

Gui, Add, ActiveX, x0 y0 w%TotalW% h%GameAreaH% vWB, Shell.Explorer
WB.Silent := true
ComObjConnect(WB, "WB_")
WB.Navigate(htmlURL . "?_=" . A_TickCount)

; Ждём загрузки HTML
WBWaitStart := A_TickCount
while (WB.ReadyState != 4 && A_TickCount - WBWaitStart < 15000)
    Sleep, 100
Sleep, 200

; ---- 2. Игровая область ПОВЕРХ HTML (полный размер) ----
Gui, Font, s10 cE0E0E0, Segoe UI
Gui, Add, Text, x0 y0 w%GameAreaW% h%GameAreaH% vGameArea 0x201 Border Background0A0A0A,

Gui, Show, w%TotalW% h%GameAreaH%, TD Macro Control

; Таймер опроса JS-команд
SetTimer, PollJSCmd, 20
; Отправляем начальное состояние в HTML
SetTimer, PushStateToHTML, -300
return

; ===================== ЛОГ =====================
AddLog(msg, cls := "") {
    global WB
    FormatTime, ts,, HH:mm:ss
    ; Отправляем в HTML-панель
    if (WB && WB.ReadyState = 4) {
        jsCls := cls ? cls : ""
        safeMsg := StrReplace(msg, "\", "\\")
        safeMsg := StrReplace(safeMsg, """", "\""")
        safeMsg := StrReplace(safeMsg, "`r`n", "\n")
        safeMsg := StrReplace(safeMsg, "`n", "\n")
        js := "ahkLog(""" . safeMsg . """, """ . jsCls . """)"
        try {
            WB.Document.parentWindow.execScript(js)
        } catch e {
            ; HTML ещё не готов — ничего страшного
        }
    }
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
    global AutoClickDelay, UnitSleepDelay, StartGameDelay, HoverDelay, MouseSpeed, ImgVariation
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
    IniRead, v, %SettingsFile%, Delays, HoverDelay, %HoverDelay%
    HoverDelay := v
    IniRead, v, %SettingsFile%, Delays, MouseSpeed, %MouseSpeed%
    MouseSpeed := v
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
    global AutoClickDelay, UnitSleepDelay, StartGameDelay, HoverDelay, MouseSpeed, ImgVariation
    global StartGameColor, StartGameColorVar, StartGameCenterX, StartGameCenterY, StartGameRadius
    IniWrite, %ClickDelay%, %SettingsFile%, Delays, ClickDelay
    IniWrite, %SlotClickDelay%, %SettingsFile%, Delays, SlotClickDelay
    IniWrite, %UpgradeClickDelay%, %SettingsFile%, Delays, UpgradeClickDelay
    IniWrite, %AutoClickDelay%, %SettingsFile%, Delays, AutoClickDelay
    IniWrite, %UnitSleepDelay%, %SettingsFile%, Delays, UnitSleepDelay
    IniWrite, %StartGameDelay%, %SettingsFile%, Delays, StartGameDelay
    IniWrite, %HoverDelay%, %SettingsFile%, Delays, HoverDelay
    IniWrite, %MouseSpeed%, %SettingsFile%, Delays, MouseSpeed
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

; Сбор списка карт из сохранённых снимков (maps\*.bmp).
; Имя карты = имя файла без расширения.
ReloadMapList() {
    global MapList, MapsDir
    MapList := []
    Loop, Files, %MapsDir%\*.bmp
    {
        name := A_LoopFileName
        StringGetPos, dotPos, name, .
        if (dotPos >= 0)
            name := SubStr(name, 1, dotPos)
        MapList.Push(name)
    }
}

; Перестроение списка карт в HTML-панели (с сохранением выбора).
RefreshMapDropdown() {
    global MapList, SelectedMapCtl
    UpdateMapListHTML()
    if (SelectedMapCtl != "")
        WBH_CallJS("ahkUpdateMap(""" . SelectedMapCtl . """)")
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
            SmoothClick(btnX, btnY, 150)
            if (delayAfter > 0)
                Sleep, %delayAfter%
            return true
        }
    }
    if (StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
        if (FindGameButtonByColor(StartGameColor, StartGameColorVar, btnX, btnY)) {
            SmoothClick(btnX, btnY, 150)
            if (delayAfter > 0)
                Sleep, %delayAfter%
            return true
        }
    }
    return false
}

BtnEmbed:
    if (Embedded) {
        UnembedGameWindow()
        Embedded := false
        WBH_CallJS("ahkUpdateEmbed(false)")
        return
    }
    if !WinExist(WinTitle) {
        AddLog("Ошибка встраивания: окно Roblox не найдено", "warn")
        WBH_CallJS("ahkUpdateEmbed(false)")
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
    WBH_CallJS("ahkUpdateEmbed(true)")
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
    ; Появляется в списке карт сразу после сохранения снимка
    ReloadMapList()
    SelectedMapCtl := ShotName
    Gui, 1:Default
    RefreshMapDropdown()
    AddLog("Карта """ . ShotName . """ добавлена в список")
return

SnapCancel:
    Gui, Snap:Destroy
    AddLog("Снимок отклонён, не сохранён")
return

; ===================== СКРИНШОТ ОБЛАСТИ ИГРЫ =====================
CaptureGameArea(filepath) {
    global MainGuiHwnd, GameAreaW, GameAreaH
    ; GameArea всегда в левом верхнем углу главного окна (x0 y0),
    ; размер GameAreaW x GameAreaH. GuiControlGet здесь НЕ использовать:
    ; при вызове из окна калибровки он ищет GameArea в чужом окне
    ; и возвращает нулевые размеры → битый файл → чёрный экран.
    VarSetCapacity(pt, 8, 0)
    DllCall("ClientToScreen", "ptr", MainGuiHwnd, "ptr", &pt)
    ScreenX := NumGet(pt, 0, "Int")
    ScreenY := NumGet(pt, 4, "Int")
    CaptureScreenshot(ScreenX, ScreenY, GameAreaW, GameAreaH, filepath)
    ; Если кадр вышел почти чёрным (игра свёрнута/не видна на экране) —
    ; пробуем PrintWindow по HWND игры
    if (IsMostlyBlack(filepath)) {
        AddLog("Захват экрана дал чёрный кадр, пробую PrintWindow...")
        if (CaptureGameWindow(filepath))
            return
        AddLog("PrintWindow тоже не дал кадр. Убедись, что Roblox встроен и виден на экране.")
    }
}

; ---- Захват окна игры через PrintWindow (запасной вариант) ----
CaptureGameWindow(filepath) {
    global GameHwnd, GameAreaW, GameAreaH
    if (!GameHwnd || !WinExist("ahk_id " . GameHwnd))
        return false
    hdcWin := DllCall("GetDC", "ptr", GameHwnd, "ptr")
    if (!hdcWin)
        return false
    hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcWin, "ptr")
    hBmp   := DllCall("CreateCompatibleBitmap", "ptr", hdcWin, "int", GameAreaW, "int", GameAreaH, "ptr")
    hOld   := DllCall("SelectObject", "ptr", hdcMem, "ptr", hBmp, "ptr")
    ; PW_RENDERFULLCONTENT (0x2) — захват DirectX-контента
    ok := DllCall("PrintWindow", "ptr", GameHwnd, "ptr", hdcMem, "uint", 0x2)
    DllCall("SelectObject", "ptr", hdcMem, "ptr", hOld)
    DllCall("DeleteDC", "ptr", hdcMem)
    DllCall("ReleaseDC", "ptr", GameHwnd, "ptr", hdcWin)
    if (!ok) {
        DllCall("DeleteObject", "ptr", hBmp)
        return false
    }
    SaveHBITMAPToBMP(hBmp, filepath, GameAreaW, GameAreaH)
    DllCall("DeleteObject", "ptr", hBmp)
    return !IsMostlyBlack(filepath)
}

; ---- Проверка: не является ли кадр почти чёрным (сетка 5x5 точек) ----
IsMostlyBlack(filepath) {
    if !FileExist(filepath)
        return true
    file := FileOpen(filepath, "r")
    if !file
        return true
    w := 1280
    h := 720
    stride := ((w*3+3)//4)*4
    total := 0, n := 0
    Loop 5 {
        px := w//5 * A_Index - w//10
        Loop 5 {
            py := h//5 * A_Index - h//10
            file.Seek(54 + py*stride + px*3)
            b := file.ReadUChar()
            g := file.ReadUChar()
            r := file.ReadUChar()
            total += r + g + b
            n++
        }
    }
    file.Close()
    ; средний канал < 10 → почти чёрный
    return (total < n*30)
}

; ---- Захват с временным скрытием плавающих окон ----
; Прячет все дочерние окна (калибровка, настройки, пресеты),
; чтобы они не заслоняли GameArea при BitBlt, затем захватывает
; и возвращает окна обратно.
CaptureForMarking(filepath) {
    global CalibGuiHwnd, PresetGuiHwnd
    hidden := []

    ; Прячем окна калибровки / пресетов / настроек если открыты
    if (CalibGuiHwnd && DllCall("IsWindow", "ptr", CalibGuiHwnd)) {
        DllCall("ShowWindow", "ptr", CalibGuiHwnd, "int", 0)
        hidden.Push(CalibGuiHwnd)
    }
    if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
        DllCall("ShowWindow", "ptr", PresetGuiHwnd, "int", 0)
        hidden.Push(PresetGuiHwnd)
    }
    ; WinWaitActive / Sleep чтобы DWM успел перерисовать без этих окон
    Sleep, 150

    CaptureGameArea(filepath)

    ; Возвращаем окна обратно
    for i, hwnd in hidden
        DllCall("ShowWindow", "ptr", hwnd, "int", 1)
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
    ; FileOpen "w" сам перезапишет файл; FileDelete перед этим опасен:
    ; если между удалением и созданием произойдёт сбой, файл пропадёт.
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
    CaptureForMarking(TempShot)
    MarkMode := "slots"
    ; Загружаем существующие слоты, если карта уже была размечена ранее
    if (MapCoords.HasKey(SelectedMapCtl)) {
        ; Клонируем чтобы не испортить оригинал при редактировании
        src := MapCoords[SelectedMapCtl]
        MarkList := []
        for i, v in src
            MarkList.Push({num: v.num, x: v.x, y: v.y})
    } else {
        MarkList := []
    }
    OpenMarkGui("Кликай по местам постановки юнитов (номер юнита спросит после каждого клика)")
    ; Показываем уже существующие слоты в списке
    Loop, % MarkList.Length() {
        s := MarkList[A_Index]
        GuiControl, Mark:, MarkListBox, % "Слот " A_Index ": юнит " s.num " -> (" s.x "," s.y ")"
    }
return

; ===================== КАЛИБРОВКА UPGRADE =====================
BtnCalibrateUpgrade:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "abs_upgrade"
    OpenMarkGui("Кликни на кнопку Upgrade")
return

; ===================== КАЛИБРОВКА START GAME =====================
BtnCalibrateStartGame:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "abs_startgame"
    OpenMarkGui("Кликни на кнопку Start Game")
return

; ===================== КАЛИБРОВКА REPEAT STAGE =====================
BtnCalibrateRepeatStage:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "abs_repeatstage"
    OpenMarkGui("Кликни на кнопку Repeat Stage")
return

; ===================== СНЯТИЕ ШАБЛОНА (Defeat/Victory) =====================
; Захватывает кадр, пользователь обводит 2 кликами небольшую область,
; макрос вырезает её в images\<имя>.png для ImageSearch-детекта.
BtnCaptureTemplate:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "template"
    TemplateName := ""
    MarkList := []
    OpenMarkGui("Зажми кнопку мыши и обведи область (например слово VICTORY). Отпусти — шаблон сохранится.")
return

; ===================== СНЯТИЕ ШАБЛОНА КНОПКИ START GAME =====================
; То же самое, что Defeat/Victory, но имя шаблона задано заранее (StartGame) —
; без запроса имени. Потом этот шаблон ищет ClickStartGameRetry.
BtnCaptureStartGame:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "template"
    TemplateName := "StartGame"
    MarkList := []
    OpenMarkGui("Зажми кнопку мыши и обведи часть кнопки Start Game (слово START или иконку, БЕЗ рамки и краёв). Отпусти — шаблон сохранится как StartGame.bmp.")
return

SaveTemplateRegion(x1, y1, x2, y2) {
    global TempShot, ImagesDir, TemplateName
    ; Нормализуем углы
    if (x1 > x2) {
        t := x1, x1 := x2, x2 := t
    }
    if (y1 > y2) {
        t := y1, y1 := y2, y2 := t
    }
    w := x2 - x1 + 1
    h := y2 - y1 + 1
    if (w < 8 || h < 8) {
        AddLog("Область слишком маленькая (" w "x" h "), шаблон не сохранён")
        return
    }
    ; Имя: либо задано заранее (Start Game), либо спрашиваем у пользователя (Defeat/Victory)
    if (TemplateName != "") {
        TplName := TemplateName
        TemplateName := ""
    } else {
        InputBox, TplName, Имя шаблона, Введи имя для шаблона (например: Victory или Defeat), , 320, 140
        if (ErrorLevel || TplName = "") {
            AddLog("Сохранение шаблона отменено")
            return
        }
    }
    ; Сохраняем как BMP (ImageSearch отлично работает с BMP, GDI+ не нужен)
    out := ImagesDir . "\" . TplName . ".bmp"
    if !CropBMP(TempShot, x1, y1, w, h, out) {
        AddLog("Не удалось вырезать шаблон")
        return
    }
    AddLog("Шаблон сохранён: images\" TplName ".bmp (" w "x" h ")")
    ; Сразу проверяем, что шаблон реально находится на экране
    if (FindGameButton(out, fx, fy))
        AddLog("Проверка: шаблон найден на экране в (" fx "," fy ") — детект будет работать!")
    else
        AddLog("ВНИМАНИЕ: шаблон НЕ найден на текущем экране. Проверь, что игра не изменилась после снятия кадра.")
}

; ---- Вырезает прямоугольную область из 24-бит BMP (src 1280x720) в новый BMP ----
CropBMP(srcBmp, x, y, w, h, dstBmp) {
    global GameAreaW, GameAreaH
    if !FileExist(srcBmp)
        return false
    src := FileOpen(srcBmp, "r")
    if !src
        return false
    ; 24-бит BMP, отрицательная высота = сверху вниз (как у нас в SaveHBITMAPToBMP)
    srcStride := ((GameAreaW*3+3)//4)*4
    dstStride := ((w*3+3)//4)*4
    ; Читаем строки y..y+h-1 из исходника, пишем в новый файл
    dst := FileOpen(dstBmp, "w")
    if !dst {
        src.Close()
        return false
    }
    ; Заголовок нового BMP
    VarSetCapacity(bi, 40, 0)
    NumPut(40, bi, 0, "UInt")
    NumPut(w, bi, 4, "Int")
    NumPut(-h, bi, 8, "Int")   ; top-down
    NumPut(1, bi, 12, "UShort")
    NumPut(24, bi, 14, "UShort")
    VarSetCapacity(fh, 14, 0)
    NumPut(0x4D42, fh, 0, "UShort")
    NumPut(14 + 40 + dstStride*h, fh, 2, "UInt")
    NumPut(14 + 40, fh, 10, "UInt")
    dst.RawWrite(&fh, 14)
    dst.RawWrite(&bi, 40)
    ; Копируем пиксели построчно
    VarSetCapacity(rowBuf, srcStride, 0)
    Loop, %h% {
        row := y + A_Index - 1
        src.Seek(54 + row*srcStride + x*3)
        src.RawRead(&rowBuf, w*3)
        ; Дополняем строку нулями до dstStride
        if (dstStride > w*3) {
            VarSetCapacity(pad, dstStride - w*3, 0)
            dst.RawWrite(&rowBuf, w*3)
            dst.RawWrite(&pad, dstStride - w*3)
        } else {
            dst.RawWrite(&rowBuf, w*3)
        }
    }
    src.Close()
    dst.Close()
    return FileExist(dstBmp)
}

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
    ; Примечание: template-режим (drag-select) обрабатывается через OnMessage-обработчики,
    ; а не через этот g-label. См. OnTemplateLButtonUp.
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
    } else if (MarkMode = "abs_startgame") {
        GuiControl, Mark:, MarkListBox, |
        GuiControl, Mark:, MarkPrompt, Кликни на кнопку Start Game
    } else if (MarkMode = "abs_repeatstage") {
        GuiControl, Mark:, MarkListBox, |
        GuiControl, Mark:, MarkPrompt, Кликни на кнопку Repeat Stage
    }
    ; template — нет отмены (drag-select целиком обрабатывается в OnTemplateLButtonUp)
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
        UpdateCoordsHTML()
        AddLog("Калибровка Upgrade сохранена: (" UpgradeX "," UpgradeY ")")
    } else if (MarkMode = "abs_startgame") {
        SaveConfig()
        UpdateCoordsHTML()
        AddLog("Калибровка Start Game сохранена: (" StartGameX "," StartGameY ")")
    } else if (MarkMode = "abs_repeatstage") {
        SaveConfig()
        UpdateCoordsHTML()
        AddLog("Калибровка RepeatStage сохранена: (" RepeatStageX "," RepeatStageY ")")
    } else if (MarkMode = "template") {
        AddLog("Снятие шаблона закрыто без сохранения")
        TemplateName := ""
        ; Подчищаем drag-состояние (если пользователь нажал Готово не отпуская мышь)
        DragCleanup()
    }
    MarkMode := ""
    Gui, Mark:Destroy
    ; Восстанавливаем видимость окна калибровки
    if (CalibGuiHwnd && DllCall("IsWindow", "ptr", CalibGuiHwnd))
        DllCall("ShowWindow", "ptr", CalibGuiHwnd, "int", 1)
    UpdateCalibStatus()
return

MarkCancel:
    MarkMode := ""
    TemplateName := ""
    DragCleanup()
    AddLog("Разметка/калибровка отменена пользователем")
    Gui, Mark:Destroy
return

; ===================== НАСТРОЙКИ (диалог) =====================
BtnSettings:
    OpenSettingsGui()
return

OpenSettingsGui() {
    global ClickDelay, SlotClickDelay, UpgradeClickDelay
    global AutoClickDelay, UnitSleepDelay, StartGameDelay, HoverDelay, MouseSpeed, ImgVariation
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

    Gui, Settings:Add, Text, x10 y220 w280, КД после наведения (перед выбором юнита):
    Gui, Settings:Add, Edit, x300 y220 w80 vSetHoverDelay, %HoverDelay%

    Gui, Settings:Add, Text, x10 y250 w280, Скорость мыши (0-100):
    Gui, Settings:Add, Edit, x300 y250 w80 vSetMouseSpeed, %MouseSpeed%

    Gui, Settings:Add, Text, x10 y280 w280, Допуск цвета (ImageSearch, 0-255):
    Gui, Settings:Add, Edit, x300 y280 w80 vSetImgVariation, %ImgVariation%

    Gui, Settings:Add, Text, x10 y310 w280, Цвет Start Game (0xRRGGBB):
    Gui, Settings:Add, Edit, x300 y310 w80 vSetStartGameColor, %StartGameColor%

    Gui, Settings:Add, Text, x10 y340 w280, Допуск PixelSearch (0-255):
    Gui, Settings:Add, Edit, x300 y340 w80 vSetStartGameColorVar, %StartGameColorVar%

    Gui, Settings:Add, Text, x10 y370 w280, Центр X (0-1280):
    Gui, Settings:Add, Edit, x300 y370 w80 vSetStartGameCenterX, %StartGameCenterX%

    Gui, Settings:Add, Text, x10 y400 w280, Центр Y (0-720):
    Gui, Settings:Add, Edit, x300 y400 w80 vSetStartGameCenterY, %StartGameCenterY%

    Gui, Settings:Add, Text, x10 y430 w280, Радиус поиска (пиксели):
    Gui, Settings:Add, Edit, x300 y430 w80 vSetStartGameRadius, %StartGameRadius%

    Gui, Settings:Add, Button, x10 y470 w180 h30 gSettingsSave, Сохранить
    Gui, Settings:Add, Button, x200 y470 w180 h30 gSettingsCancel, Отмена

    Gui, Settings:Show, w400 h510, Настройки
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
    HoverDelay := SetHoverDelay
    MouseSpeed := SetMouseSpeed
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

; ===================== ПРЕСЕТЫ (отдельное окно) =====================
BtnOpenPresets:
    if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
        Gui, Preset:Show
        return
    }
    OpenPresetsGui()
return

OpenPresetsGui() {
    global PresetGuiHwnd
    Gui, Preset:New, +HwndPresetGuiHwnd, Пресеты
    Gui, Preset:Color, 0x1E1E1E, 0x252526
    Gui, Preset:Font, s10 cE0E0E0, Segoe UI

    Gui, Preset:Font, s9 c00CCFF Bold, Segoe UI
    Gui, Preset:Add, Text, x12 y10 w540 h20, Пресеты — полная конфигурация
    Gui, Preset:Font, s9 cE0E0E0, Segoe UI

    ; ---- имя пресета + действия ----
    Gui, Preset:Add, Text, x12 y40 w220, Имя пресета:
    Gui, Preset:Add, Edit, x170 y38 w220 h22 vPresetName,
    Gui, Preset:Add, Button, x400 y38 w150 h24 gBtnPresetSave, Сохранить пресет

    ; ---- список пресетов ----
    Gui, Preset:Add, Text, x12 y72 w220, Список пресетов:
    Gui, Preset:Add, ListBox, x170 y68 w220 h140 vPresetList gPresetSelect,
    Gui, Preset:Add, Button, x400 y68 w150 h24 gBtnPresetLoad, Загрузить пресет
    Gui, Preset:Add, Button, x400 y98 w150 h24 gBtnPresetDelete, Удалить пресет
    Gui, Preset:Add, Button, x400 y128 w150 h24 gBtnPresetRefresh, Обновить список

    ; ---- подсказка о составе ----
    Gui, Preset:Font, s7 c808080 Italic, Segoe UI
    Gui, Preset:Add, Text, x12 y222 w540 h34, Пресет включает ВСЁ: координаты кнопок (Upgrade/Auto/StartGame/RepeatStage), задержки, параметры ImageSearch/PixelSearch и слоты всех карт (расположение юнитов). При загрузке пресет сразу применяется и записывается в config.ini, settings.ini и maps\*_slots.ini.
    Gui, Preset:Font, s9 cE0E0E0 Norm, Segoe UI

    Gui, Preset:Add, Button, x400 y268 w150 h26 gBtnPresetClose, Закрыть

    Gui, Preset:Show, w570 h306, Пресеты
    LoadPresetsList()
}

; ===================== КАЛИБРОВКА (отдельное окно) =====================
BtnOpenCalibration:
    if (CalibGuiHwnd && DllCall("IsWindow", "ptr", CalibGuiHwnd)) {
        Gui, Calib:Show
        return
    }
    OpenCalibrationGui()
return

OpenCalibrationGui() {
    global CalibGuiHwnd, CalibStatus
    Gui, Calib:New, +HwndCalibGuiHwnd, Калибровка координат
    Gui, Calib:Color, 0x1E1E1E, 0x252526
    Gui, Calib:Font, s10 cE0E0E0, Segoe UI

    Gui, Calib:Font, s10 c00CCFF Bold, Segoe UI
    Gui, Calib:Add, Text, x14 y14 w520 h24, Калибровка координат кнопок TD
    Gui, Calib:Font, s10 cE0E0E0, Segoe UI

    Gui, Calib:Add, Text, x14 y44 w520 h20 vCalibStatus, % CalibStatusText()

    ; ---- группа: калибровка кнопок ----
    Gui, Calib:Add, GroupBox, x14 y74 w640 h140, Калибровка кнопок
    Gui, Calib:Add, Button, x34 y104 w160 h28 gBtnCalibrateUpgrade, Калибровать Upgrade
    Gui, Calib:Add, Button, x204 y104 w160 h28 gBtnCalibrateStartGame, Калибровать Start Game
    Gui, Calib:Add, Button, x374 y104 w160 h28 gBtnCalibrateRepeatStage, Калибровать Repeat Stage
    Gui, Calib:Add, Text, x204 y146 w330 h20 c808080, Клик по скриншоту разметит кнопку. AutoUpgrade — в меню Автопрокачки.

    ; ---- группа: шаблоны для детекта победы/поражения ----
    Gui, Calib:Add, GroupBox, x14 y224 w640 h96, Шаблоны детекта Defeat / Victory
    Gui, Calib:Add, Button, x34 y250 w180 h28 gBtnCaptureTemplate, Снять шаблон с экрана
    Gui, Calib:Add, Button, x34 y284 w180 h28 gBtnTestDetection, Проверить детект сейчас
    Gui, Calib:Add, Text, x224 y256 w410 h40 c808080, Обведи мышью НЕБОЛЬШУЮ область (например слово "VICTORY" или "DEFEAT"). Большие шаблоны ImageSearch не находит!
    Gui, Calib:Add, Text, x224 y278 w410 h20 c00CCFF, Имя сохранится как images\*.bmp

    ; ---- группа: шаблон детекта кнопки Start Game ----
    Gui, Calib:Add, GroupBox, x14 y330 w640 h96, Шаблон детекта Start Game
    Gui, Calib:Add, Button, x34 y356 w180 h28 gBtnCaptureStartGame, Снять шаблон Start Game
    Gui, Calib:Add, Button, x34 y390 w180 h28 gBtnTestStartGame, Проверить детект старта
    Gui, Calib:Add, Text, x224 y362 w410 h40 c808080, Обведи ЧАСТЬ кнопки Start (например слово "START" — без рамки и краёв). Макрос будет искать и кликать по нему.
    Gui, Calib:Add, Text, x224 y384 w410 h20 c00CCFF, Сохранится как images\StartGame.bmp (без запроса имени)

    Gui, Calib:Add, Button, x494 y442 w140 h28 gBtnCalibClose, Закрыть

    Gui, Calib:Show, w668 h486, Калибровка координат
}

; ---- Проверка детекта победы/поражения на текущем экране ----
BtnTestDetection:
    global ImagesDir
    if (DetectVictory())
        AddLog("Проверка: VICTORY обнаружен на экране!")
    else if (DetectDefeat())
        AddLog("Проверка: DEFEAT обнаружен на экране!")
    else {
        AddLog("Проверка: ни VICTORY, ни DEFEAT не найдены на текущем экране.")
        if (!FileExist(ImagesDir . "\Victory.bmp") && !FileExist(ImagesDir . "\Victory.png"))
            AddLog("Victory-шаблон отсутствует в images\ — сначала сними его кнопкой «Снять шаблон».")
        if (!FileExist(ImagesDir . "\Defeat.bmp") && !FileExist(ImagesDir . "\Defeat.png"))
            AddLog("Defeat-шаблон отсутствует в images\ — сначала сними его кнопкой «Снять шаблон».")
        AddLog("Совет: открой экран победы в игре и нажми «Снять шаблон» ещё раз, обведя слово VICTORY.")
    }
return

; ---- Проверка детекта кнопки Start Game на текущем экране ----
BtnTestStartGame:
    global ImagesDir
    full := ImagesDir . "\StartGame.bmp"
    if !FileExist(full)
        full := ImagesDir . "\StartGame.png"
    if !FileExist(full) {
        AddLog("Проверка: StartGame-шаблон отсутствует в images\ — сначала сними его кнопкой «Снять шаблон Start Game».")
        AddLog("Совет: открой в игре экран с кнопкой Start Game и сними шаблон, обведя ЧАСТЬ кнопки (слово START).")
        return
    }
    if (IsTemplateTooBig(full)) {
        AddLog("Проверка: StartGame-шаблон слишком большой — ImageSearch его не найдёт. Сними шаблон поменьше (обведи только слово START).")
        return
    }
    if (FindGameButton(full, bx, by))
        AddLog("Проверка: Start Game найден на экране в (" bx "," by ") — детект будет работать!")
    else
        AddLog("Проверка: Start Game НЕ найден на текущем экране. Открой экран с кнопкой Start Game и нажми проверку ещё раз.")
return

CalibStatusText() {
    global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    return "Up(" UpgradeX "," UpgradeY ")  Auto(" AutoX "," AutoY ")  Start(" StartGameX "," StartGameY ")  Repeat(" RepeatStageX "," RepeatStageY ")"
}

UpdateCalibStatus() {
    global CalibStatus
    if (CalibGuiHwnd && DllCall("IsWindow", "ptr", CalibGuiHwnd))
        GuiControl, Calib:, CalibStatus, % CalibStatusText()
}

; ---------- пресеты (окно Preset) ----------
PresetSelect:
    Gui, Preset:Submit, NoHide
    GuiControl, Preset:, PresetName, % PresetList
return

BtnPresetSave:
    ; Если PresetName уже задан (из модального окна), не перезаписываем из GUI
    if (PresetName = "" || !PresetGuiHwnd || !DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
        if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd))
            Gui, Preset:Submit, NoHide
    }
    if (PresetName = "") {
        MsgBox, 48, Ошибка, Введи имя пресета.
        return
    }
    ; ---- 1. Координаты кнопок (калибровка) ----
    IniWrite, %UpgradeX%,     %PresetsIni%, %PresetName%, UpgradeX
    IniWrite, %UpgradeY%,     %PresetsIni%, %PresetName%, UpgradeY
    IniWrite, %AutoX%,        %PresetsIni%, %PresetName%, AutoX
    IniWrite, %AutoY%,        %PresetsIni%, %PresetName%, AutoY
    IniWrite, %StartGameX%,   %PresetsIni%, %PresetName%, StartGameX
    IniWrite, %StartGameY%,   %PresetsIni%, %PresetName%, StartGameY
    IniWrite, %RepeatStageX%, %PresetsIni%, %PresetName%, RepeatStageX
    IniWrite, %RepeatStageY%, %PresetsIni%, %PresetName%, RepeatStageY
    ; ---- 2. Задержки (Delays) ----
    IniWrite, %ClickDelay%,        %PresetsIni%, %PresetName%, ClickDelay
    IniWrite, %SlotClickDelay%,    %PresetsIni%, %PresetName%, SlotClickDelay
    IniWrite, %UpgradeClickDelay%, %PresetsIni%, %PresetName%, UpgradeClickDelay
    IniWrite, %AutoClickDelay%,    %PresetsIni%, %PresetName%, AutoClickDelay
    IniWrite, %UnitSleepDelay%,    %PresetsIni%, %PresetName%, UnitSleepDelay
    IniWrite, %StartGameDelay%,    %PresetsIni%, %PresetName%, StartGameDelay
    IniWrite, %HoverDelay%,        %PresetsIni%, %PresetName%, HoverDelay
    IniWrite, %MouseSpeed%,        %PresetsIni%, %PresetName%, MouseSpeed
    ; ---- 3. Поиск изображений (ImageSearch) ----
    IniWrite, %ImgVariation%, %PresetsIni%, %PresetName%, ImgVariation
    ; ---- 4. Поиск пикселя (PixelSearch) ----
    IniWrite, %StartGameColor%,    %PresetsIni%, %PresetName%, StartGameColor
    IniWrite, %StartGameColorVar%, %PresetsIni%, %PresetName%, StartGameColorVar
    IniWrite, %StartGameCenterX%,  %PresetsIni%, %PresetName%, StartGameCenterX
    IniWrite, %StartGameCenterY%,  %PresetsIni%, %PresetName%, StartGameCenterY
    IniWrite, %StartGameRadius%,   %PresetsIni%, %PresetName%, StartGameRadius
    ; ---- 5. Слоты всех карт (расположение юнитов) ----
    IniWrite, % MapList.Length(), %PresetsIni%, %PresetName%, MapCount
    for idx, mapName in MapList {
        nameKey := "Map_" idx "_Name"
        IniWrite, %mapName%, %PresetsIni%, %PresetName%, %nameKey%
        if (MapCoords.HasKey(mapName)) {
            slots := MapCoords[mapName]
            slotCount := slots.Length()
        } else {
            slotCount := 0
        }
        cntKey := "Map_" idx "_SlotCount"
        IniWrite, %slotCount%, %PresetsIni%, %PresetName%, %cntKey%
        Loop, %slotCount% {
            s := slots[A_Index]
            slotKey := "Map_" idx "_Slot_" A_Index
            line := s.num . "," . s.x . "," . s.y
            IniWrite, %line%, %PresetsIni%, %PresetName%, %slotKey%
        }
    }
    AddLog("Пресет """ PresetName """ сохранён (координаты + настройки + слоты всех карт)")
    LoadPresetsList()
return

BtnPresetLoad:
    ; Если PresetName уже задан (из модального окна), не перезаписываем из GUI
    if (PresetName = "" || !PresetGuiHwnd || !DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
        if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
            Gui, Preset:Submit, NoHide
            Gui, Preset:Default
        }
    }
    if (PresetName = "") {
        if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
            GuiControlGet, sel, , PresetList
            if (sel != "")
                PresetName := sel
        }
    }
    if (PresetName = "") {
        MsgBox, 48, Ошибка, Выбери пресет из списка или введи имя.
        return
    }
    IniRead, v, %PresetsIni%, %PresetName%, UpgradeX, __NONE__
    if (v = "__NONE__") {
        MsgBox, 48, Ошибка, Пресет """ PresetName """ не найден.
        return
    }
    ; ---- 1. Координаты кнопок ----
    IniRead, v, %PresetsIni%, %PresetName%, UpgradeX, 0
    UpgradeX := v
    IniRead, v, %PresetsIni%, %PresetName%, UpgradeY, 0
    UpgradeY := v
    IniRead, v, %PresetsIni%, %PresetName%, AutoX, 0
    AutoX := v
    IniRead, v, %PresetsIni%, %PresetName%, AutoY, 0
    AutoY := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameX, 0
    StartGameX := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameY, 0
    StartGameY := v
    IniRead, v, %PresetsIni%, %PresetName%, RepeatStageX, 0
    RepeatStageX := v
    IniRead, v, %PresetsIni%, %PresetName%, RepeatStageY, 0
    RepeatStageY := v
    ; ---- 2. Задержки ----
    IniRead, v, %PresetsIni%, %PresetName%, ClickDelay, %ClickDelay%
    ClickDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, SlotClickDelay, %SlotClickDelay%
    SlotClickDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, UpgradeClickDelay, %UpgradeClickDelay%
    UpgradeClickDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, AutoClickDelay, %AutoClickDelay%
    AutoClickDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, UnitSleepDelay, %UnitSleepDelay%
    UnitSleepDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameDelay, %StartGameDelay%
    StartGameDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, HoverDelay, %HoverDelay%
    HoverDelay := v
    IniRead, v, %PresetsIni%, %PresetName%, MouseSpeed, %MouseSpeed%
    MouseSpeed := v
    ; ---- 3. ImageSearch ----
    IniRead, v, %PresetsIni%, %PresetName%, ImgVariation, %ImgVariation%
    ImgVariation := v
    ; ---- 4. PixelSearch ----
    IniRead, v, %PresetsIni%, %PresetName%, StartGameColor, %StartGameColor%
    StartGameColor := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameColorVar, %StartGameColorVar%
    StartGameColorVar := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameCenterX, %StartGameCenterX%
    StartGameCenterX := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameCenterY, %StartGameCenterY%
    StartGameCenterY := v
    IniRead, v, %PresetsIni%, %PresetName%, StartGameRadius, %StartGameRadius%
    StartGameRadius := v
    ; ---- 5. Сохраняем загруженные значения в config.ini и settings.ini ----
    SaveConfig()
    SaveSettings()
    ; ---- 6. Слоты всех карт ----
    IniRead, mapCount, %PresetsIni%, %PresetName%, MapCount, 0
    Loop, %mapCount% {
        idx := A_Index
        nameKey := "Map_" idx "_Name"
        IniRead, mapName, %PresetsIni%, %PresetName%, %nameKey%, __NONE__
        if (mapName = "" || mapName = "ERROR" || mapName = "__NONE__")
            continue
        cntKey := "Map_" idx "_SlotCount"
        IniRead, slotCount, %PresetsIni%, %PresetName%, %cntKey%, 0
        slotList := []
        Loop, %slotCount% {
            slotKey := "Map_" idx "_Slot_" A_Index
            IniRead, slotLine, %PresetsIni%, %PresetName%, %slotKey%, __NONE__
            if (slotLine = "" || slotLine = "ERROR" || slotLine = "__NONE__")
                continue
            StringSplit, p, slotLine, `,
            slotList.Push({num: p1, x: p2, y: p3})
        }
        ; Записываем слоты в файл карты и обновляем MapCoords
        SaveMapSlots(mapName, slotList)
        LoadMapCoordsOne(mapName)
    }
    ; ---- 7. Обновляем UI ----
    ReloadMapList()
    LoadAllMapCoords()
    RefreshMapDropdown()
    UpdateCoordsHTML()
    UpdateCalibStatus()
    AddLog("Пресет """ PresetName """ загружен (координаты + настройки + слоты карт применены и записаны на диск)")
return

BtnPresetDelete:
    ; Если PresetName уже задан (из модального окна), не перезаписываем из GUI
    if (PresetName = "" || !PresetGuiHwnd || !DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
        if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
            Gui, Preset:Submit, NoHide
            Gui, Preset:Default
        }
    }
    if (PresetName = "") {
        if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
            GuiControlGet, sel, , PresetList
            if (sel != "")
                PresetName := sel
        }
    }
    if (PresetName = "") {
        MsgBox, 48, Ошибка, Введи или выбери имя пресета для удаления.
        return
    }
    IniDelete, %PresetsIni%, %PresetName%
    if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd))
        GuiControl, Preset:, PresetName,
    AddLog("Пресет """ PresetName """ удалён")
    LoadPresetsList()
return

BtnPresetRefresh:
    LoadPresetsList()
return

LoadPresetsList() {
    global PresetsIni, PresetGuiHwnd
    if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd)) {
        GuiControl, Preset:, PresetList, |
    }
    if (!FileExist(PresetsIni))
        return
    FileRead, content, %PresetsIni%
    Loop, Parse, content, `n, `r
    {
        line := Trim(A_LoopField)
        if (line = "")
            continue
        if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
            name := Trim(SubStr(line, 2, -1))
            if (PresetGuiHwnd && DllCall("IsWindow", "ptr", PresetGuiHwnd))
                GuiControl, Preset:, PresetList, %name%
        }
    }
}

BtnPresetClose:
PresetGuiClose:
    Gui, Preset:Destroy
    PresetGuiHwnd := 0
return

; ===================== НАСТРОЙКИ АВТОПРОКАЧКИ =====================
AutoUpgradeToggle:
    ; AutoUpgradeEnabled уже обновлён через ProcessJSCmd ("toggle-autoupgrade")
return

BtnOpenAutoUpgradeSettings:
    if (AutoUpgradeGuiHwnd && DllCall("IsWindow", "ptr", AutoUpgradeGuiHwnd)) {
        Gui, AutoUpgrade:Show
        return
    }
    OpenAutoUpgradeSettingsGui()
return

OpenAutoUpgradeSettingsGui() {
    global AutoUpgradeGuiHwnd, AutoUpgradePriority
    global Priority1, Priority2, Priority3, Priority4, Priority5, Priority6
    Gui, AutoUpgrade:New, +HwndAutoUpgradeGuiHwnd, Настройки автопрокачки
    Gui, AutoUpgrade:Color, 0x1E1E1E
    Gui, AutoUpgrade:Font, s10 cE0E0E0, Segoe UI

    Gui, AutoUpgrade:Font, s10 c00CCFF Bold
    Gui, AutoUpgrade:Add, Text, x14 y14 w520 h24, Приоритет прокачки по слотам (кликов по AutoUpgrade)
    Gui, AutoUpgrade:Font, s10 cE0E0E0 Norm

    ; 6 полей для приоритета (1-6)
    loopX := 14
    Loop, 6 {
        Gui, AutoUpgrade:Add, Text, x%loopX% y48 w40 Center, Слот %A_Index%
        Gui, AutoUpgrade:Add, Edit, x%loopX% y68 w40 h22 Number Center vPriority%A_Index%, % AutoUpgradePriority[A_Index]
        loopX += 66
    }

    ; Смещение Y при выборе юнита
    Gui, AutoUpgrade:Add, Text, x14 y96 w310 h20, Смещение Y выбора юнита (пикс. вверх):
    Gui, AutoUpgrade:Add, Edit, x330 y94 w50 h22 Number vUnitOffsetY, %AutoUpgradeUnitOffsetY%

    ; Калибровка кнопки AutoUpgrade
    Gui, AutoUpgrade:Add, GroupBox, x14 y126 w550 h90, Калибровка кнопки AutoUpgrade
    Gui, AutoUpgrade:Add, Button, x34 y152 w200 h28 gBtnCaptureAutoUpgrade, Снять шаблон AutoUpgrade
    Gui, AutoUpgrade:Add, Button, x34 y182 w200 h28 gBtnTestAutoUpgrade, Проверить детект сейчас
    Gui, AutoUpgrade:Add, Text, x244 y158 w310 h40 c808080, Зажми и обведи кнопку AutoUpgrade. Сохранится как images\AutoUpgrade.bmp

    Gui, AutoUpgrade:Add, Button, x284 y230 w120 h28 gBtnAutoUpgradeSave, Сохранить и закрыть
    Gui, AutoUpgrade:Add, Button, x414 y230 w120 h28 gBtnAutoUpgradeClose, Отмена

    Gui, AutoUpgrade:Show, w580 h272, Настройки автопрокачки
}

BtnCaptureAutoUpgrade:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureForMarking(TempShot)
    MarkMode := "template"
    TemplateName := "AutoUpgrade"
    MarkList := []
    OpenMarkGui("Зажми кнопку мыши и обведи кнопку AutoUpgrade. Отпусти — шаблон сохранится как AutoUpgrade.bmp.")
return

BtnTestAutoUpgrade:
    global ImagesDir
    full := ImagesDir . "\AutoUpgrade.bmp"
    if !FileExist(full)
        full := ImagesDir . "\AutoUpgrade.png"
    if !FileExist(full) {
        AddLog("AutoUpgrade-шаблон отсутствует в images\ — сначала сними его.")
        return
    }
    if (IsTemplateTooBig(full)) {
        AddLog("AutoUpgrade-шаблон слишком большой — ImageSearch не найдёт. Сними шаблон поменьше.")
        return
    }
    if (FindGameButton(full, bx, by))
        AddLog("Проверка: AutoUpgrade найден на экране в (" bx "," by ") — детект будет работать!")
    else
        AddLog("Проверка: AutoUpgrade НЕ найден. Открой экран где видна кнопка AutoUpgrade.")
return

BtnAutoUpgradeSave:
    Gui, AutoUpgrade:Submit, NoHide
    Loop, 6 {
        val := Priority%A_Index%
        if val is integer
        {
            if (val < 0)
                val := 0
            if (val > 9)
                val := 9
        }
        else
            val := 1
        AutoUpgradePriority[A_Index] := val
    }
    ; Смещение Y
    if UnitOffsetY is integer
        AutoUpgradeUnitOffsetY := UnitOffsetY
    else
        AutoUpgradeUnitOffsetY := 20
    AddLog("Настройки автопрокачки сохранены: " AutoUpgradePriority[1] "-" AutoUpgradePriority[2] "-" AutoUpgradePriority[3] "-" AutoUpgradePriority[4] "-" AutoUpgradePriority[5] "-" AutoUpgradePriority[6] "  offset=" AutoUpgradeUnitOffsetY)
    Gui, AutoUpgrade:Destroy
    AutoUpgradeGuiHwnd := 0
return

BtnAutoUpgradeClose:
AutoUpgradeGuiClose:
    Gui, AutoUpgrade:Destroy
    AutoUpgradeGuiHwnd := 0
return

BtnCalibClose:
CalibGuiClose:
    Gui, Calib:Destroy
    CalibGuiHwnd := 0
return

; ===================== СТАРТ / СТОП ФАРМА =====================
BtnStartStop:
F9::
    if (SelectedMapCtl = "") {
        AddLog("Сначала выбери карту", "warn")
        WBH_CallJS("ahkUpdateStatus('Select a map', 'error')")
        return
    }
    if (!MapCoords.HasKey(SelectedMapCtl)) {
        AddLog("Нельзя запустить: """ SelectedMapCtl """ не размечена", "warn")
        WBH_CallJS("ahkUpdateStatus('Map not marked', 'error')")
        return
    }
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена", "warn")
        WBH_CallJS("ahkUpdateStatus('Game not found', 'error')")
        return
    }
    Running := !Running
    if (Running) {
        WBH_CallJS("ahkUpdateFarm(true)")
        AddLog("Старт фарма: " SelectedMapCtl)
        SetTimer, RunPlacementSequence, -100
    } else {
        WBH_CallJS("ahkUpdateFarm(false)")
        AddLog("Фарм остановлен")
        SetTimer, WatchNextStage, Off
    }
return

; ---- Плавное наведение мыши (без клика) ----
; Равномерное движение: 30 мелких шагов, скорость регулируется только
; паузой между шагами (MouseSpeed 0-100). Без рывков при любой скорости.
SmoothMove(x, y) {
    global MouseSpeed
    MouseGetPos, curX, curY
    steps := 30
    ; Пауза между шагами: 30 мс при скорости 10 (медленно),
    ; 1 мс при скорости 100 (быстро). MouseMove всегда мгновенный (0).
    stepSleep := 32 - MouseSpeed / 3
    if (stepSleep < 1)
        stepSleep := 1
    Loop, %steps% {
        t := A_Index / steps
        tx := curX + (x - curX) * t
        ty := curY + (y - curY) * t
        MouseMove, %tx%, %ty%, 0
        Sleep, %stepSleep%
    }
    MouseMove, %x%, %y%, 0
}

; ---- Плавный клик: наводит мышь и кликает ----
; Некоторые кнопки в игре не срабатывают при телепортации курсора
; (Click, X, Y двигает мгновенно). Нужно реальное наведение мыши.
SmoothClick(x, y, hoverMs := 150) {
    SmoothMove(x, y)
    Sleep, %hoverMs%
    Click
    Sleep, 20
}

; ---- Плавный клик с несколькими нажатиями ----
; Наводится, ждёт, нажимает 2-3 раза с паузой между кликами.
; Используется для кнопок Start Game / Repeat Stage — надёжнее.
SmoothClickMulti(x, y, count := 2, hoverMs := 200, betweenMs := 300) {
    SmoothMove(x, y)
    Sleep, %hoverMs%
    Loop, %count% {
        Click
        Sleep, %betweenMs%
    }
    Sleep, 20
}

; ---- Проверка: совпадает ли цвет с допуском (по каналам RGB) ----
IsColorMatch(col, target, var) {
    r1 := col >> 16 & 0xFF
    g1 := col >> 8 & 0xFF
    b1 := col & 0xFF
    r2 := target >> 16 & 0xFF
    g2 := target >> 8 & 0xFF
    b2 := target & 0xFF
    return (Abs(r1-r2) <= var && Abs(g1-g2) <= var && Abs(b1-b2) <= var)
}

; ---- Уводит мышь в сторону (сброс hover) ----
; Перед повторной попыткой клика уводим курсор в нейтральную точку
; (левый нижний угол GameArea), чтобы кнопка «отпустила» hover.
MoveMouseAway() {
    global GameAreaW, GameAreaH
    ToScreen(30, GameAreaH - 30)
    MouseMove, % TS_X, % TS_Y, 0
    Sleep, 400
}

; ---- Клик Start Game с повторными попытками ----
; Приоритет: 1) ImageSearch по шаблону StartGame.bmp (как Defeat/Victory);
; 2) калиброванные координаты + проверка цвета; 3) поиск по цвету (fallback).
ClickStartGameRetry() {
    global StartGameX, StartGameY, StartGameColor, StartGameColorVar, TS_X, TS_Y
    global Running, ImagesDir
    attempts := 3
    Loop, %attempts% {
        if (!Running)
            return
        clicked := false
        ; 1) ImageSearch по шаблону StartGame.bmp / StartGame.png (приоритет)
        full := ImagesDir . "\StartGame.bmp"
        if !FileExist(full)
            full := ImagesDir . "\StartGame.png"
        if (FileExist(full) && !IsTemplateTooBig(full)) {
            if (FindGameButton(full, btnX, btnY)) {
                SmoothClickMulti(btnX, btnY, 2, 200, 500)
                AddLog("Start Game: клик по шаблону (" btnX "," btnY "), попытка " A_Index "/" attempts)
                clicked := true
                Sleep, 1500
                ; Проверяем: кнопка исчезла? (шаблон больше не на экране)
                if (FindGameButton(full, bx, by)) {
                    AddLog("Start Game: кнопка ещё на экране (по шаблону), увожу мышь и повторяю...")
                } else {
                    AddLog("Start Game нажата: кнопка исчезла с экрана")
                    return
                }
            }
        }
        ; 2) Калиброванные координаты + проверка цвета (если шаблон не найден)
        if (!clicked && StartGameX > 0 && StartGameY > 0) {
            ToScreen(StartGameX, StartGameY)
            SmoothClickMulti(TS_X, TS_Y, 2, 200, 500)
            AddLog("Start Game: клик по координатам (" StartGameX "," StartGameY ") -> screen(" TS_X "," TS_Y "), попытка " A_Index "/" attempts)
            clicked := true
            Sleep, 1500
            PixelGetColor, col, %TS_X%, %TS_Y%, RGB
            if (StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
                if (!IsColorMatch(col, StartGameColor, StartGameColorVar + 30)) {
                    AddLog("Start Game нажата: кнопка исчезла с экрана")
                    return
                }
                AddLog("Start Game: кнопка ещё на экране (цвет " col "), увожу мышь и повторяю...")
            } else {
                ; Цвет не настроен — считаем, что клик прошёл
                return
            }
        }
        ; 3) Fallback: поиск по цвету (координат и шаблона нет)
        if (!clicked && StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
            if (FindGameButtonByColor(StartGameColor, StartGameColorVar, btnX, btnY)) {
                SmoothClickMulti(btnX, btnY, 2, 200, 500)
                AddLog("Start Game: клик по цвету (fallback) (" btnX "," btnY "), попытка " A_Index "/" attempts)
                clicked := true
                Sleep, 1500
                ; Цветной fallback без проверки — считаем успешным
                return
            }
        }
        if (!clicked) {
            AddLog("Start Game: кнопка не найдена (попытка " A_Index "/" attempts ")")
            return
        }
        ; Не нажалось — уводим мышь в сторону, чтобы сбросить hover
        MoveMouseAway()
    }
    AddLog("ВНИМАНИЕ: Start Game не нажалась за " attempts " попыток — пробую снова")
}

; ---- Разовая расстановка всех юнитов по размеченным слотам ----
RunPlacementSequence:
    slots := MapCoords[SelectedMapCtl]
    AddLog("Слотов загружено: " slots.Length() " для """ SelectedMapCtl """")
    ; Кликаем по центру области игры для фокуса
    ToScreen(640, 360)
    SmoothClick(TS_X, TS_Y, 200)
    for i, s in slots {
        if (!Running)
            break
        ; Порядок: сначала наводимся на место, ждём КД, потом выбираем юнита, потом ставим
        ToScreen(s.x, s.y)
        AddLog("Слот " i ": юнит " s.num " client(" s.x "," s.y ") -> screen(" TS_X "," TS_Y ")")
        SmoothMove(TS_X, TS_Y)
        Sleep, %HoverDelay%
        Send, % s.num
        Sleep, %ClickDelay%
        Click
        Sleep, %SlotClickDelay%
        AddLog("Юнит " s.num " поставлен (слот " i ")")
        Sleep, %UnitSleepDelay%
    }
    ; ---- Автопрокачка: после расстановки, если включена ----
    if (AutoUpgradeEnabled && Running) {
        AddLog("Автопрокачка: начинаю прокачку юнитов...")
        for i, s in slots {
            if (!Running)
                break
            priority := AutoUpgradePriority[s.num]
            if (priority <= 0)
                continue
            ; Кликаем чуть выше юнита чтобы выбрать его
            ToScreen(s.x, s.y - AutoUpgradeUnitOffsetY)
            SmoothClick(TS_X, TS_Y, 200)
            Sleep, 200
            ; Кликаем по кнопке AutoUpgrade priority раз
            Loop, %priority% {
                if (!Running)
                    break
                Gosub, DoAutoUpgradeClick
                Sleep, %AutoClickDelay%
            }
            AddLog("Автопрокачка: слот " i " (юнит " s.num ") — " priority " клик(ов)")
        }
        AddLog("Автопрокачка завершена")
    }
    if (Running) {
        WBH_CallJS("ahkUpdateStatus('Starting game...', 'running')")
        AddLog("Расстановка завершена, нажимаю Start Game...")
        ClickStartGameRetry()
        WBH_CallJS("ahkUpdateStatus('Watching...', 'running')")
        SetTimer, WatchNextStage, 1000
    }
return

; ---- Клик по кнопке AutoUpgrade (вызывается через Gosub) ----
DoAutoUpgradeClick:
    fullAU := ImagesDir . "\AutoUpgrade.bmp"
    if !FileExist(fullAU)
        fullAU := ImagesDir . "\AutoUpgrade.png"
    if (FileExist(fullAU) && !IsTemplateTooBig(fullAU)) {
        if (FindGameButton(fullAU, btnX, btnY)) {
            ; Клик по ЦЕНТРУ шаблона: читаем размеры BMP
            FileGetSize, tplSize, %fullAU%
            tplW := 0, tplH := 0
            if (tplSize > 26) {
                tplFile := FileOpen(fullAU, "r")
                if (tplFile) {
                    tplFile.Seek(18)
                    tplW := tplFile.ReadUInt()
                    tplFile.Seek(22)
                    tplH := tplFile.ReadUInt()
                    if (tplH > 0x7FFFFFFF)
                        tplH := 0x100000000 - tplH
                    tplFile.Close()
                }
            }
            if (tplW > 0 && tplH > 0)
                SmoothClick(btnX + tplW//2, btnY + tplH*2//5, 150)
            else
                SmoothClick(btnX, btnY, 150)
            return
        }
    }
    if (AutoX > 0 && AutoY > 0) {
        ToScreen(AutoX, AutoY)
        SmoothClick(TS_X, TS_Y, 150)
    }
return

; ---- Наблюдение за окончанием волны / победы / поражения ----
WatchNextStage:
    if !WinExist(WinTitle) {
        WBH_CallJS("ahkUpdateFarm(false)")
        WBH_CallJS("ahkUpdateStatus('Game lost', 'error')")
        AddLog("Окно Roblox пропало, остановка")
        SetTimer, WatchNextStage, Off
        Running := false
        return
    }
    ; 1) Проверяем поражение/победу — ищем Defeat / Victory
    if (DetectDefeat()) {
        AddLog("Обнаружено поражение! Кликаю Repeat Stage...")
        ClickRepeatStage()
        WBH_CallJS("ahkUpdateStatus('Defeat, restarting...', 'error')")
        Gosub, RestartFarmLoop
        return
    }
    if (DetectVictory()) {
        AddLog("Обнаружена победа! Кликаю Repeat Stage...")
        ClickRepeatStage()
        WBH_CallJS("ahkUpdateStatus('Victory, restarting...', 'running')")
        Gosub, RestartFarmLoop
        return
    }
    ; Next Stage — убран, автопрокачка работает вместо него
return

; ---- Бесконечный цикл: после победы/поражения всё заново ----
RestartFarmLoop:
    SetTimer, WatchNextStage, Off
    if (!Running)
        return
    WBH_CallJS("ahkUpdateStatus('Restarting stage...', 'running')")
    AddLog("Перезапуск этапа: жду загрузку, затем расстановка заново")
    Sleep, 4000
    if (Running)
        SetTimer, RunPlacementSequence, -100
return

; ---- Проверка: шаблон слишком большой для быстрого ImageSearch ----
; ImageSearch по шаблону > 300x300 в области 1280x720 занимает секунды
; и вешает GUI («не отвечает»). Такие шаблоны пропускаем.
IsTemplateTooBig(imageFile) {
    if !FileExist(imageFile)
        return false
    ; Читаем размеры из заголовка BMP/PNG
    file := FileOpen(imageFile, "r")
    if !file
        return false
    ; BMP: 'BM' + ... width @18, height @22
    file.Seek(0)
    b0 := file.ReadUChar()
    b1 := file.ReadUChar()
    if (b0 = 0x42 && b1 = 0x4D) {   ; 'BM'
        file.Seek(18)
        w := file.ReadUInt()
        file.Seek(22)
        hRaw := file.ReadUInt()
        h := hRaw
        if (h > 0x7FFFFFFF)   ; отрицательная высота = top-down
            h := 0x100000000 - hRaw
        file.Close()
        return (w > 300 || h > 300)
    }
    ; PNG: 89 50 4E 47 + width @16 (big-endian), height @20
    ; (без битовых сдвигов — в AHK v1 << 24 может дать знаковое число)
    if (b0 = 0x89 && b1 = 0x50) {
        file.Seek(16)
        w := file.ReadUChar()*16777216 + file.ReadUChar()*65536 + file.ReadUChar()*256 + file.ReadUChar()
        file.Seek(20)
        h := file.ReadUChar()*16777216 + file.ReadUChar()*65536 + file.ReadUChar()*256 + file.ReadUChar()
        file.Close()
        return (w > 300 || h > 300)
    }
    file.Close()
    return false
}

; ---- Детект поражения (Defeat) — ищет Defeat.png или Defeat.bmp ----
DetectDefeat() {
    global Embedded, ImagesDir
    if (!Embedded)
        return false
    full := ImagesDir . "\Defeat.bmp"
    if !FileExist(full)
        full := ImagesDir . "\Defeat.png"
    if (FileExist(full)) {
        if (IsTemplateTooBig(full)) {
            static warnedDefeat := false
            if (!warnedDefeat) {
                warnedDefeat := true
                AddLog("Defeat-шаблон слишком большой — ImageSearch вешает макрос. Сними маленький шаблон (Калибровка → Снять шаблон, имя Defeat).")
            }
            return false
        }
        if (FindGameButton(full, bx, by))
            return true
    }
    return false
}

; ---- Детект победы (Victory) — ищет Victory.png или Victory.bmp ----
DetectVictory() {
    global Embedded, ImagesDir
    if (!Embedded)
        return false
    full := ImagesDir . "\Victory.bmp"
    if !FileExist(full)
        full := ImagesDir . "\Victory.png"
    if (FileExist(full)) {
        if (IsTemplateTooBig(full)) {
            static warnedVictory := false
            if (!warnedVictory) {
                warnedVictory := true
                AddLog("Victory-шаблон слишком большой — ImageSearch вешает макрос. Сними маленький шаблон (Калибровка → Снять шаблон, имя Victory).")
            }
            return false
        }
        if (FindGameButton(full, bx, by))
            return true
    }
    return false
}

; ---- Клик по кнопке Repeat Stage ----
; Кликает (координаты → изображение → цвет), ждёт и проверяет, исчез ли
; экран победы/поражения. Если нет — повторяет (до 3 попыток).
ClickRepeatStage() {
    global RepeatStageX, RepeatStageY, ImagesDir, ImgVariation, StartGameColor, StartGameColorVar
    global MainGuiHwnd, TS_X, TS_Y
    global Running
    attempts := 3
    Loop, %attempts% {
        if (!Running)
            return
        clicked := false
        ; 1) Калиброванные координаты — приоритет (быстро, без ImageSearch)
        if (RepeatStageX > 0 && RepeatStageY > 0) {
            ToScreen(RepeatStageX, RepeatStageY)
            SmoothClickMulti(TS_X, TS_Y, 2, 200, 400)
            AddLog("Repeat Stage: клик по экрану (" TS_X "," TS_Y "), попытка " A_Index)
            clicked := true
        }
        ; 2) ImageSearch по RepeatStage.bmp / RepeatStage.png
        if (!clicked) {
            full := ImagesDir . "\RepeatStage.bmp"
            if !FileExist(full)
                full := ImagesDir . "\RepeatStage.png"
            if (FileExist(full)) {
                if (FindGameButton(full, bx, by)) {
                    SmoothClickMulti(bx, by, 2, 200, 400)
                    AddLog("Repeat Stage нажата по поиску изображения (" bx "," by "), попытка " A_Index)
                    clicked := true
                }
            }
        }
        ; 3) Fallback: ищем по цвету StartGame
        if (!clicked && StartGameColor != 0 && StartGameColor != "0x000000" && StartGameColor != "") {
            if (FindGameButtonByColor(StartGameColor, StartGameColorVar, bx, by)) {
                SmoothClickMulti(bx, by, 2, 200, 400)
                AddLog("Повторить по цвету StartGame (fallback), попытка " A_Index)
                clicked := true
            }
        }
        if (!clicked) {
            AddLog("Repeat Stage: кнопка не найдена (попытка " A_Index ")")
            return
        }
        ; Ждём и проверяем: экран победы/поражения исчез?
        Sleep, 2000
        if (!DetectVictory() && !DetectDefeat()) {
            AddLog("Repeat Stage нажата: экран закрыт")
            return
        }
        AddLog("Repeat Stage: экран ещё на месте, увожу мышь и повторяю...")
        ; Не нажалось — уводим мышь в сторону, чтобы сбросить hover
        MoveMouseAway()
	}
	AddLog("ВНИМАНИЕ: Repeat Stage не нажалась за " attempts " попыток")
}

; ===================== HTML ↔ AHK BRIDGE =====================

; ---- Выполнить JavaScript в HTML-панели ----
WBH_CallJS(js) {
    global WB
    if (!WB || WB.ReadyState != 4)
        return
    try {
        WB.Document.parentWindow.execScript(js)
    } catch e {
        ; HTML-панель может быть не готова
    }
}

; ---- Таймер: опрос команд от JS (каждые 150 мс) ----
PollJSCmd:
    if (!WB || WB.ReadyState != 4)
        return
    cmd := ""
    try {
        cmd := WB.Document.parentWindow.ahkCmd
        if (cmd && cmd != "")
            WB.Document.parentWindow.ahkCmd := ""
    } catch e {
        return
    }
    if (cmd && cmd != "")
        ProcessJSCmd(cmd)
return

; ---- Обработка команд, пришедших из HTML ----
ProcessJSCmd(cmd) {
    global SelectedMapCtl, AutoUpgradeEnabled, Running, WB
    
    ; Разбираем команду: "command" или "command/arg"
    slashPos := InStr(cmd, "/")
    if (slashPos) {
        action := SubStr(cmd, 1, slashPos - 1)
        arg := SubStr(cmd, slashPos + 1)
    } else {
        action := cmd
        arg := ""
    }
    
    if (action = "embed") {
        Gosub, BtnEmbed
        return
    }
    if (action = "start-farm") {
        Gosub, BtnStartStop
        return
    }
    if (action = "select-map") {
        if (arg = "__none__")
            SelectedMapCtl := ""
        else
            SelectedMapCtl := arg
        Gosub, MapChanged
        return
    }
    if (action = "snapshot") {
        Gosub, BtnCaptureMap
        return
    }
    if (action = "mark-slots") {
        Gosub, BtnMarkSlots
        return
    }
    if (action = "clear-map") {
        Gosub, BtnClearMap
        return
    }
    if (action = "toggle-autoupgrade") {
        AutoUpgradeEnabled := !AutoUpgradeEnabled
        WBH_CallJS("document.getElementById('chkAutoUpgrade').checked = " . (AutoUpgradeEnabled ? "true" : "false") . ";")
        if (AutoUpgradeEnabled)
            AddLog("Auto Upgrade: ON")
        else
            AddLog("Auto Upgrade: OFF")
        return
    }
    if (action = "settings") {
        OpenModalWindow("settings", "Settings", 480, 530)
        return
    }
    if (action = "presets") {
        OpenModalWindow("presets", "Presets", 440, 370)
        return
    }
    if (action = "calibrate") {
        OpenModalWindow("calibrate", "Calibration", 440, 420)
        return
    }
    if (action = "upgrade-cfg") {
        OpenModalWindow("upgrade", "Auto Upgrade", 360, 320)
        return
    }
    if (action = "clear-log") {
        WBH_CallJS("ahkClearLog()")
        return
    }
    if (action = "minimize-main") {
        Gui, Minimize
        return
    }
    if (action = "close-main") {
        Gosub, GuiClose
        return
    }
    if (InStr(cmd, "drag-start-main/")) {
        params := SubStr(cmd, 17)
        slashPos := InStr(params, "/")
        if (slashPos) {
            sx := SubStr(params, 1, slashPos - 1)
            sy := SubStr(params, slashPos + 1)
            DoNativeDrag(sx, sy)
        }
        return
    }
    if (InStr(cmd, "drag-start-modal/")) {
        params := SubStr(cmd, 18)
        slashPos := InStr(params, "/")
        if (slashPos) {
            sx := SubStr(params, 1, slashPos - 1)
            sy := SubStr(params, slashPos + 1)
            DoNativeDragModal(sx, sy)
        }
        return
    }
}

; ---- Отправка начального состояния в HTML ----
PushStateToHTML:
    global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    global Embedded, Running, AutoUpgradeEnabled, MapList
    
    ; Сообщаем JS что мы в AHK-режиме (не standalone браузер)
    WBH_CallJS("ahkSetMode()")
    
    if (Embedded)
        WBH_CallJS("ahkUpdateEmbed(true)")
    
    ; Карты
    if (MapList.Length() > 0) {
        mapOpts := ""
        for i, m in MapList
            mapOpts .= (i > 1 ? "|" : "") . m
        WBH_CallJS("ahkSetMapOptions(""" . mapOpts . """)")
    }
    
    ; Координаты
    upStr := "Up(" . UpgradeX . "," . UpgradeY . ")"
    stStr := "Start(" . StartGameX . "," . StartGameY . ")"
    rpStr := "Repeat(" . RepeatStageX . "," . RepeatStageY . ")"
    auStr := "Auto(" . AutoX . "," . AutoY . ")"
    WBH_CallJS("ahkUpdateCoords(""" . upStr . """,""" . stStr . """,""" . rpStr . """,""" . auStr . """)")
    
    ; Автопрокачка
    if (AutoUpgradeEnabled)
        WBH_CallJS("document.getElementById('chkAutoUpgrade').checked = true;")
    
    AddLog("HTML sidebar loaded — bridge active", "success")
return

; ---- Обновление координат в HTML (вызывается после калибровки) ----
UpdateCoordsHTML() {
    global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
    upStr := "Up(" . UpgradeX . "," . UpgradeY . ")"
    stStr := "Start(" . StartGameX . "," . StartGameY . ")"
    rpStr := "Repeat(" . RepeatStageX . "," . RepeatStageY . ")"
    auStr := "Auto(" . AutoX . "," . AutoY . ")"
    WBH_CallJS("ahkUpdateCoords(""" . upStr . """,""" . stStr . """,""" . rpStr . """,""" . auStr . """)")
}

; ---- Обновление списка карт в HTML ----
UpdateMapListHTML() {
    global MapList
    if (MapList.Length() > 0) {
        mapOpts := ""
        for i, m in MapList
            mapOpts .= (i > 1 ? "|" : "") . m
        WBH_CallJS("ahkSetMapOptions(""" . mapOpts . """)")
    }
}

; ===================== MODAL WINDOWS (HTML sub-windows) =====================

; ---- Открыть модальное окно с HTML-дизайном ----
; name: "settings" / "presets" / "calibrate" / "upgrade"
; title: заголовок окна
; w, h: размеры окна
OpenModalWindow(name, title, w, h) {
    global htmlURL, WB_Modal, ModalHwnd
    
    ; Закрываем предыдущее модальное окно если открыто
    Gui, Modal:Destroy
    SetTimer, PollModalClose, Off
    
    ; Создаём окно без стандартного title bar (кастомный хотбар в HTML)
    Gui, Modal:New, +HwndModalHwnd -Caption, %title%
    Gui, Modal:Color, 0x121212
    Gui, Modal:Add, ActiveX, x0 y0 w%w% h%h% vWB_Modal, Shell.Explorer
    WB_Modal.Silent := true
    navURL := htmlURL . "?_=" . A_TickCount . "#" . name
    WB_Modal.Navigate(navURL)
    
    ; Ждём загрузки
    waitStart := A_TickCount
    while (WB_Modal.ReadyState != 4 && A_TickCount - waitStart < 10000)
        Sleep, 80
    
    ; Пушим данные в модалку (текущие настройки / список пресетов / координаты)
    PushModalData(name)
    
    ; Центрируем окно на экране
    SysGet, Mon, MonitorWorkArea
    cx := (MonRight - MonLeft - w) // 2
    cy := (MonTop - MonTop + MonBottom - MonTop - h) // 2
    if (cx < 0)
        cx := 100
    if (cy < 0)
        cy := 100
    
    Gui, Modal:Show, x%cx% y%cy% w%w% h%h%, %title%
    
    ; Таймер для опроса JS-команд (закрыть, свернуть, драг)
    SetTimer, PollModalClose, 20
}

; ---- Таймер: проверяем команды от JS (закрыть, свернуть, переместить) ----
PollModalClose:
    if (!WB_Modal || WB_Modal.ReadyState != 4)
        return
    cmd := ""
    try {
        cmd := WB_Modal.Document.parentWindow.ahkCmd
        if (cmd && cmd != "")
            WB_Modal.Document.parentWindow.ahkCmd := ""
    } catch e {
        return
    }
    if (cmd = "")
        return
    
    ; Разбор команды: "action" или "action/arg"
    slashPos := InStr(cmd, "/")
    if (slashPos) {
        action := SubStr(cmd, 1, slashPos - 1)
        arg := SubStr(cmd, slashPos + 1)
    } else {
        action := cmd
        arg := ""
    }
    
    if (cmd = "close-modal") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
    }
    else if (cmd = "minimize-modal") {
        Gui, Modal:Minimize
    }
    else if (InStr(cmd, "drag-start-modal/")) {
        params := SubStr(cmd, 18)
        slashPos := InStr(params, "/")
        if (slashPos) {
            DoNativeDragModal(SubStr(params, 1, slashPos - 1), SubStr(params, slashPos + 1))
        }
    }
    
    ; ---- Новые команды от модалок ----
    else if (action = "settings-save") {
        GoSub, ModalSaveSettings
    }
    else if (action = "preset-save") {
        PresetName := arg
        GoSub, BtnPresetSave
        PushModalData("presets")
    }
    else if (action = "preset-load") {
        PresetName := arg
        GoSub, BtnPresetLoad
        PushModalData("presets")
    }
    else if (action = "preset-delete") {
        PresetName := arg
        GoSub, BtnPresetDelete
        PushModalData("presets")
    }
    else if (action = "calibrate-upgrade") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCalibrateUpgrade
    }
    else if (action = "calibrate-startgame") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCalibrateStartGame
    }
    else if (action = "calibrate-repeatstage") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnCalibrateRepeatStage
    }
    else if (action = "calibrate-autoupgrade") {
        SetTimer, PollModalClose, Off
        Gui, Modal:Destroy
        ModalHwnd := 0
        GoSub, BtnOpenAutoUpgradeSettings
    }
    else if (action = "upgrade-save") {
        GoSub, ModalSaveUpgrade
    }
return

; ---- Закрытие модалки через ✕ (крестик окна) ----
ModalGuiClose:
    SetTimer, PollModalClose, Off
    Gui, Modal:Destroy
    ModalHwnd := 0
return

; ---- Вызов JS в модальном окне ----
ModalCallJS(js) {
    global WB_Modal
    if (!WB_Modal || WB_Modal.ReadyState != 4)
        return
    try {
        WB_Modal.Document.parentWindow.execScript(js)
    } catch e {
        AddLog("Modal JS error: " . e.Message)
    }
}

; ---- Пуш данных в модальное окно после загрузки ----
PushModalData(name) {
    global
    if (name = "settings") {
        colorHex := SubStr(StartGameColor, 3)  ; убираем "0x"
        ModalCallJS("ahkLoadSettings("
            . ClickDelay . "," . SlotClickDelay . "," . UpgradeClickDelay . ","
            . AutoClickDelay . "," . UnitSleepDelay . "," . StartGameDelay . ","
            . HoverDelay . "," . MouseSpeed . "," . ImgVariation . ",'"
            . colorHex . "'," . StartGameColorVar . ","
            . StartGameCenterX . "," . StartGameCenterY . "," . StartGameRadius . ")")
    }
    else if (name = "presets") {
        ; Собираем список пресетов из presets.ini
        presetsList := ""
        if (FileExist(PresetsIni)) {
            FileRead, content, %PresetsIni%
            Loop, Parse, content, `n, `r
            {
                line := Trim(A_LoopField)
                if (line = "")
                    continue
                if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
                    if (presetsList != "")
                        presetsList .= "|"
                    presetsList .= Trim(SubStr(line, 2, -1))
                }
            }
        }
        ModalCallJS("ahkLoadPresets('" . presetsList . "')")
    }
    else if (name = "calibrate") {
        ModalCallJS("ahkUpdateCalibCoords("
            . UpgradeX . "," . UpgradeY . ","
            . StartGameX . "," . StartGameY . ","
            . RepeatStageX . "," . RepeatStageY . ","
            . AutoX . "," . AutoY . ")")
    }
    else if (name = "upgrade") {
        prioStr := ""
        Loop, 6 {
            if (A_Index > 1)
                prioStr .= ","
            prioStr .= AutoUpgradePriority[A_Index]
        }
        ModalCallJS("ahkLoadUpgradeCfg('" . prioStr . "'," . AutoUpgradeUnitOffsetY . ")")
    }
}

; ---- Сохранение настроек из модального окна Settings ----
ModalSaveSettings:
    ; arg = clickDelay/slotClickDelay/upgradeClickDelay/autoClickDelay/unitSleepDelay/startGameDelay/hoverDelay/mouseSpeed/imgVariation/startGameColor/startGameColorVar/startGameCenterX/startGameCenterY/startGameRadius
    StringSplit, vals, arg, /
    if (vals0 < 14)
        return
    ClickDelay        := vals1
    SlotClickDelay    := vals2
    UpgradeClickDelay := vals3
    AutoClickDelay    := vals4
    UnitSleepDelay    := vals5
    StartGameDelay    := vals6
    HoverDelay        := vals7
    MouseSpeed        := vals8
    ImgVariation      := vals9
    StartGameColor    := "0x" . vals10
    StartGameColorVar := vals11
    StartGameCenterX  := vals12
    StartGameCenterY  := vals13
    StartGameRadius   := vals14
    SaveSettings()
    AddLog("Settings saved from modal")
return

; ---- Сохранение настроек автопрокачки из модального окна ----
ModalSaveUpgrade:
    ; arg = p1,p2,p3,p4,p5,p6/offset
    secondSlash := InStr(arg, "/", , 0)
    if (!secondSlash)
        return
    prioPart := SubStr(arg, 1, secondSlash - 1)
    offsetPart := SubStr(arg, secondSlash + 1)
    StringSplit, prio, prioPart, `,
    Loop, 6 {
        val := prio%A_Index%
        if (val = "" || val < 0)
            val := 0
        if (val > 9)
            val := 9
        AutoUpgradePriority[A_Index] := val
    }
    AutoUpgradeUnitOffsetY := offsetPart
    AddLog("Auto Upgrade settings saved from modal")
return

; ---- Нативный драг главного окна (цикл в AHK, без JS/COM) ----
DoNativeDrag(startMX, startMY) {
    global MainGuiHwnd
    wid := MainGuiHwnd
    DllCall("ReleaseCapture")
    SendMessage, 0xA1, 2, 0,, ahk_id %wid%
    DllCall("ReleaseCapture")
}

DoNativeDragModal(startMX, startMY) {
    global ModalHwnd
    if (!ModalHwnd)
        return
    wid := ModalHwnd
    DllCall("ReleaseCapture")
    SendMessage, 0xA1, 2, 0,, ahk_id %wid%
    DllCall("ReleaseCapture")
}

GuiClose:
    if (Embedded)
        UnembedGameWindow()
    ExitApp