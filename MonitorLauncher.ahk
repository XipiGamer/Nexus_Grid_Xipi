#Requires AutoHotkey v2.0
#SingleInstance Force

; --- RUTA AL MONITOR ---
; Usamos la ruta que ya tienes establecida para el monitor
rutaMonitor := "H:\proyectos\Nexus_Grid_Xipi\UpdateMonitor.ps1"

; --- EJECUCIÓN SILENCIOSA ---
; -WindowStyle Hidden: asegura que PowerShell no muestre la ventana negra
; -ExecutionPolicy Bypass: evita bloqueos de seguridad al ejecutar el .ps1
comando := "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"" . rutaMonitor . "`""

try {
    Run(comando, , "Hide")
} catch Error as e {
    ; Solo mostrará algo si hay un error crítico al intentar lanzar el proceso
    MsgBox("Error al lanzar el monitor invisible: " . e.Message)
}