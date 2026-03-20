# ==========================================
# 1. Configuración de Rutas y Variables
# ==========================================
# 1. Parámetro de entrada
param([string]$NuevoModo) 

Add-Type -AssemblyName System.Drawing
$skinName      = "Nexus_Grid_Xipi"
$outputDir     = "$env:USERPROFILE\Documents\Rainmeter\Skins\$skinName\@Resources"
$outputFile    = Join-Path $outputDir "SteamGames.inc"
$steamBase     = "C:\Program Files (x86)\Steam"
$steamCache    = "$steamBase\appcache\librarycache"
$libraryConfig = "$steamBase\steamapps\libraryfolders.vdf"
$configFile    = "H:\proyectos\Nexus_Grid_Xipi\config.ini"

$CWidth, $CHeight, $Spacing = 160, 240, 20
$ColsAuto = 14 
$layoutSchema = @(14, 4, 4, 14, 14)

$manualExclusions = @(431960) #wallpaper engine
$manualInclusions = @() # ID de ejemplo (last of us ii) <--- busca directamente en SteamgridDB
#si la imagen de algun juego no es acorde a lo que quieres, 
#añade su ID a esta lista y el script lo bajará de internet (prioridad máxima) en lugar de usar la imagen local (si existe)

##### Modo Grid: Auto o Manual (Toggle) #####

# Definimos el parámetro al inicio de tu script si no lo tiene:
# param([string]$ForzarModo = "") 




# 2. Valor por defecto (si el archivo no existe)
$ModoGrid = "Auto" 

# 3. Intentar leer el modo actual del archivo
if (Test-Path $outputFile) {
    # Buscamos específicamente la línea que contiene el modo
    $lineaModo = Get-Content $outputFile | Select-String "VariableModo=(Auto|Manual)"
    if ($lineaModo) {
        $valorActual = ($lineaModo.ToString().Split("=")[1]).Trim()
        $ModoGrid = $valorActual # Mantenemos el valor por defecto igual al que ya existe
    }
}

# 4. Lógica de cambio (SOLO si se recibe algo por parámetro)
if (-not [string]::IsNullOrWhiteSpace($NuevoModo)) {
    if ($NuevoModo -eq "Toggle") {
        # Si es Toggle, invertimos el valor que leímos
        $ModoGrid = if ($ModoGrid -eq "Manual") { "Auto" } else { "Manual" }
    }
    else {
        # Si mandaste "Auto" o "Manual" directamente, lo aplicamos
        $ModoGrid = $NuevoModo
    }
}
# Si $NuevoModo está vacío, $ModoGrid se queda con el $valorActual que leyó arriba.
# ==========================================
# 2. API SteamGridDB y Funciones de conteo
# ==========================================
$SGDB_API_KEY = $null
if (Test-Path $configFile) {
    $lineaKey = Get-Content $configFile | Select-String "SGDB_API_KEY="
    if ($lineaKey) { $SGDB_API_KEY = $lineaKey.ToString().Split("=")[1].Trim() }
}

function Get-SteamGridDBImage {
    param ([string]$GameName, [string]$ApiKey)
    if (-not $ApiKey) { return $null }
    $cleanName = ($GameName -split " - ")[0] -replace "™|®|:|\(.*?\)","" -replace "\s+", " "
    $encodedName = [Uri]::EscapeDataString($cleanName.Trim())
    try {
        $search = Invoke-RestMethod -Uri "https://www.steamgriddb.com/api/v2/search/autocomplete/$encodedName" -Headers @{"Authorization" = "Bearer $ApiKey"}
        if ($search.success -and $search.data.Count -gt 0) {
            $gameId = $search.data[0].id
            $grids = Invoke-RestMethod -Uri "https://www.steamgriddb.com/api/v2/grids/game/$($gameId)?dimensions=600x900" -Headers @{"Authorization" = "Bearer $ApiKey"}
            if ($grids.success -and $grids.data.Count -gt 0) { return $grids.data[0].url }
        }
    } catch { return $null }
}

function Get-ManualPriorityImage {
    param ($Game, $OutputDir, $ApiKey, $ManualInclusions)
    
    # Convertimos a String para que compare bien tanto números (Steam) como letras (Epic)
    # y evitamos el error de "InvalidCast"
    if ($ManualInclusions -notcontains $Game.ID) { return $false }

    $targetFile = Join-Path $OutputDir "$($Game.ID).jpg"
    
    Write-Host " [!] PRIORIDAD MANUAL: $($Game.Name)..." -ForegroundColor Yellow
    $url = Get-SteamGridDBImage -GameName $Game.Name -ApiKey $ApiKey
    if ($url) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $targetFile -TimeoutSec 10
            return $true 
        } catch { return $false }
    }
    return $false
}

# ==========================================
# 3. Escaneo de Librerías (SOLO ESCANEO)
# ==========================================


#**** escaneo STEAM ****

$allGames = @()
Write-Host "[1/3] Escaneando librerías..." -ForegroundColor Cyan

$configContent = Get-Content $libraryConfig -Raw
$libraryPaths = [regex]::Matches($configContent, '"path"\s+"(.+?)"') | % { $_.Groups[1].Value -replace "\\\\", "\" }
foreach ($path in $libraryPaths) {
    $apps = Join-Path $path "steamapps"
    if (Test-Path $apps) {
        Get-ChildItem "$apps\appmanifest_*.acf" | % {
            $content = Get-Content $_.FullName -Raw
            $appid = [regex]::Match($content, '"appid"\s+"(\d+)"').Groups[1].Value
            $name = [regex]::Match($content, '"name"\s+"(.+?)"').Groups[1].Value
            if ($manualExclusions -notcontains [int]$appid -and $name -notmatch "Steamworks|Redistributable|Server") {
                $allGames += [PSCustomObject]@{ ID = $appid; Name = $name; Type = "Steam" }
            }
        }
    }
}

#**** escaneo EPIC ****

$epicManifestPath = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
if (Test-Path $epicManifestPath) {
    Get-ChildItem $epicManifestPath -Filter "*.item" | ForEach-Object {
        $content = Get-Content $_.FullName -Raw | ConvertFrom-Json
        if (Test-Path $content.InstallLocation) {
            $allGames += [PSCustomObject]@{ 
                ID = "epic_$($content.AppName)"; Name = $content.DisplayName; Type = "Epic"; 
                CatalogID = $content.CatalogItemId; LaunchURI = "com.epicgames.launcher://apps/$($content.AppName)?action=launch&silent=true" 
            }
        }
    }
}

#**** escaneo Battle.net ****
#**** escaneo BLIZZARD ****
$blizzPath = "H:\BlizardLibrary"
$countAnterior = $allGames.Count
Write-Host " [DEBUG] Verificando ruta Blizzard: $blizzPath" -ForegroundColor Gray

if (Test-Path $blizzPath) {
    Get-ChildItem -Path $blizzPath -Directory | ForEach-Object {
        $gameName = $_.Name
        # REPLICANDO FORMATO: Solo recolectamos información base
        $allGames += [PSCustomObject]@{ 
            ID         = "blizz_$($gameName -replace '\s','')" 
            Name       = $gameName 
            Type       = "Blizzard"
            SourcePath = $_.FullName 
        }
    }
    Write-Host " [DEBUG] Juegos Blizzard detectados: $($allGames.Count - $countAnterior)" -ForegroundColor Gray
}
else {
    Write-Host " [!] ERROR: La ruta $blizzPath no existe o no es accesible." -ForegroundColor Red
}


# ==========================================
# 4. Procesar Imágenes (PRIORIDAD AQUÍ)
# ==========================================
Write-Host "[2/3] Verificando carátulas..." -ForegroundColor Cyan

foreach ($game in $allGames) {
    # --- PASO 1: PRIORIDAD MANUAL ---
    # Si el ID está en la lista, se baja de internet y saltamos al siguiente juego
    if (Get-ManualPriorityImage -Game $game -OutputDir $outputDir -ApiKey $SGDB_API_KEY -ManualInclusions $manualInclusions) {
        continue 
    }

    # --- PASO 2: BUSQUEDA EXTENSIVA  ---
    $imgName = "$($game.ID).jpg"
    $localImg = Join-Path $outputDir $imgName
    
    if (-not (Test-Path $localImg)) {
        $found = $false
        
        # BÚSQUEDA LOCAL STEAM 
        if ($game.Type -eq "Steam") {
            $gameFolder = Join-Path $steamCache $game.ID
            if (Test-Path $gameFolder) {
                $foundFile = Get-ChildItem -Path $gameFolder -Filter "*.jpg" -Recurse | 
                             Where-Object { $_.Length -gt 20kb -and $_.Length -lt 80kb -and ($_.Name -like "*library*" -or $_.Name -like "*capsule*") } | 
                             Select-Object -First 1
                
                if ($foundFile) {
                    Copy-Item -Path $foundFile.FullName -Destination $localImg -Force
                    Write-Host " EXITOSO (Local Steam): $($game.Name)" -ForegroundColor Green
                    $found = $true
                }
            }
        }

        # BÚSQUEDA EPIC
        if (-not $found -and $game.Type -eq "Epic") {
            $url = "https://cdn1.epicgames.com/item/$($game.CatalogID)/library_600x900.jpg"
            try {
                Invoke-WebRequest -Uri $url -OutFile $localImg -UserAgent "Mozilla/5.0" -TimeoutSec 5 -ErrorAction Stop
                Write-Host " EXITOSO (Epic CDN): $($game.Name)" -ForegroundColor Cyan
                $found = $true
            } catch {}
        }
        #**** Búsqueda BLIZZARD ****

        foreach ($game in $blizzardGames) {
            # 1. RESET CRÍTICO: Limpiamos variables para que no herede del juego anterior
            $currentId = $null
            $imageUrl = $null
            
            Write-Host "`n[*] Buscando carátula para: $($game.Name)..." -ForegroundColor Cyan
            $targetFile = Join-Path $resourcesPath "$($game.ID).jpg"
        
            if (Test-Path $targetFile) {
                Write-Host " [SKIP] Ya existe." -ForegroundColor Gray
                continue
            }
        
            # 2. LIMPIEZA AGRESIVA DEL NOMBRE
            # Quitamos "III", "II", y cualquier cosa rara para mejorar el Autocomplete
            $cleanName = $game.Name -replace "™|®|:|\(.*?\)", ""
            $encodedName = [Uri]::EscapeDataString($cleanName.Trim())
            
            try {
                $searchRes = Invoke-RestMethod -Uri "https://www.steamgriddb.com/api/v2/search/autocomplete/$encodedName" -Headers $headers
                
                if ($searchRes.success -and $searchRes.data.Count -gt 0) {
                    # Seleccionamos el ID del primer resultado de la lista
                    $currentId = $searchRes.data[0].id
                    Write-Host "  -> ID encontrado: $currentId ($($searchRes.data[0].name))" -ForegroundColor Gray
                    
                    # 3. PETICIÓN DE GRIDS
                    $gridRes = Invoke-RestMethod -Uri "https://www.steamgriddb.com/api/v2/grids/game/$currentId?dimensions=600x900" -Headers $headers
                    
                    if ($gridRes.success -and $gridRes.data.Count -gt 0) {
                        $imageUrl = $gridRes.data[0].url
                        
                        # 4. DESCARGA CON USER-AGENT PARA EVITAR BLOQUEOS
                        Invoke-WebRequest -Uri $imageUrl -OutFile $targetFile -UserAgent "Mozilla/5.0" -TimeoutSec 15
                        Write-Host " [OK] Descargado con éxito." -ForegroundColor Green
                    }
                }
            }
            catch {
                Write-Host " [ERROR] Falló la conexión para $($game.Name)" -ForegroundColor Red
            }
        }
        # RESPALDO API (Si no es manual pero no hay imagen)
        if (-not $found -and $SGDB_API_KEY) {
            $sgdbUrl = Get-SteamGridDBImage -GameName $game.Name -ApiKey $SGDB_API_KEY
            if ($sgdbUrl) {
                try {
                    Invoke-WebRequest -Uri $sgdbUrl -OutFile $localImg -TimeoutSec 10
                    Write-Host " EXITOSO (SteamGridDB): $($game.Name)" -ForegroundColor Yellow
                    $found = $true
                } catch {}
            }
        }
        
        if (-not $found) { Write-Host " FALLIDO: $($game.Name)" -ForegroundColor Red }
    }
}
# ==========================================
# 5. Generación de Grid y Archivo (Con Soporte de Iconos)
# ==========================================
Write-Host "[3/3] Generando Grid con clasificación..." -ForegroundColor Cyan
$incContent = ""
$count = 0

foreach ($game in ($allGames | Sort-Object Name)) {
    # ... (Tu lógica de posicionamiento $posX y $posY se mantiene igual) ...
    if ($ModoGrid -eq "Manual") {
        $tempSum = 0; $targetRow = 0
        for ($i = 0; $i -lt $layoutSchema.Count; $i++) {
            if ($count -lt ($tempSum + $layoutSchema[$i])) { $targetRow = $i; $indexInRow = $count - $tempSum; break }
            $tempSum += $layoutSchema[$i]
        }
        $posX = ($indexInRow * ($CWidth + $Spacing)) + 40
        $posY = ($targetRow * ($CHeight + $Spacing)) + 80
    }
    else {
        $posX = (($count % $ColsAuto) * ($CWidth + $Spacing)) + 40
        $posY = ([Math]::Floor($count / $ColsAuto) * ($CHeight + $Spacing)) + 80
    }

    # --- LÓGICA DE FILTRO DE EJECUTABLE (STRING MATCH) ---
    $action = ""

    if ($game.Type -eq "Epic") {
        $action = "[`"$($game.LaunchURI)`"]"
    } 
    elseif ($game.Type -eq "Blizzard") {
        Write-Host " [VERBOSE] Analizando Blizzard: $($game.Name)" -ForegroundColor Gray
        
        # 1. Buscamos todos los .exe en la ruta escaneada (Línea 172)
        $folder = $game.SourcePath
      
        # 2. Tu idea: El que más se parezca al título (String Match)
        $excludeList = "Launcher|Crash|Update|Setup|System|Support|Editor|Switcher|Versions|Bones"
        $exeFiles = Get-ChildItem -Path $folder -Filter "*.exe" -Recurse | 
        Where-Object { $_.Name -notmatch $excludeList }
        $bestMatch = $exeFiles | ForEach-Object {
            $score = 0
            $tituloPalabras = $game.Name -split "\s+|-" # Ejemplo: "StarCraft", "II"
            foreach ($word in $tituloPalabras) {
                if ($_.Name -like "*$word*") { $score++ }
            }
            [PSCustomObject]@{ Path = $_.FullName; Name = $_.Name; Score = $score }
        } | Sort-Object Score -Descending | Select-Object -First 1

        # 3. Asignación con Verbose
        if ($bestMatch -and $bestMatch.Score -gt 0) {
            Write-Host "   -> Ganador: $($bestMatch.Name) (Score: $($bestMatch.Score))" -ForegroundColor DarkGray
            $rutaLimpia = $bestMatch.Path -replace '\\', '\\'
            $action = "[`"$rutaLimpia`"]"
        }
        else {
            Write-Host "   [!] No hubo match claro. Usando carpeta raíz." -ForegroundColor Yellow
            $action = "[`"$($game.SourcePath -replace '\\', '\\')`"]"
        }
    } 
    else {
        # Steam (ID numérico)
        $action = "[`"steam://rungameid/$($game.ID)`"]"
    }


    # --- CONSTRUCCIÓN DE LOS METERS ---
    # 1. El Meter de la carátula (Fondo)
    # 2. El Meter del Icono (Superpuesto) usando $game.Type
    
    $incContent += "
[Game$count]
Meter=Image
ImageName=#@#$($game.ID).jpg
ImageNotFound=#@#default.jpg
W=$CWidth
H=$CHeight
X=$posX
Y=$posY
PreserveAspectRatio=1
ImageAlpha=210
LeftMouseUpAction=$action
Group=Games
MouseOverAction=[!SetOption #CURRENTSECTION# ImageAlpha 255][!SetVariable NombreJuego `"$($game.Name)`"][!UpdateMeter *][!Redraw]
MouseLeaveAction=[!SetOption #CURRENTSECTION# ImageAlpha 210][!SetVariable NombreJuego `"`"][!UpdateMeter *][!Redraw]

[Icon$count]
Meter=Image
ImageName=#@#Icons\$($game.Type).png
W=24
H=24
X=($posX + $CWidth - 28)
Y=($posY + 4)
ImageAlpha=255
Group=Games
DynamicVariables=1
"
    $count++
    if ($ModoGrid -eq "Manual" -and $count -ge 100) { break }
}
# ... (El resto del guardado del archivo y Refresh de Rainmeter) ...

# --- GUARDADO FINAL DEL ARCHIVO .INC ---

# Preparamos el encabezado con el modo que decidió el switch
$header = "[Variables]`nTotalGames=$count`nUltimaFecha=$((Get-Date).ToString("d 'de' MMMM 'del' yyyy"))`nVariableModo=$ModoGrid`n"

# Escribimos el archivo (asegurando UTF8 para Rainmeter
($header + $incContent) | Out-File -FilePath $outputFile -Encoding unicode -Force

# Refrescamos el skin para ver los cambios al instante
if (Test-Path "C:\Program Files\Rainmeter\Rainmeter.exe") {
    & "C:\Program Files\Rainmeter\Rainmeter.exe" !Refresh "$skinName"
}

Write-Host "`nPROCESO TERMINADO - MODO ACTUAL: $ModoGrid" -ForegroundColor Magenta
