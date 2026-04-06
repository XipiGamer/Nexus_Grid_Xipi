#Requires AutoHotkey v2.0
#SingleInstance Force

; Si se pasa --close, matar la instancia existente y salir
if (A_Args.Length > 0 && A_Args[1] = "--close") {
    for proc in ComObjGet("winmgmts:").ExecQuery("SELECT * FROM Win32_Process WHERE Name='AutoHotkey64.exe'") {
        if InStr(proc.CommandLine, "Gallery.ahk") && proc.ProcessId != DllCall("GetCurrentProcessId") {
            Run("taskkill /PID " . proc.ProcessId . " /F", , "Hide")
        }
    }
    ExitApp()
}

#Include "H:\proyectos\Nexus_Grid_Xipi\Lib\WebView2.ahk"

; ==========================================
; NEXUS GRID - GALLERY VIEW (WebView2)
; ==========================================

rutaBase   := "H:\proyectos\Nexus_Grid_Xipi"
rutaHTML   := rutaBase . "\@Resources\gallery.html"
rutaScript := rutaBase . "\Core_Browser.ps1"
rutaPS     := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

; --- Si el HTML no existe, generarlo primero ---
if !FileExist(rutaHTML) {
    RunWait('"' . rutaPS . '" -ExecutionPolicy Bypass -WindowStyle Hidden -File "' . rutaScript . '" -GenerateHTML', , "Hide")
}

; --- DIMENSIONES INICIALES (se ajustan dinámicamente desde JS) ---
screenW := A_ScreenWidth
screenH := A_ScreenHeight
winW    := Round(screenW * 0.82)
winH    := Round(screenH * 0.15)   ; altura mínima inicial, JS la ajusta
posX    := Round((screenW - winW) / 2)
posY    := Round((screenH - winH) / 2)

; --- CREAR VENTANA con fondo transparente ---
myGui := Gui("-Caption +AlwaysOnTop +Resize +E0x00080000")
myGui.BackColor := "0d0d0f"
WinSetTransparent(230, myGui.Hwnd)  ; 230/255 ≈ 90% opacidad

; --- MOSTRAR antes de crear WebView2 ---
myGui.Show("w" . winW . " h" . winH . " x" . posX . " y" . posY . " NoActivate")

; --- ESQUINAS REDONDEADAS ---
ApplyRoundedCorners(winW, winH) {
    global myGui
    radio  := 14
    region := DllCall("Gdi32.dll\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", winW, "Int", winH, "Int", radio, "Int", radio)
    DllCall("User32.dll\SetWindowRgn", "UInt", myGui.Hwnd, "UInt", region, "UInt", 1)
}
ApplyRoundedCorners(winW, winH)

; --- WEBVIEW2 ---
wvc := WebView2.CreateControllerAsync(myGui.Hwnd).await2()
wv  := wvc.CoreWebView2

; Bounds iniciales
global wvc, wv, winW, winH
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

wv.Navigate("file:///" . StrReplace(rutaHTML, "\", "/"))

; --- CERRAR CON ESCAPE ---
myGui.OnEvent("Escape", (*) => myGui.Destroy())
Hotkey("Escape", (*) => myGui.Destroy())

; --- MENSAJES DESDE JS ---
wv.add_WebMessageReceived(OnWebMessage)
OnWebMessage(wv2, args) {
    global myGui, winW, winH, screenW, screenH, posX, posY
    msg := args.TryGetWebMessageAsString()
    try {
        if RegExMatch(msg, '"action"\s*:\s*"resize".*?"w"\s*:\s*(\d+).*?"h"\s*:\s*(\d+)', &m) {
            newW := Integer(m[1])
            newH := Integer(m[2])

            ; Limitar al 95% de la pantalla
            maxW := Round(screenW * 0.95)
            maxH := Round(screenH * 0.92)
            newW := Min(newW, maxW)
            newH := Min(newH, maxH)

            ; Centrar
            newX := Round((screenW - newW) / 2)
            newY := Round((screenH - newH) / 2)

            winW := newW
            winH := newH

            myGui.Move(newX, newY, newW, newH)
            SetBounds(newW, newH)
            ApplyRoundedCorners(newW, newH)
        }
        else if RegExMatch(msg, '"action"\s*:\s*"launch".*?"uri"\s*:\s*"([^"]+)"', &m)
            Run(m[1])
        else if RegExMatch(msg, '"action"\s*:\s*"close"')
            myGui.Destroy()
    }
}
