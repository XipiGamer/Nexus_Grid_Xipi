#Requires AutoHotkey v2.0
#SingleInstance Force

; --- BLOQUEO DE INSTANCIA ---
ValidarInstanciaUnica()
ValidarInstanciaUnica() {
    static mutex := DllCall("CreateMutex", "Ptr", 0, "Int", 1, "Str", "Global\MiniSteamPopupMutex", "Ptr")
    if (A_LastError = 183) {
        ExitApp()
    }
}

; --- CONFIGURACIÓN ---
rutaBase := "H:\proyectos\Nexus_Grid_Xipi"
rutaScript := rutaBase . "\Core_Browser.ps1"
rutaPowerShell := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
rutaInc := "H:\proyectos\Nexus_Grid_Xipi\@Resources\SteamGames.inc"

colorFondo := "bb9373"
colorTexto := "361a2b"
colorauto := "740a74"
colormanual := "16a04f"

ModoActual := "Auto"
TextoVariable := ""

try {
    if FileExist(rutaInc) {
        contenido := FileRead(rutaInc)
        if RegExMatch(contenido, "im)VariableModo\s*=\s*(Manual|Auto)", &match) {
            ModoActual := match[1]
        }
    }
}

; --- INTERFAZ ---
myGui := Gui("-Caption +AlwaysOnTop +ToolWindow")
myGui.BackColor := colorFondo
myGui.SetFont("s11 w700 q5", "JetBrainsMono NF")

if (ModoActual = "Auto") {
    TextoVariable := "󱗽 MANUAL"
    ColorVariable := colormanual
} else {
    TextoVariable := "󱗼 AUTO"
    ColorVariable := colorauto
}

TxtFijo := myGui.Add("Text", "x12 y0 h34 +0x200 +0x100 c" . colorTexto, "Cambiar a 󰁔 ")
TxtVar := myGui.Add("Text", "x+0 y0 h34 w90 +0x200 +0x100 c" . ColorVariable, TextoVariable)

; --- CÁLCULO DE POSICIÓN INFERIOR ---
; Calculamos el borde inferior de la pantalla (restando la barra de tareas si es necesario)
MonitorGetWorkArea(, , , , &WorkAreaBottom)
anchoGui := 200
altoGui := 34
posX := (A_ScreenWidth // 2) - (anchoGui // 2)
posY := WorkAreaBottom - altoGui

myGui.Show("w" . anchoGui . " h" . altoGui . " x" . posX . " y" . posY . " NoActivate Hide")

; --- APLICAR ESQUINAS REDONDEADAS (SOLO ARRIBA) ---
; Ahora el recorte empieza en 0 y termina en +10 de alto para ocultar el redondeo inferior
radioCurva := 12
reducirEsquinas := DllCall("Gdi32.dll\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", anchoGui, "Int", altoGui + 15, "Int", radioCurva, "Int", radioCurva)
DllCall("User32.dll\SetWindowRgn", "UInt", myGui.Hwnd, "UInt", reducirEsquinas, "UInt", 1)

; --- LÓGICA DE FUNDIDO ---
WinSetTransparent(0, myGui.Hwnd)
myGui.Show("NoActivate")

Loop 20 {
    WinSetTransparent(Floor(A_Index * 12.75), myGui.Hwnd)
    Sleep 5
}

; --- CURSOR Y EVENTOS ---
OnMessage(0x0020, WM_SETCURSOR)
WM_SETCURSOR(wParam, lParam, msg, hwnd) {
    if (wParam = TxtFijo.Hwnd || wParam = TxtVar.Hwnd) {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32649, "Ptr"))
        return Number(True)
    }
}

TxtFijo.OnEvent("Click", EjecutarCambio)
TxtVar.OnEvent("Click", EjecutarCambio)

SetTimer(CerrarPorInactividad, 1500)
CerrarPorInactividad() {
    if !WinActive(myGui.Hwnd) {
        MouseGetPos(, , &id)
        if (id != myGui.Hwnd) {
            ExitApp()
        }
    }
}

EjecutarCambio(*) {
    global ModoActual
    SetTimer(CerrarPorInactividad, 0)
    NuevoModo := (ModoActual = "Auto") ? "Manual" : "Auto"
    comando := '"' . rutaPowerShell . '" -ExecutionPolicy Bypass -WindowStyle Hidden -File "' . rutaScript . '" -NuevoModo ' . NuevoModo
    try {
        RunWait(comando, , "Hide")
        ExitApp()
    } catch Error as e {
        MsgBox("Error: " . e.Message)
        ExitApp()
    }
}