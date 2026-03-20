# ==========================================
# CONFIGURACIÓN DE RUTAS Y TIEMPOS
# ==========================================
$IncFile = "H:\proyectos\Nexus_Grid_Xipi\@Resources\SteamGames.inc"
$UpdateScript = "H:\proyectos\Nexus_Grid_Xipi\Core_Browser.ps1"
$libraryConfig = "C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf"
$blizzPath = "H:\BlizardLibrary"
$Intervalo = 1 # Revisa cada 1 segundo
$manualExclusions = @(431960) 

Write-Host "Vigilante de librerías iniciado (segundo plano)..." -ForegroundColor Cyan

while ($true) {
    # 1. ESCANEO (Lógica idéntica a UpdateMini.ps1)
    $allGames = @()

    # **** escaneo STEAM ****
    if (Test-Path $libraryConfig) {
        try {
            $configContent = Get-Content $libraryConfig -Raw
            $libraryPaths = [regex]::Matches($configContent, '"path"\s+"(.+?)"') | % { $_.Groups[1].Value -replace "\\\\", "\" }
            foreach ($path in $libraryPaths) {
                $apps = Join-Path $path "steamapps"
                if (Test-Path $apps) {
                    Get-ChildItem "$apps\appmanifest_*.acf" -ErrorAction SilentlyContinue | % {
                        $content = Get-Content $_.FullName -Raw
                        $appid = [regex]::Match($content, '"appid"\s+"(\d+)"').Groups[1].Value
                        $name = [regex]::Match($content, '"name"\s+"(.+?)"').Groups[1].Value
                        if ($manualExclusions -notcontains [int]$appid -and $name -notmatch "Steamworks|Redistributable|Server") {
                            $allGames += [PSCustomObject]@{ ID = $appid; Type = "Steam" }
                        }
                    }
                }
            }
        }
        catch {}
    }

    # **** escaneo EPIC ****
    $epicManifestPath = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path $epicManifestPath) {
        Get-ChildItem $epicManifestPath -Filter "*.item" -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $content = Get-Content $_.FullName -Raw | ConvertFrom-Json
                if (Test-Path $content.InstallLocation) {
                    $allGames += [PSCustomObject]@{ ID = "epic_$($content.AppName)"; Type = "Epic" }
                }
            }
            catch {}
        }
    }

    # **** escaneo BLIZZARD ****
    if (Test-Path $blizzPath) {
        Get-ChildItem -Path $blizzPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $allGames += [PSCustomObject]@{ ID = "blizz_$($_.Name -replace '\s','')"; Type = "Blizzard" }
        }
    }

    # 2. COMPARACIÓN CON EL ARCHIVO .INC
    $TotalActual = $allGames.Count
    $TotalPrevio = 0
    
    if (Test-Path $IncFile) {
        $IncContent = Get-Content $IncFile -Raw
        if ($IncContent -match 'TotalGames=(\d+)') {
            $TotalPrevio = [int]$Matches[1]
        }
    }

    # 3. ACCIÓN SI HAY CAMBIOS
    if ($TotalActual -ne $TotalPrevio) {
        $Timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "[$Timestamp] Cambio detectado: $TotalPrevio -> $TotalActual. Actualizando..." -ForegroundColor Yellow
        
        if (Test-Path $UpdateScript) {
            # Se lanza en modo oculto para no interrumpir
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$UpdateScript`"" -WindowStyle Hidden
        }
    }

    # Pausa antes de la siguiente revisión
    Start-Sleep -Seconds $Intervalo
}