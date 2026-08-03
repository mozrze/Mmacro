ShowDragRect(drx1, dry1, drx2, dry2) {
    global DragOverlayHwnd
    if (drx1 > drx2) {
        t := drx1
        drx1 := drx2
        drx2 := t
    }
    if (dry1 > dry2) {
        t := dry1
        dry1 := dry2
        dry2 := t
    }
    w := drx2 - drx1
    h := dry2 - dry1
    if (w < 2 && h < 2)
        return
    if (!DragOverlayHwnd || !DllCall("IsWindow", "ptr", DragOverlayHwnd)) {
        Gui, DragRect:New, +HwndDragOverlayHwnd -Caption +ToolWindow +AlwaysOnTop +E0x20
        Gui, DragRect:Color, FF0000
        Gui, DragRect:Show, x%drx1% y%dry1% w%w% h%h% NoActivate
        WinSet, Transparent, 100, ahk_id %DragOverlayHwnd%
    }
    WinMove, ahk_id %DragOverlayHwnd%,, %drx1%, %dry1%, %w%, %h%
}

HideDragRect() {
    global DragOverlayHwnd
    if (DragOverlayHwnd && DllCall("IsWindow", "ptr", DragOverlayHwnd)) {
        Gui, DragRect:Destroy
        DragOverlayHwnd := 0
    }
}

OnTemplateLButtonDown(wParam, lParam, msg, hwnd) {
    global MarkMode, MarkGuiHwnd, DragActive, DragStartSX, DragStartSY, DragCurSX, DragCurSY, DragPrevRect
    global MainGuiHwnd, TitleBarBgHwnd, TitleBarTextHwnd
    ; ---- Перетаскивание окна за кастомную тёмную шапку (нет системной Caption) ----
    if (hwnd = TitleBarBgHwnd || hwnd = TitleBarTextHwnd) {
        DllCall("ReleaseCapture")
        PostMessage, 0xA1, 2, 0,, ahk_id %MainGuiHwnd%   ; WM_NCLBUTTONDOWN, HTCAPTION
        return
    }
    if (MarkMode != "template" || !MarkGuiHwnd)
        return
    GuiControlGet, picHwnd, Mark:Hwnd, MarkPic
    if (hwnd != picHwnd)
        return
    CoordMode, Mouse, Screen
    MouseGetPos, sx, sy
    VarSetCapacity(mpt, 8, 0)
    NumPut(sx, mpt, 0, "Int")
    NumPut(sy, mpt, 4, "Int")
    DllCall("ScreenToClient", "ptr", MarkGuiHwnd, "ptr", &mpt)
    wx := NumGet(mpt, 0, "Int")
    wy := NumGet(mpt, 4, "Int")
    if (wx < 10 || wy < 36 || wx > 1290 || wy > 756)
        return
    DragActive := true
    DragStartSX := sx
    DragStartSY := sy
    DragCurSX := sx
    DragCurSY := sy
    DragPrevRect := ""
    return 1
}

OnTemplateMouseMove(wParam, lParam, msg, hwnd) {
    global DragActive, DragStartSX, DragStartSY, DragCurSX, DragCurSY, DragPrevRect
    if (!DragActive)
        return
    CoordMode, Mouse, Screen
    MouseGetPos, sx, sy
    if (sx = DragCurSX && sy = DragCurSY)
        return
    ShowDragRect(DragStartSX, DragStartSY, sx, sy)
    DragCurSX := sx
    DragCurSY := sy
    DragPrevRect := DragStartSX "," DragStartSY "," sx "," sy
}

OnTemplateLButtonUp(wParam, lParam, msg, hwnd) {
    global DragActive, DragStartSX, DragStartSY, DragCurSX, DragCurSY, DragPrevRect
    global MarkGuiHwnd, MarkMode, MarkList, CalibGuiHwnd
    if (!DragActive)
        return
    DragActive := false
    HideDragRect()
    CoordMode, Mouse, Screen
    MouseGetPos, sx, sy
    VarSetCapacity(mpt, 8, 0)
    NumPut(DragStartSX, mpt, 0, "Int")
    NumPut(DragStartSY, mpt, 4, "Int")
    DllCall("ScreenToClient", "ptr", MarkGuiHwnd, "ptr", &mpt)
    px1 := NumGet(mpt, 0, "Int") - 10
    py1 := NumGet(mpt, 4, "Int") - 36
    NumPut(sx, mpt, 0, "Int")
    NumPut(sy, mpt, 4, "Int")
    DllCall("ScreenToClient", "ptr", MarkGuiHwnd, "ptr", &mpt)
    px2 := NumGet(mpt, 0, "Int") - 10
    py2 := NumGet(mpt, 4, "Int") - 36
    GuiControl, Mark:, MarkListBox, % "Area: (" px1 "," py1 ") -> (" px2 "," py2 ")"
    GuiControl, Mark:, MarkPrompt, Cutting template...
    SaveTemplateRegion(px1, py1, px2, py2)
    MarkMode := ""
    Gui, Mark:Destroy
    if (CalibGuiHwnd && DllCall("IsWindow", "ptr", CalibGuiHwnd))
        DllCall("ShowWindow", "ptr", CalibGuiHwnd, "int", 1)
    UpdateCalibStatus()
    return 1
}

DragCleanup() {
    global DragActive, DragPrevRect
    if (!DragActive)
        return
    DragActive := false
    HideDragRect()
    DragPrevRect := ""
}
