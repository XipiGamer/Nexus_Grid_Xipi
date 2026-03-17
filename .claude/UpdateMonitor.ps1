param (
    [string]$ForzarModo = "" 
)

# --- CONFIGURACIÓN DE RUTAS ---
$steamBase = "C:\Program Files (x86)\Steam"
$libraryConfig = "$steamBase\steamapps\libraryfolders.vdf"
$epicManifestPath = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
$bnetPath = "H:\BlizardLibrary" 
$mainScript = "H:\proyectos\UpdateMini.ps1"

$lastTotalCount = 0

Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] [*] Inspector de Librerías Activo (Intervalo: 20s)" -ForegroundColor Cyan
Write-Host "[*] Presiona Ctrl+C para detener el monitoreo." -ForegroundColor Gray
Write-Host "[!] Monitoreando: Steam, Epic y Blizzard...`n" -ForegroundColor DarkGray

while ($true) {
    $currentTimestamp = Get-Date -Format "HH:mm:ss"
    try {
        # 1. Conteo Steam
        $steamCount = 0
        if (Test-Path $libraryConfig) {
            $configContent = Get-Content $libraryConfig -Raw
            $libraryPaths = [regex]::Matches($configContent, '"path"\s+"(.+?)"') | ForEach-Object { $_.Groups[1].Value -replace "\\\\", "\" }
            
            foreach ($path in $libraryPaths) {
                $apps = Join-Path $path "steamapps"
                if (Test-Path $apps) {
                    $steamCount += (Get-ChildItem "$apps\appmanifest_*.acf" -ErrorAction SilentlyContinue).Count
                }
            }
        }
        
        # 2. Conteo Epic
        $epicCount = 0
        if (Test-Path $epicManifestPath) {
            $epicCount = (Get-ChildItem $epicManifestPath -Filter "*.item" -ErrorAction SilentlyContinue).Count
        }

        # 3. Lógica Blizzard (Recuperada y Corregida)
        $bnetCount = 0
        if (Test-Path $bnetPath) {
            # Aquí reintegramos la lógica de filtrado que tenías en el script principal para consistencia
            $bnetGames = Get-ChildItem -Path $bnetPath -Directory -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -notmatch "patch|temp|\.data|Builders" }
            $bnetCount = $bnetGames.Count
        }

        $totalCount = $steamCount + $epicCount + $bnetCount

        # 4. LÓGICA DE DETECCIÓN
        if ($totalCount -ne $lastTotalCount) {
            
            if ($lastTotalCount -eq 0) {
                $lastTotalCount = $totalCount
                Write-Host "[$currentTimestamp] [v] Estado Inicial: $totalCount juegos (S:$steamCount | E:$epicCount | B:$bnetCount)" -ForegroundColor DarkGray
            } 
            else {
                $dif = $totalCount - $lastTotalCount
                $msg = if ($dif -gt 0) { "NUEVO JUEGO DETECTADO" } else { "JUEGO ELIMINADO" }
                
                Write-Host "`n[$currentTimestamp] [!] $msg" -ForegroundColor Yellow -NoNewline
                Write-Host " (Total: $totalCount)" -ForegroundColor White
                Write-Host "    Detalle: Steam($steamCount) | Epic($epicCount) | Blizzard($bnetCount)" -ForegroundColor DarkCyan
                
                Write-Host "    Preparando entorno y actualizando..." -ForegroundColor Gray
                Start-Sleep -Seconds 2
                
                if (Test-Path $mainScript) {
                    # Ejecución del script principal
                    & $mainScript
                    Write-Host "    [$((Get-Date).ToString('HH:mm:ss'))] [OK] Grid y Rainmeter actualizados.`n" -ForegroundColor Green
                }
                else {
                    Write-Host "    [X] ERROR: No se encontró el script en $mainScript" -ForegroundColor Red
                }
                
                $lastTotalCount = $totalCount
            }
        }
    }
    catch {
        Write-Host "`n[$currentTimestamp] [!] ERROR EN EL MONITOR: $($_.Exception.Message)" -ForegroundColor Red
    }

    [System.GC]::Collect()
    Start-Sleep -Seconds 20
}