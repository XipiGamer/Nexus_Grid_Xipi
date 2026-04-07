#Requires AutoHotkey v2.0
#SingleInstance Ignore  ; No reemplazar instancia — manejar toggle manualmente

; ==========================================
; NEXUS GRID - GALLERY VIEW (WebView2)
; Toggle: si ya está abierto lo cierra, si no lo abre
; ==========================================

; --- TOGGLE: cerrar si ya existe una instancia ---
hwnd := WinExist("Nexus Grid — Gallery ahk_class AutoHotkeyGUI")
if hwnd {
    WinClose(hwnd)
    ExitApp()
}

#Include "H:\proyectos\Nexus_Grid_Xipi\Lib\WebView2.ahk"

rutaBase   := "H:\proyectos\Nexus_Grid_Xipi"
rutaHTML   := rutaBase . "\@Resources\gallery.html"
rutaScript := rutaBase . "\Core_Browser.ps1"
rutaPS     := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

; --- Si el HTML no existe, generarlo primero ---
if !FileExist(rutaHTML) {
    RunWait('"' . rutaPS . '" -ExecutionPolicy Bypass -WindowStyle Hidden -File "' . rutaScript . '" -GenerateHTML', , "Hide")
}

; --- DIMENSIONES ---
screenW := A_ScreenWidth
screenH := A_ScreenHeight
cardW   := 110
gap     := 14
pad     := 20
cols    := Min(16, Floor((screenW * 0.95 - pad * 2 + gap) / (cardW + gap)))
winW    := cols * (cardW + gap) - gap + pad * 2
winH    := Round(screenH * 0.15)
posX    := Round((screenW - winW) / 2)
posY    := Round((screenH - winH) / 2)

; --- CREAR VENTANA ---
myGui := Gui("-Caption +AlwaysOnTop +Resize")
myGui.BackColor := "0d0d0f"
myGui.Title := "Nexus Grid — Gallery"
WinSetTransparent(230, myGui.Hwnd)

; --- MOSTRAR antes de crear WebView2 ---
myGui.Show("w" . winW . " h" . winH . " x" . posX . " y" . posY . " NoActivate")

; --- ESQUINAS REDONDEADAS ---
ApplyRoundedCorners(w, h) {
    global myGui
    region := DllCall("Gdi32.dll\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", 14, "Int", 14)
    DllCall("User32.dll\SetWindowRgn", "UInt", myGui.Hwnd, "UInt", region, "UInt", 1)
}
ApplyRoundedCorners(winW, winH)

; --- WEBVIEW2 ---
dataDir := A_Temp . "\NexusGrid_WV2"
wvc := WebView2.CreateControllerAsync(myGui.Hwnd, 0, dataDir).await2()
wv  := wvc.CoreWebView2

SetBounds(w, h) {
    global wvc
    b := Buffer(16)
    NumPut("Int", 0, b, 0)
    NumPut("Int", 0, b, 4)
    NumPut("Int", w, b, 8)
    NumPut("Int", h, b, 12)
    wvc.Bounds := b
}
SetBounds(winW, winH)

; Cache-busting
timestamp := A_NowUTC
wv.Navigate("file:///" . StrReplace(rutaHTML, "\", "/") . "?v=" . timestamp)

; --- CERRAR CON ESCAPE ---
myGui.OnEvent("Escape", (*) => myGui.Destroy())
Hotkey("Escape", (*) => myGui.Destroy())

; --- MENSAJES DESDE JS ---
wv.add_WebMessageReceived(OnWebMessage)
OnWebMessage(wv2, args) {
    global myGui, winW, winH, screenW, screenH
    msg := args.TryGetWebMessageAsString()
    try {
        if RegExMatch(msg, '"action"\s*:\s*"resize_h".*?"h"\s*:\s*(\d+)', &m) {
            newH := Integer(m[1])
            newH := Min(newH, Round(screenH * 0.92))
            newY := Round((screenH - newH) / 2)
            newX := Round((screenW - winW) / 2)
            winH := newH
            myGui.Move(newX, newY, winW, newH)
            SetBounds(winW, newH)
            ApplyRoundedCorners(winW, newH)
        }
        else if RegExMatch(msg, '"action"\s*:\s*"launch".*?"uri"\s*:\s*"([^"]+)"', &m) {
            uri := m[1]
            if InStr(uri, "battlenet://") || InStr(uri, "steam://") || InStr(uri, "com.epicgames")
                Run(uri)
            else
                Run('"' . uri . '"')
        }
        else if RegExMatch(msg, '"action"\s*:\s*"close"')
            myGui.Destroy()
    }
}
