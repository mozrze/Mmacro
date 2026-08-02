#SingleInstance Force
#NoEnv
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Screen
CoordMode, Pixel, Window
DetectHiddenWindows, On
SendMode, Input

; ===================== НАСТРОЙКИ =====================
WinTitle := "ahk_exe RobloxPlayerBeta.exe"
GameAreaW := 1280
GameAreaH := 720
SidebarW  := 320

MapsDir := A_ScriptDir . "\maps"
ConfigFile := A_ScriptDir . "\config.ini"
TempShot := A_ScriptDir . "\_preview.bmp"
IfNotExist, %MapsDir%
    FileCreateDir, %MapsDir%

MapList := ["Flower Forest", "Fairy King Forest", "King's Tomb", "Rose Kingdom", "School Grounds"]
MapCoords := {}   ; MapCoords[map] := [{num,x,y}, ...]

; Абсолютные координаты кнопок Upgrade/AutoUpgrade на экране.
; Задаются ОДИН РАЗ на всю игру, по одному клику на кнопку.
UpgradeX := 0
UpgradeY := 0
AutoX := 0
AutoY := 0

Running := false
Embedded := false
GameHwnd := 0
OrigStyle := 0
OrigExStyle := 0
OrigParent := 0

; ---- состояние окна разметки/калибровки ----
MarkMode := ""     ; "slots" | "offset"
MarkList := []
; =======================================================

TotalW := GameAreaW + SidebarW
TotalH := GameAreaH + 40

LoadConfig()
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
Gui, Add, Button, x%SbX% y244 w137 h26 gBtnCalibrateUpgrade, Калибровка Upgrade
Gui, Add, Button, x%SbX2% y244 w137 h26 gBtnCalibrateAuto, Калибровка AutoUpgrade
Gui, Add, Button, x%SbX% y274 w280 h24 gBtnClearMap, Очистить разметку карты
Gui, Add, Text, x%SbX% y302 w280 h16 vOffsetStatus c808080, % "Upgrade(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ")"

Gui, Add, Text, x%SbX% y324 w280 c00CCFF, ФАРМ
Gui, Add, Button, x%SbX% y344 w280 h34 gBtnStartStop vStartStopBtn, Старт (F9)
Gui, Add, CheckBox, x%SbX% y386 w280 h20 vAutoNextStage cE0E0E0, Авто-следующая волна
Gui, Add, Text, x%SbX% y412 w280 h20 vFarmStatus c808080, Статус: остановлен

Gui, Add, Text, x%SbX% y442 w280 c00CCFF, ЛОГ
Gui, Add, Edit, x%SbX% y462 w280 h214 vLogBox ReadOnly -WantReturn Background151515 cB0B0B0,

Gui, Show, w%TotalW% h%TotalH%, TD Macro Control
return

; ===================== ЛОГ =====================
AddLog(msg) {
    GuiControlGet, cur,, LogBox
    FormatTime, ts,, HH:mm:ss
    new := "[" ts "] " msg "`r`n" cur
    GuiControl,, LogBox, %new%
}

; ===================== КОНФИГ (глобальные оффсеты) =====================
LoadConfig() {
    global ConfigFile, UpgradeX, UpgradeY, AutoX, AutoY
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
}

SaveConfig() {
    global ConfigFile, UpgradeX, UpgradeY, AutoX, AutoY
    IniWrite, %UpgradeX%, %ConfigFile%, Buttons, UpgradeX
    IniWrite, %UpgradeY%, %ConfigFile%, Buttons, UpgradeY
    IniWrite, %AutoX%, %ConfigFile%, Buttons, AutoX
    IniWrite, %AutoY%, %ConfigFile%, Buttons, AutoY
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
; Переводит координаты, сохранённые относительно области GameArea (0..1280, 0..720),
; в реальные экранные координаты — не зависит от того, какое окно сейчас активно.
; Результат кладётся в глобальные TS_X / TS_Y (тот же паттерн, что и в CaptureGameArea).
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

; ===================== СНИМОК КАРТЫ (сохранение как файл) =====================
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

; ===================== РАЗМЕТКА СЛОТОВ КАРТЫ (1 клик = 1 слот) =====================
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

; ===================== КАЛИБРОВКА UPGRADE (один раз на игру, независимо от AutoUpgrade) =====================
BtnCalibrateUpgrade:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureGameArea(TempShot)
    MarkMode := "abs_upgrade"
    OpenMarkGui("Кликни на кнопку Upgrade")
return

; ===================== КАЛИБРОВКА AUTOUPGRADE (один раз на игру, независимо от Upgrade) =====================
BtnCalibrateAuto:
    if !WinExist(WinTitle) {
        AddLog("Игра не найдена — сначала встрой Roblox")
        return
    }
    CaptureGameArea(TempShot)
    MarkMode := "abs_auto"
    OpenMarkGui("Кликни на кнопку AutoUpgrade")
return

OpenMarkGui(promptText) {
    global TempShot, MarkPrompt, MarkPic, MarkListBox
    Gui, Mark:New, , Разметка
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
    px := A_GuiX
    py := A_GuiY

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
    }
return

MarkDone:
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
        GuiControl,, OffsetStatus, % "Upgrade(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ")"
        AddLog("Калибровка Upgrade сохранена: (" UpgradeX "," UpgradeY ")")
    } else if (MarkMode = "abs_auto") {
        SaveConfig()
        GuiControl,, OffsetStatus, % "Upgrade(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ")"
        AddLog("Калибровка AutoUpgrade сохранена: (" AutoX "," AutoY ")")
    }
    MarkMode := ""
    Gui, Mark:Destroy
return

MarkCancel:
    MarkMode := ""
    AddLog("Разметка/калибровка отменена пользователем")
    Gui, Mark:Destroy
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
    for i, s in slots {
        if (!Running)
            break
        Send, % s.num
        Sleep, 80
        ToScreen(s.x, s.y)
        AddLog("Placement slot: client(" s.x "," s.y ") -> screen(" TS_X "," TS_Y ")")
        MouseMove, % TS_X, % TS_Y, 0
        Click
        Sleep, 250

        ToScreen(UpgradeX, UpgradeY)
        MouseMove, % TS_X, % TS_Y, 0
        Click
        Sleep, 150

        ToScreen(AutoX, AutoY)
        Loop, 6 {
            MouseMove, % TS_X, % TS_Y, 0
            Click
            Sleep, 120
        }
        AddLog("Юнит " s.num " поставлен и настроена автопрокачка (слот " i ")")
        Sleep, 200
    }
    if (Running) {
        GuiControl,, FarmStatus, Статус: расстановка завершена, наблюдение
        AddLog("Расстановка завершена")
        SetTimer, WatchNextStage, 1000
    }
return

; ---- Наблюдение за окончанием волны / следующей картой (заготовка) ----
WatchNextStage:
    if !WinExist(WinTitle) {
        GuiControl,, FarmStatus, Статус: окно игры потеряно
        AddLog("Окно Roblox пропало, остановка")
        SetTimer, WatchNextStage, Off
        Running := false
        GuiControl,, StartStopBtn, Старт (F9)
        return
    }
    ; TODO: проверка окончания волны / клик Next Stage при включенном AutoNextStage
return

GuiClose:
    if (Embedded)
        UnembedGameWindow()
    ExitApp
