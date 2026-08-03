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

; ---- drag-select для захвата шаблонов ----
DragActive := false
DragStartSX := 0, DragStartSY := 0
DragCurSX := 0, DragCurSY := 0
DragPrevRect := ""
DragOverlayHwnd := 0

; Обработчики мыши: только для MarkMode = "template" (drag-select области)
; Также через этот же хук перетаскивается окно за кастомную тёмную шапку
; (см. TitleBarBgHwnd/TitleBarTextHwnd и OnTitleBarLButtonDown в drag_select.ahk).
OnMessage(0x201, "OnTemplateLButtonDown")   ; WM_LBUTTONDOWN
OnMessage(0x200, "OnTemplateMouseMove")       ; WM_MOUSEMOVE
OnMessage(0x202, "OnTemplateLButtonUp")       ; WM_LBUTTONUP
; =======================================================

TotalW := GameAreaW + SidebarW
TitleBarH := 32
TotalH := GameAreaH + 40 + TitleBarH

LoadConfig()
LoadSettings()
ReloadMapList()
LoadAllMapCoords()

; ===================== GUI (тёмная тема) =====================
; -Caption убирает системную (белую/светлую) шапку окна — вместо неё
; ниже рисуется собственная тёмная шапка (TitleBar*), чтобы весь
; интерфейс, включая рамку окна, был в едином тёмном стиле.
Gui, +HwndMainGuiHwnd -Caption +Border
Gui, Color, 0x1E1E1E, 0x252526
Gui, Font, s10 cE0E0E0, Segoe UI

; ---- Собственная тёмная шапка окна (замена системной) ----
; Цвет 0x1E1E1E — тот же фон, что у окна и сайдбара (единый тёмный стиль,
; а не "накладная" полоска другого оттенка), + тонкая линия-разделитель снизу.
Gui, Add, Text, x0 y0 w%TotalW% h%TitleBarH% vTitleBarBg gTitleBarDrag Background1E1E1E,
TitleBarLineY := TitleBarH - 1
Gui, Add, Text, x0 y%TitleBarLineY% w%TotalW% h1 Background2E2E2E,
Gui, Font, s10 cE0E0E0 Bold, Segoe UI
Gui, Add, Text, x14 y0 w300 h%TitleBarH% vTitleBarText gTitleBarDrag BackgroundTrans, TD MACRO CONTROL
; ---- Кнопки свернуть/закрыть: СВОЙ фон (не Trans!) ----
; BackgroundTrans в AHK означает WS_EX_TRANSPARENT — контрол становится
; "прозрачным для кликов", то есть клик проваливается сквозь него на то,
; что находится ПОД ним (тут — TitleBarBg с gTitleBarDrag). Именно поэтому
; свернуть/закрыть не работали: клик всегда попадал в обработчик
; перетаскивания окна, а не в свою метку. Даём кнопкам собственный
; непрозрачный фон чуть светлее шапки — заодно они выглядят как настоящие
; кнопки, а не как случайные символы поверх фона.
Gui, Font, s13 cE0E0E0 Norm, Segoe UI
TbMinX := TotalW - 84
TbCloseX := TotalW - 42
Gui, Add, Text, x%TbMinX% y0 w42 h%TitleBarH% vTitleBarMin gTitleBarMin Center Background2A2A2A, −
Gui, Add, Text, x%TbCloseX% y0 w42 h%TitleBarH% vTitleBarClose gTitleBarClose Center Background2A2A2A, ×
Gui, Font, s10 cE0E0E0 Norm, Segoe UI
GuiControlGet, TitleBarBgHwnd, Hwnd, TitleBarBg
GuiControlGet, TitleBarTextHwnd, Hwnd, TitleBarText
GuiControlGet, TitleBarMinHwnd, Hwnd, TitleBarMin
GuiControlGet, TitleBarCloseHwnd, Hwnd, TitleBarClose

GameAreaY := TitleBarH
GameAreaBottomY := GameAreaY + GameAreaH
Gui, Add, Text, x0 y%GameAreaY% w%GameAreaW% h%GameAreaH% vGameArea 0x201 Border BackgroundBlack,
Gui, Add, Text, x0 y%GameAreaBottomY% w%GameAreaW% h40 c808080 Center 0x201, Область встраивания Roblox — нажми "Встроить" справа

SbX := GameAreaW + 12

; ---- Принудительный IE11-режим для WebBrowser ----
RegWrite, REG_DWORD, HKCU, Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION, AutoHotkey.exe, 11001
RegWrite, REG_DWORD, HKCU, Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION, AutoHotkeyU32.exe, 11001
RegWrite, REG_DWORD, HKCU, Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION, AutoHotkeyU64.exe, 11001
RegWrite, REG_DWORD, HKCU, Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION, AutoHotkeyA32.exe, 11001

; ---- WebBrowser (боковая панель — загружает UI/index.html) ----
SidebarH := TotalH - TitleBarH
Gui, Add, ActiveX, x%SbX% y%TitleBarH% w%SidebarW% h%SidebarH% vWb, Shell.Explorer
uiHtml := A_ScriptDir . "\..\UI\index.html"
Loop, Files, %uiHtml%, F
    uiReal := A_LoopFileLongPath
if (uiReal = "")
    uiReal := uiHtml
uiUrl := "file:///" . StrReplace(uiReal, "\", "/")
Wb.Navigate(uiUrl)
ComObjConnect(Wb, "Wb_")

Gui, Show, w%TotalW% h%TotalH%, TD Macro Control
return

; ===================== Тёмная шапка: drag + свернуть/закрыть =====================
; Пустая метка: реальное перетаскивание окна обрабатывается раньше,
; через OnMessage(WM_LBUTTONDOWN) в OnTemplateLButtonDown (drag_select.ahk).
; Но g-label обязана указывать на существующую метку, иначе AHK
; выдаёт ошибку загрузки скрипта ("Target label does not exist") —
; именно это и произошло.
TitleBarDrag:
return

TitleBarMin:
    Gui, Minimize
return

TitleBarClose:
    Gosub, GuiClose
return

; ===================== МОСТ JS -> AHK =====================
Wb_BeforeNavigate2(pDisp, url, flags, targetFrame, postData, headers, cancel) {
    global SelectedMapCtl, AutoUpgradeEnabled, Running
    if (!InStr(url, "ahk://"))
        return
    try cancel[] := -1
    rest := SubStr(url, 8)
    slashPos := InStr(rest, "/")
    if (!slashPos)
        return
    action := SubStr(rest, 1, slashPos - 1)
    ; JS шлёт payload через encodeURIComponent(JSON.stringify(...)) — обязательно
    ; декодировать проценты, иначе ExtractJsonStr ищет `"key":"` в строке вида
    ; %7B%22key%22... и ничего не находит (баг: выбор карты/имя слота не доходили до AHK).
    payload := UrlDecode(SubStr(rest, slashPos + 1))

    ; Оборачиваем в try/catch: ComObjConnect по умолчанию МОЛЧА глотает
    ; любую ошибку внутри обработчика события — если в GoSub ниже что-то
    ; упадёт (например, окно Настроек/Пресетов/Калибровки), снаружи не будет
    ; видно вообще ничего, кнопка в сайдбаре просто "не сработает" без следа.
    ; Теперь любая такая ошибка попадёт в лог.
    try {
        ; ВАЖНО: GoSub напрямую здесь работал ненадёжно для меток, которые
        ; создают НОВОЕ Gui-окно (Settings/Preset/Calib/Mark/AutoUpgrade) —
        ; они выполнялись синхронно ВНУТРИ COM-события BeforeNavigate2
        ; ActiveX-браузера. AutoHotkey в этой ситуации может "создать" окно,
        ; но не прорисовать его и не дать ему фокус — выглядит так, будто
        ; клик вообще ничего не сделал, хотя ошибки нет и в лог нечего писать.
        ; SetTimer с отрицательной задержкой откладывает выполнение метки на
        ; 10мс — уже ПОСЛЕ выхода из COM-колбэка, там создание окна работает
        ; штатно. Задержка не заметна на глаз, но чинит открытие всех окон.
        if (action = "embed")
            SetTimer, BtnEmbed, -10
        else if (action = "start")
            SetTimer, BtnStartStop, -10
        else if (action = "captureMap")
            SetTimer, BtnCaptureMap, -10
        else if (action = "markSlots")
            SetTimer, BtnMarkSlots, -10
        else if (action = "clearMap")
            SetTimer, BtnClearMap, -10
        else if (action = "openAutoUpgradeSettings")
            SetTimer, BtnOpenAutoUpgradeSettings, -10
        else if (action = "openSettings")
            SetTimer, BtnSettings, -10
        else if (action = "openPresets")
            SetTimer, BtnOpenPresets, -10
        else if (action = "openCalibration")
            SetTimer, BtnOpenCalibration, -10
        else if (action = "selectMap")
        {
            name := ExtractJsonStr(payload, "name")
            if (name != "")
                SelectedMapCtl := name
        }
        else if (action = "autoUpgradeToggle")
        {
            AutoUpgradeEnabled := (InStr(payload, "true") ? true : false)
        }
    } catch e {
        errMsg := "ОШИБКА в обработчике '" action "': " (IsObject(e) ? e.Message : e)
        AddLog(errMsg)
        try WbSend("log", "{msg:'" EscapeJs(errMsg) "',type:'error'}")
    }
}

; ---- Декодирование percent-encoding (encodeURIComponent) ----
UrlDecode(s) {
    out := ""
    i := 1
    len := StrLen(s)
    while (i <= len) {
        c := SubStr(s, i, 1)
        if (c = "%" && i + 2 <= len) {
            hex := SubStr(s, i + 1, 2)
            if hex is xdigit
            {
                out .= Chr("0x" . hex)
                i += 3
                continue
            }
        }
        if (c = "+") {
            out .= " "
            i += 1
            continue
        }
        out .= c
        i += 1
    }
    return out
}

ExtractJsonStr(json, key) {
    pos := InStr(json, """" key """:""")
    if (!pos)
        return ""
    pos += StrLen(key) + 4
    end := InStr(json, """", false, pos)
    if (!end)
        return ""
    return SubStr(json, pos, end - pos)
}

; ===================== МОСТ AHK -> JS =====================
WbSend(action, data := "") {
    global Wb
    try {
        js := "window.uiBridge('" action "', " (data = "" ? "{}" : data) ")"
        Wb.Document.parentWindow.execScript(js)
    }
}
WbUi(key, value) {
    global Wb
    try Wb.Document.parentWindow.execScript("window.uiBridge('setUi',{key:'" EscapeJs(key) "',value:'" EscapeJs(value) "'})")
}
WbMaps() {
    global Wb, MapList
    json := "["
    for i, m in MapList
        json .= (i>1 ? "," : "") . "'" . EscapeJs(m) . "'"
    json .= "]"
    try Wb.Document.parentWindow.execScript("window.uiBridge('setMaps',{maps:" json ",select:'" EscapeJs(MapList.Length()>0 ? MapList[1] : "") "'})")
}
Wb_DocumentComplete(pDisp, url) {
    global Wb
    WbMaps()
    WbUi("windowStatus", "не проверено")
    WbUi("offsetStatus", "Up(0,0) Auto(0,0) Start(0,0) Repeat(0,0)")
}
EscapeJs(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, """", "\""")
    s := StrReplace(s, "'", "\'")
    s := StrReplace(s, "`r`n", "\n")
    s := StrReplace(s, "`r", "\n")
    s := StrReplace(s, "`n", "\n")
    return s
}

; ===================== ЛОГ (перенаправлен в JS) =====================
AddLog(msg) {
    FormatTime, ts,, HH:mm:ss
    line := "[" ts "] " msg
    try Wb.Document.parentWindow.execScript("window.uiBridge('log',{msg:'" EscapeJs(line) "'})")
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

; Перестроение выпадающего списка карт в GUI (с сохранением выбора).
RefreshMapDropdown() {
    global MapList, SelectedMapCtl
    if (MapList.Length() > 0) {
        listStr := JoinArr(MapList, "|")
        found := false
        for i, m in MapList {
            if (m = SelectedMapCtl) {
                found := true
                break
            }
        }
        GuiControl, , SelectedMapCtl, %listStr%
        if (found)
            GuiControl, ChooseString, SelectedMapCtl, %SelectedMapCtl%
        else
            GuiControl, Choose, SelectedMapCtl, 1
        Gui, Submit, NoHide
    } else {
        ; Список пуст — в DropDownList нельзя ставить пустую строку, ставим заглушку
        GuiControl, , SelectedMapCtl, |
        SelectedMapCtl := ""
    }
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
    ; x,y приходят как координаты ВНУТРИ игровой области (0,0 = её левый
    ; верхний угол). Игровая область теперь начинается не с самого верха
    ; клиентской области окна, а ниже кастомной тёмной шапки — прибавляем
    ; GameAreaY, чтобы клики по-прежнему попадали в нужное место экрана.
    global MainGuiHwnd, GameAreaY, TS_X, TS_Y
    if (!MainGuiHwnd || !DllCall("IsWindow", "ptr", MainGuiHwnd)) {
        AddLog("ToScreen: MainGuiHwnd некорректен (" MainGuiHwnd ")")
        TS_X := x
        TS_Y := y
        return
    }
    VarSetCapacity(pt, 8, 0)
    NumPut(x, pt, 0, "Int")
    NumPut(y + GameAreaY, pt, 4, "Int")
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
    global MainGuiHwnd, GameAreaW, GameAreaH, GameAreaY, ImgVariation
    if (!MainGuiHwnd || !DllCall("IsWindow", "ptr", MainGuiHwnd))
        return false
    VarSetCapacity(pt, 8, 0)
    NumPut(0, pt, 0, "Int")
    NumPut(GameAreaY, pt, 4, "Int")
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
    global MainGuiHwnd, GameAreaY, StartGameCenterX, StartGameCenterY, StartGameRadius
    if (!MainGuiHwnd || !DllCall("IsWindow", "ptr", MainGuiHwnd))
        return false
    VarSetCapacity(pt, 8, 0)
    NumPut(StartGameCenterX, pt, 0, "Int")
    NumPut(StartGameCenterY + GameAreaY, pt, 4, "Int")
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
    global MainGuiHwnd, GameAreaW, GameAreaH, GameAreaY
    ; GameArea всегда в левом верхнем углу главного окна (x0, y=GameAreaY —
    ; ниже кастомной тёмной шапки), размер GameAreaW x GameAreaH.
    ; GuiControlGet здесь НЕ использовать: при вызове из окна калибровки
    ; он ищет GameArea в чужом окне и возвращает нулевые размеры →
    ; битый файл → чёрный экран.
    VarSetCapacity(pt, 8, 0)
    NumPut(0, pt, 0, "Int")
    NumPut(GameAreaY, pt, 4, "Int")
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
        GuiControl,, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ")"
        AddLog("Калибровка Upgrade сохранена: (" UpgradeX "," UpgradeY ")")
    } else if (MarkMode = "abs_startgame") {
        SaveConfig()
        GuiControl,, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ") Repeat(" RepeatStageX "," RepeatStageY ")"
        AddLog("Калибровка Start Game сохранена: (" StartGameX "," StartGameY ")")
    } else if (MarkMode = "abs_repeatstage") {
        SaveConfig()
        GuiControl,, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ") Repeat(" RepeatStageX "," RepeatStageY ")"
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
    WinActivate, Настройки
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
        WinActivate, ahk_id %PresetGuiHwnd%
        return
    }
    OpenPresetsGui()
return

OpenPresetsGui() {
    global PresetGuiHwnd
    Gui, Preset:New, +HwndPresetGuiHwnd, Пресеты
    Gui, Preset:Color, 0x1E1E1E, 0x252526
    Gui, Preset:Font, s10 cE0E0E0, Segoe UI

    Gui, Preset:Font, s10 c00CCFF Bold, Segoe UI
    Gui, Preset:Add, Text, x14 y14 w620 h24, Пресеты — полная конфигурация
    Gui, Preset:Font, s10 cE0E0E0, Segoe UI

    ; ---- имя пресета + действия ----
    Gui, Preset:Add, Text, x14 y54 w260, Имя пресета:
    Gui, Preset:Add, Edit, x204 y50 w260 h22 vPresetName,
    Gui, Preset:Add, Button, x484 y50 w160 h26 gBtnPresetSave, Сохранить пресет

    ; ---- список пресетов ----
    Gui, Preset:Add, Text, x14 y90 w260, Список пресетов:
    Gui, Preset:Add, ListBox, x204 y86 w260 h150 vPresetList gPresetSelect,
    Gui, Preset:Add, Button, x484 y86 w160 h26 gBtnPresetLoad, Загрузить пресет
    Gui, Preset:Add, Button, x484 y120 w160 h26 gBtnPresetDelete, Удалить пресет
    Gui, Preset:Add, Button, x484 y154 w160 h26 gBtnPresetRefresh, Обновить список

    ; ---- подсказка о составе ----
    Gui, Preset:Font, s8 c808080 Italic, Segoe UI
    Gui, Preset:Add, Text, x14 y252 w620 h40, Пресет включает ВСЁ: координаты кнопок (Upgrade/Auto/StartGame/RepeatStage), задержки, параметры ImageSearch/PixelSearch и слоты всех карт (расположение юнитов). При загрузке пресет сразу применяется и записывается в config.ini, settings.ini и maps\*_slots.ini.
    Gui, Preset:Font, s10 cE0E0E0 Norm, Segoe UI

    Gui, Preset:Add, Button, x484 y300 w160 h28 gBtnPresetClose, Закрыть

    Gui, Preset:Show, w668 h344, Пресеты
    WinActivate, Пресеты
    LoadPresetsList()
}

; ===================== КАЛИБРОВКА (отдельное окно) =====================
BtnOpenCalibration:
    if (CalibGuiHwnd && DllCall("IsWindow", "ptr", CalibGuiHwnd)) {
        Gui, Calib:Show
        WinActivate, ahk_id %CalibGuiHwnd%
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
    WinActivate, Калибровка координат
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
    Gui, Preset:Submit, NoHide
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
    Gui, Preset:Submit, NoHide
    Gui, Preset:Default
    if (PresetName = "") {
        GuiControlGet, sel, , PresetList
        if (sel = "") {
            MsgBox, 48, Ошибка, Выбери пресет из списка или введи имя.
            return
        }
        PresetName := sel
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
    Gui, 1:Default
    RefreshMapDropdown()
    GuiControl, 1:, OffsetStatus, % "Up(" UpgradeX "," UpgradeY ") Auto(" AutoX "," AutoY ") Start(" StartGameX "," StartGameY ") Repeat(" RepeatStageX "," RepeatStageY ")"
    UpdateCalibStatus()
    AddLog("Пресет """ PresetName """ загружен (координаты + настройки + слоты карт применены и записаны на диск)")
return

BtnPresetDelete:
    Gui, Preset:Submit, NoHide
    Gui, Preset:Default
    if (PresetName = "") {
        GuiControlGet, sel, , PresetList
        if (sel = "") {
            MsgBox, 48, Ошибка, Введи или выбери имя пресета для удаления.
            return
        }
        PresetName := sel
    }
    IniDelete, %PresetsIni%, %PresetName%
    GuiControl, Preset:, PresetName,
    AddLog("Пресет """ PresetName """ удалён")
    LoadPresetsList()
return

BtnPresetRefresh:
    LoadPresetsList()
return

LoadPresetsList() {
    global PresetsIni
    GuiControl, Preset:, PresetList, |
    if (!FileExist(PresetsIni))
        return
    FileRead, content, %PresetsIni%
    Loop, Parse, content, `n, `r
    {
        line := A_LoopField
        if (SubStr(line, 1, 1) = "[" && SubStr(line, 0, 1) = "]") {
            name := Trim(SubStr(line, 2, -1))
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
    Gui, 1:Submit, NoHide
    ; Галочка уже обновила AutoUpgradeEnabled, больше ничего не нужно
return

BtnOpenAutoUpgradeSettings:
    if (AutoUpgradeGuiHwnd && DllCall("IsWindow", "ptr", AutoUpgradeGuiHwnd)) {
        Gui, AutoUpgrade:Show
        WinActivate, ahk_id %AutoUpgradeGuiHwnd%
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
    WinActivate, Настройки автопрокачки
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
        GuiControl,, FarmStatus, Статус: расстановка завершена, нажимаю Start Game...
        AddLog("Расстановка завершена, нажимаю Start Game...")
        ClickStartGameRetry()
        GuiControl,, FarmStatus, Статус: игра запущена, наблюдение
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
        GuiControl,, FarmStatus, Статус: окно игры потеряно
        AddLog("Окно Roblox пропало, остановка")
        SetTimer, WatchNextStage, Off
        Running := false
        GuiControl,, StartStopBtn, Старт (F9)
        return
    }
    ; 1) Проверяем поражение/победу — ищем Defeat / Victory
    if (DetectDefeat()) {
        AddLog("Обнаружено поражение! Кликаю Repeat Stage...")
        ClickRepeatStage()
        GuiControl,, FarmStatus, Статус: поражение, перезапуск...
        Gosub, RestartFarmLoop
        return
    }
    if (DetectVictory()) {
        AddLog("Обнаружена победа! Кликаю Repeat Stage...")
        ClickRepeatStage()
        GuiControl,, FarmStatus, Статус: победа, перезапуск...
        Gosub, RestartFarmLoop
        return
    }
    ; Next Stage — убран, автопрокачка работает вместо него
return

; ---- Бесконечный цикл: после победы/поражения всё заново ----
; Выключаем наблюдение, ждём перезагрузку этапа, заново расставляем
; юнитов (RunPlacementSequence сам нажмёт Start Game и включит наблюдение).
RestartFarmLoop:
    SetTimer, WatchNextStage, Off
    if (!Running)
        return
    GuiControl,, FarmStatus, Статус: перезапуск этапа...
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

GuiClose:
    if (Embedded)
        UnembedGameWindow()
    ExitApp