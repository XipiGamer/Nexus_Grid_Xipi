#Requires AutoHotkey v2.0
#SingleInstance Force

; --- BLOQUEO DE INSTANCIA ---
ValidarInstanciaUnica()
ValidarInstanciaUnica() {
    handle := DllCall("CreateMutex", "Ptr", 0, "Int", 1, "Str", "Global\MiniSteamPopupMutex", "Ptr")
    if (A_LastError = 183) {
        ExitApp()
    }
}

; --- CONFIGURACIÓN ---
rutaBase := "H:\proyectos\Nexus_Grid_Xipi"
rutaScript := rutaBase . "\UpdateMini.ps1"
rutaPowerShell := "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
rutaInc := "C:\Users\chipi\Documents\Rainmeter\Skins\Mini-Steam Launcher\@Resources\SteamGames.inc"

colorFondo := "ffffff"
colorTexto := "C18DAB"
colorauto := "ac0e0e"
colormanual := "2b9f5b"

; --- INICIALIZACIÓN DE VARIABLES (Evita el Warning) ---
ModoActual := "Auto"
ColorVariable := colormanual ; Valor por defecto
TextoVariable := ""

; --- VALIDACIÓN INICIAL ---
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

; --- APLICAR ESQUINAS REDONDEADAS (SOLO ABAJO) ---
myGui.Show("w200 h34 xCenter y0 NoActivate Hide")

; El truco: Empezamos en Y = -10 para que las esquinas superiores queden fuera del área visible
; (HWND, X1, Y1, X2, Y2, AnchoCurva, AltoCurva)
radioCurva := 10
reducirEsquinas := DllCall("Gdi32.dll\CreateRoundRectRgn", "Int", 0, "Int", -10, "Int", 200, "Int", 34, "Int", radioCurva, "Int", radioCurva)
DllCall("User32.dll\SetWindowRgn", "UInt", myGui.Hwnd, "UInt", reducirEsquinas, "UInt", 1)

; --- LÓGICA DE FUNDIDO ---
WinSetTransparent(0, myGui.Hwnd)
myGui.Show("NoActivate")

Loop 30 {
    valorOpacidad := Floor(A_Index * 8.5)
    WinSetTransparent(valorOpacidad, myGui.Hwnd)
    Sleep 5
}

; --- CURSOR (MANO) ---
OnMessage(0x0020, WM_SETCURSOR)
WM_SETCURSOR(wParam, lParam, msg, hwnd) {
    if (wParam = TxtFijo.Hwnd || wParam = TxtVar.Hwnd) {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32649, "Ptr"))
        return Number(True)
    }
}

TxtFijo.OnEvent("Click", EjecutarCambio)
TxtVar.OnEvent("Click", EjecutarCambio)

; --- AUTO-CIERRE ---
SetTimer(CerrarPorInactividad, 1500)
CerrarPorInactividad() {
    MouseGetPos(, , &id)
    if (id != myGui.Hwnd) {
        ExitApp()
    }
}

; --- ACCIÓN ---
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
    }
}