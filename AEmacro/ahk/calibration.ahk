; ═══════════════════════════════════════════════════════════
;  calibration.ahk  —  Комплексный интерфейс калибровки
;  Отдельный файл для калибровки:
;    • Upgrade
;    • AutoUpgrade
;    • Start Game
;    • Repeat Stage  (после поражения / кнопка "повторить")
;  Поддерживает пресеты: Save / Load / Delete в ahk\presets.ini
;  Координаты по умолчанию сохраняются в корневой config.ini
;  (секция [Buttons])
; ═══════════════════════════════════════════════════════════

#SingleInstance Force
#NoEnv
#Utf8
SetWorkingDir, %A_ScriptDir%\..   ; <- корень проекта (родитель ahk)

; ---- пути ----
ConfigIni  := A_ScriptDir "\..\config.ini"
PresetsIni := A_ScriptDir "\presets.ini"
MapsDir    := A_ScriptDir "\..\maps"
ImagesDir  := A_ScriptDir "\..\images"

; ---- параметры игрового окна ----
GameAreaW := 1280
GameAreaH := 720
WinTitle  := "ahk_exe RobloxPlayerBeta.exe"

; ---- текущие координаты (будут перезаписаны из config.ini) ----
UpgradeX := 0, UpgradeY := 0
AutoX := 0, AutoY := 0
StartGameX := 0, StartGameY := 0
RepeatStageX := 0, RepeatStageY := 0

; ---- состояние ----
TempShot     := A_ScriptDir "\..\_preview.bmp"
MarkMode     := ""
MarkList     := []
MarkGuiHwnd  := 0
Embedded     := false

; ---- переменные для GUI ----
PresetName := ""

; =================================================================
if !FileExist(MapsDir)
   FileCreateDir, %MapsDir%
if !FileExist(ImagesDir)
   FileCreateDir, %ImagesDir%

LoadConfig()
LoadPresetsList()

; ── главное окно ──
Gui, +HwndMainGuiHwnd
Gui, Color, 0x1E1E1E, 0x252526
Gui, Font, s10 cE0E0E0, Segoe UI

; ---- заголовок ----
Gui, Add, Text, x14 y14 w520 h24 c00CCFF Bold, Калибровка координат кнопок TD

; ---- статус встраивания ----
Gui, Add, Button, x14 y44 w200 h30 gBtnEmbed, Встроить Roblox сюда
Gui, Add, Text, x220 y50 w380 vWindowStatus, Статус: не проверено

; ---- группа: калибровка кнопок ----
Gui, Add, GroupBox, x14 y84 w640 h140, Калибровка кнопок
Gui, Add, Button, x34 y114 w160 h28 gBtnCalibrateUpgrade, Калибровать Upgrade
Gui, Add, Button, x204 y114 w160 h28 gBtnCalibrateAuto, Калибровать AutoUpgrade
Gui, Add, Button, x374 y114 w160 h28 gBtnCalibrateStartGame, Калибровать Start Game
Gui, Add, Button, x34 y148 w160 h28 gBtnCalibrateRepeat, Калибровать RepeatStage
Gui, Add, Button, x204 y148 w160 h28 gBtnSnapshot, Снимок экрана
Gui, Add, Text, x34 y182 w600 h20 vOffsetStatus, % StatusText()

; ---- группа: пресеты ----
Gui, Add, GroupBox, x14 y234 w640 h120, Пресеты координат
Gui, Add, Text, x34 y256 w260, Имя пресета:
Gui, Add, Edit, x304 y256 w180 h20 vPresetName, default
Gui, Add, Button, x494 y256 w140 h26 gBtnSavePreset, Сохранить пресет
Gui, Add, Button, x494 y286 w140 h26 gBtnLoadPreset, Загрузить пресет
Gui, Add, Button, x494 y316 w140 h26 gBtnDeletePreset, Удалить пресет
Gui, Add, Text, x34 y286 w260, Список пресетов:
Gui, Add, ListBox, x304 y282 w180 h60 vPresetList,
Gui, Add, Button, x34 y316 w140 h26 gBtnRefreshPresets, Обновить список

; ---- группа: экспорт / импорт ----
Gui, Add, GroupBox, x14 y364 w640 h80, Экспорт / импорт
Gui, Add, Button, x34 y390 w140 h28 gBtnSaveConfig, Сохранить в config.ini
Gui, Add, Button, x184 y390 w140 h28 gBtnLoadConfig, Загрузить из config.ini
Gui, Add, Button, x334 y390 w140 h28 gBtnOpenPresets, Открыть папку с пресетами
Gui, Add, Button, x484 y390 w140 h28 gBtnExit, Закрыть

Gui, Show, w664 h460, Калибровка координат кнопок TD
return

; =================================================================
BtnExit:
GuiClose:
   if (Embedded)
      UnembedGameWindow()
   ExitApp

; =================================================================
StatusText() {
   global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
   return "Up(" UpgradeX "," UpgradeY ")  Auto(" AutoX "," AutoY ")  Start(" StartGameX "," StartGameY ")  Repeat(" RepeatStageX "," RepeatStageY ")"
}

; =================================================================
BtnEmbed:
   global Embedded, GameHwnd, OrigStyle, OrigExStyle, OrigParent
   if (!WinExist(WinTitle)) {
      GuiControl,, WindowStatus, Статус: игра не найдена
      return
   }
   GameHwnd := WinExist(WinTitle)
   WinGet, OrigStyle, Style, ahk_id %GameHwnd%
   WinGet, OrigExStyle, ExStyle, ahk_id %GameHwnd%
   OrigParent := DllCall("GetParent", "ptr", GameHwnd, "ptr")
   ; в этом окне нет GameArea (игра встраивается в Roblox напрямую)
   DllCall("SetParent", "ptr", GameHwnd, "ptr", MainGuiHwnd)
   WinMove, ahk_id %GameHwnd%,, 0, 0, %GameAreaW%, %GameAreaH%
   Sleep, 150
   GetClientSize(GameHwnd, RealW, RealH)
   Embedded := true
   GuiControl,, WindowStatus, % "Статус: встроено " RealW "x" RealH
return

UnembedGameWindow() {
   global GameHwnd, OrigStyle, OrigExStyle, OrigParent, Embedded
   if (!GameHwnd || !WinExist("ahk_id " . GameHwnd))
      return
   DllCall("SetParent", "ptr", GameHwnd, "ptr", OrigParent)
   WinSet, Style, %OrigStyle%, ahk_id %GameHwnd%
   WinSet, ExStyle, %OrigExStyle%, ahk_id %GameHwnd%
   WinMove, ahk_id %GameHwnd%,, 100, 100, 1280, 720
   Embedded := false
   GuiControl,, WindowStatus, Статус: возвращено в обычный режим
}

; =================================================================
; ── вспомогательные функции для захвата экрана ──
ToScreen(x, y) {
   global MainGuiHwnd
   if (!MainGuiHwnd || !DllCall("IsWindow", "ptr", MainGuiHwnd)) {
      TS_X := x, TS_Y := y
      return
   }
   VarSetCapacity(pt, 8, 0)
   NumPut(x, pt, 0, "Int")
   NumPut(y, pt, 4, "Int")
   DllCall("ClientToScreen", "ptr", MainGuiHwnd, "ptr", &pt)
   global TS_X, TS_Y
   TS_X := NumGet(pt, 0, "Int")
   TS_Y := NumGet(pt, 4, "Int")
}

GetClientSize(hwnd, ByRef cw, ByRef ch) {
   VarSetCapacity(rect, 16, 0)
   DllCall("GetClientRect", "ptr", hwnd, "ptr", &rect)
   cw := NumGet(rect, 8, "Int")
   ch := NumGet(rect, 12, "Int")
}

CaptureScreenshot(x, y, w, h, filepath) {
   hDesktopDC := DllCall("GetDC", "ptr", 0, "ptr")
   hCaptureDC := DllCall("CreateCompatibleDC", "ptr", hDesktopDC, "ptr")
   hBitmap    := DllCall("CreateCompatibleBitmap", "ptr", hDesktopDC, "int", w, "int", h, "ptr")
   hOld       := DllCall("SelectObject", "ptr", hCaptureDC, "ptr", hBitmap, "ptr")
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
   stride := ((w * 3 + 3) // 4) * 4
   imageSize := stride * h
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

; =================================================================
; ── захват игровой области в TempShot ──
BtnSnapshot:
   if (!Embedded) {
      MsgBox, 48, Ошибка, Сначала встройте Roblox.
      return
   }
   CaptureGameArea(TempShot)
   Gui, Snap:New, , Снимок карты — превью
   Gui, Snap:Color, 0x1E1E1E
   Gui, Snap:Font, s10 cE0E0E0, Segoe UI
   Gui, Snap:Add, Picture, x10 y10 w640 h360, %TempShot%
   Gui, Snap:Add, Button, x10 y380 w310 h34 gSnapConfirm, Подтвердить снимок
   Gui, Snap:Add, Button, x340 y380 w310 h34 gSnapCancel, Отмена
   Gui, Snap:Show, w660 h424, Снимок карты — превью
return

CaptureGameArea(filepath) {
   global MainGuiHwnd, GameAreaW, GameAreaH
   ToScreen(0, 0)
   CaptureScreenshot(TS_X, TS_Y, GameAreaW, GameAreaH, filepath)
}

SnapConfirm:
   Gui, Snap:Destroy
   InputBox, ShotName, Название, Введи имя для снимка (например: FlowerForest_start), , 300, 140
   if (ErrorLevel || ShotName = "") {
      if (!ErrorLevel)
         MsgBox, Снимок не сохранён: имя пусто.
      return
   }
   FinalPath := MapsDir "\" ShotName ".bmp"
   FileCopy, %TempShot%, %FinalPath%, 1
return

SnapCancel:
   Gui, Snap:Destroy
return

; =================================================================
; ── калибровка кнопок ──
StartCalibration(btnName) {
   global TempShot, MarkMode
   if (!Embedded) {
      MsgBox, 48, Ошибка, Сначала встройте Roblox.
      return
   }
   CaptureGameArea(TempShot)
   MarkMode := btnName
   OpenMarkGui("Кликни на кнопку " btnName)
}

BtnCalibrateUpgrade:
   StartCalibration("Upgrade")
return
BtnCalibrateAuto:
   StartCalibration("AutoUpgrade")
return
BtnCalibrateStartGame:
   StartCalibration("StartGame")
return
BtnCalibrateRepeat:
   StartCalibration("RepeatStage")
return

OpenMarkGui(promptText) {
   global TempShot, MarkPrompt, MarkPic, MarkListBox, MarkGuiHwnd
   Gui, Mark:New, +HwndMarkGuiHwnd, Разметка
   Gui, Mark:Color, 0x1E1E1E
   Gui, Mark:Font, s10 cE0E0E0, Segoe UI
   Gui, Mark:Add, Text, x10 y10 w1280 vMarkPrompt, %promptText%
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
   if (!MarkGuiHwnd)
      return
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
      MsgBox, 48, Ошибка, Клик мимо картинки, попробуйте снова.
      return
   }
   ApplyCalibration(MarkMode, px, py)
return

ApplyCalibration(btnName, px, py) {
   global UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
   if (btnName = "Upgrade") {
      UpgradeX := px, UpgradeY := py
      GuiControl, Mark:, MarkListBox, % "Upgrade: (" px "," py ")"
   } else if (btnName = "AutoUpgrade") {
      AutoX := px, AutoY := py
      GuiControl, Mark:, MarkListBox, % "AutoUpgrade: (" px "," py ")"
   } else if (btnName = "StartGame") {
      StartGameX := px, StartGameY := py
      GuiControl, Mark:, MarkListBox, % "Start Game: (" px "," py ")"
   } else if (btnName = "RepeatStage") {
      RepeatStageX := px, RepeatStageY := py
      GuiControl, Mark:, MarkListBox, % "RepeatStage: (" px "," py ")"
   }
   GuiControl, Mark:, MarkPrompt, Готово — нажми "Готово / Сохранить"
}

MarkUndo:
   GuiControl, Mark:, MarkListBox, |
   GuiControl, Mark:, MarkPrompt, Кликни на нужную кнопку
return

MarkDone:
   Gui, 1:Default
   MarkMode := ""
   Gui, Mark:Destroy
   GuiControl,, OffsetStatus, % StatusText()
return

MarkCancel:
   MarkMode := ""
   Gui, Mark:Destroy
return

; =================================================================
; ── сохранение / загрузка config.ini ──
BtnSaveConfig:
   SaveConfig()
   AddLogLocal("Координаты сохранены в config.ini")
return

BtnLoadConfig:
   LoadConfig()
   GuiControl,, OffsetStatus, % StatusText()
   AddLogLocal("Координаты загружены из config.ini")
return

LoadConfig() {
   global ConfigIni, UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
   if (!FileExist(ConfigIni))
      return
   IniRead, v, %ConfigIni%, Buttons, UpgradeX, %UpgradeX%
   UpgradeX := v
   IniRead, v, %ConfigIni%, Buttons, UpgradeY, %UpgradeY%
   UpgradeY := v
   IniRead, v, %ConfigIni%, Buttons, AutoX, %AutoX%
   AutoX := v
   IniRead, v, %ConfigIni%, Buttons, AutoY, %AutoY%
   AutoY := v
   IniRead, v, %ConfigIni%, Buttons, StartGameX, %StartGameX%
   StartGameX := v
   IniRead, v, %ConfigIni%, Buttons, StartGameY, %StartGameY%
   StartGameY := v
   IniRead, v, %ConfigIni%, Buttons, RepeatStageX, %RepeatStageX%
   RepeatStageX := v
   IniRead, v, %ConfigIni%, Buttons, RepeatStageY, %RepeatStageY%
   RepeatStageY := v
}

SaveConfig() {
   global ConfigIni, UpgradeX, UpgradeY, AutoX, AutoY, StartGameX, StartGameY, RepeatStageX, RepeatStageY
   IniWrite, %UpgradeX%,    %ConfigIni%, Buttons, UpgradeX
   IniWrite, %UpgradeY%,    %ConfigIni%, Buttons, UpgradeY
   IniWrite, %AutoX%,       %ConfigIni%, Buttons, AutoX
   IniWrite, %AutoY%,       %ConfigIni%, Buttons, AutoY
   IniWrite, %StartGameX%,  %ConfigIni%, Buttons, StartGameX
   IniWrite, %StartGameY%,  %ConfigIni%, Buttons, StartGameY
   IniWrite, %RepeatStageX%, %ConfigIni%, Buttons, RepeatStageX
   IniWrite, %RepeatStageY%, %ConfigIni%, Buttons, RepeatStageY
}

; =================================================================
; ── пресеты (ahk\presets.ini) ──
BtnSavePreset:
   Gui, Submit, NoHide
   if (PresetName = "") {
      MsgBox, 48, Ошибка, Введи имя пресета.
      return
   }
   IniWrite, %UpgradeX%,    %PresetsIni%, %PresetName%, UpgradeX
   IniWrite, %UpgradeY%,    %PresetsIni%, %PresetName%, UpgradeY
   IniWrite, %AutoX%,       %PresetsIni%, %PresetName%, AutoX
   IniWrite, %AutoY%,       %PresetsIni%, %PresetName%, AutoY
   IniWrite, %StartGameX%,  %PresetsIni%, %PresetName%, StartGameX
   IniWrite, %StartGameY%,  %PresetsIni%, %PresetName%, StartGameY
   IniWrite, %RepeatStageX%, %PresetsIni%, %PresetName%, RepeatStageX
   IniWrite, %RepeatStageY%, %PresetsIni%, %PresetName%, RepeatStageY
   AddLogLocal("Пресет """ PresetName """ сохранён")
   LoadPresetsList()
return

BtnLoadPreset:
   Gui, Submit, NoHide
   if (PresetName = "") {
      GuiControlGet, PresetName, , PresetList
      if (PresetName = "") {
         MsgBox, 48, Ошибка, Выбери пресет из списка.
         return
      }
   }
   if (!IniReadExist(PresetsIni, PresetName)) {
      MsgBox, 48, Ошибка, Пресет """ PresetName """ не найден.
      return
   }
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
   GuiControl,, OffsetStatus, % StatusText()
   AddLogLocal("Пресет """ PresetName """ загружен")
return

BtnDeletePreset:
   Gui, Submit, NoHide
   if (PresetName = "") {
      GuiControlGet, PresetName, , PresetList
   }
   if (PresetName = "") {
      MsgBox, 48, Ошибка, Введи или выбери имя пресета для удаления.
      return
   }
   IniDelete, %PresetsIni%, %PresetName%
   AddLogLocal("Пресет """ PresetName """ удалён")
   LoadPresetsList()
return

BtnRefreshPresets:
   LoadPresetsList()
return

LoadPresetsList() {
   global PresetList, PresetsIni
   GuiControl,, PresetList, |
   
   if (!FileExist(PresetsIni))
      return
   
   ; Читаем все секции из presets.ini, игнорируя [Presets]
   FileRead, content, %PresetsIni%
   if (ErrorLevel)
      return
   
   Loop, Parse, content, `n, `r {
      line := A_LoopField
      ; Проверяем, является ли строка заголовком секции [SectionName]
      if (RegExMatch(line, "^\s*\[([^\]]+)\]\s*$", match)) {
         name := Trim(match1)
         if (name != "Presets" && name != "") {
            GuiControl, ChooseString, PresetList, %name%
         }
      }
   }
}

; упрощённая проверка наличия секции (для AHK используем IniRead с default-значением)
IniReadExist(iniFile, section) {
   IniRead, v, %iniFile%, %section%, UpgradeX, __NONE__
   return (v != "__NONE__")
}

; =================================================================
BtnOpenPresets:
   Run, % "explorer.exe " A_ScriptDir
return

; =================================================================
; ── простой лог в консоль (для отладки) ──
AddLogLocal(msg) {
   Gui, 1:Default
   GuiControlGet, cur,, OffsetStatus
   FormatTime, ts,, HH:mm:ss
   GuiControl,, OffsetStatus, % "[" ts "] " msg
}
