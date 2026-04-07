#Requires AutoHotkey v2.0
#SingleInstance Force

rutaGallery := "H:\proyectos\Nexus_Grid_Xipi\Gallery.ahk"
rutaAHK     := "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

; Buscar si Gallery.ahk ya está corriendo
galleryPID := 0
for proc in ComObjGet("winmgmts:").ExecQuery("SELECT * FROM Win32_Process WHERE Name='AutoHotkey64.exe'") {
    if InStr(proc.CommandLine, "Gallery.ahk") {
        galleryPID := proc.ProcessId
        break
    }
}

if galleryPID {
    ; Ya está abierto — cerrarlo
    Run("taskkill /PID " . galleryPID . " /F", , "Hide")
} else {
    ; No está abierto — lanzarlo
    Run('"' . rutaAHK . '" "' . rutaGallery . '"')
}

ExitApp()
