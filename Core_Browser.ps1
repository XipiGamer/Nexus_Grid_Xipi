# ==========================================
# 1. Configuración de Rutas y Variables
# ==========================================
# 1. Parámetro de entrada
param([string]$NuevoModo, [switch]$GenerateHTML) 

Add-Type -AssemblyName System.Drawing
$skinName = "Nexus_Grid_Xipi"
$outputDir = "$env:USERPROFILE\Documents\Rainmeter\Skins\$skinName\@Resources"
$outputFile = Join-Path $outputDir "SteamGames.inc"
$steamBase = "C:\Program Files (x86)\Steam"
$steamCache = "$steamBase\appcache\librarycache"
$libraryConfig = "$steamBase\steamapps\libraryfolders.vdf"
$configFile = "H:\proyectos\Nexus_Grid_Xipi\config.ini"

$CWidth, $CHeight, $Spacing = 100, 180, 20
$ColsAuto = 12
$layoutSchema = @( 3, 3, 3, 3, 18, 18)

$manualExclusions = @(431960) #wallpaper engine
$manualInclusions = @() # ID de ejemplo (last of us ii) <--- busca directamente en SteamgridDB
#si la imagen de algun juego no es acorde a lo que quieres, 
#añade su ID a esta lista y el script lo bajará de internet (prioridad máxima) en lugar de usar la imagen local (si existe)

##### Modo Grid: Auto o Manual (Toggle) #####


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
    $cleanName = ($GameName -split " - ")[0] -replace "™|®|:|\(.*?\)", "" -replace "\s+", " "
    $encodedName = [Uri]::EscapeDataString($cleanName.Trim())
    try {
        $search = Invoke-RestMethod -Uri "https://www.steamgriddb.com/api/v2/search/autocomplete/$encodedName" -Headers @{"Authorization" = "Bearer $ApiKey" }
        if ($search.success -and $search.data.Count -gt 0) {
            $gameId = $search.data[0].id
            $grids = Invoke-RestMethod -Uri "https://www.steamgriddb.com/api/v2/grids/game/$($gameId)?dimensions=600x900" -Headers @{"Authorization" = "Bearer $ApiKey" }
            if ($grids.success -and $grids.data.Count -gt 0) { return $grids.data[0].url }
        }
    }
    catch { return $null }
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
        }
        catch { return $false }
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
            }
            catch {}
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
                }
                catch {}
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

        # 3. Mapa directo de nombres → URI Battle.net
        $blizzURIs = @{
            "Diablo III"   = "battlenet://DiabloIII"
            "StarCraft II" = "battlenet://S2"
            "Overwatch 2"  = "battlenet://Pro"
            "Hearthstone"  = "battlenet://WTCG"
            "World of Warcraft" = "battlenet://WoW"
            "Diablo IV"    = "battlenet://Fen"
        }
        if ($blizzURIs.ContainsKey($game.Name)) {
            Write-Host "   -> URI Battle.net: $($blizzURIs[$game.Name])" -ForegroundColor DarkGray
            $action = "[`"$($blizzURIs[$game.Name])`"]"
        }
        elseif ($bestMatch -and $bestMatch.Score -gt 0) {
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



    # --- INICIO DE INTEGRACIÓN IMAGEMAGICK 
    # --- CONFIGURACIÓN DE RUTAS ---
    $absolutePath = "$PSScriptRoot\@Resources\$($game.ID).jpg"
    $processedPath = "$PSScriptRoot\@Resources\cache\$($game.ID)_blur.png"
    $relativeProcessed = "#@#cache\$($game.ID)_blur.png"
    
    # Crear carpeta de caché si no existe
    if (!(Test-Path "$PSScriptRoot\@Resources\cache")) { 
        New-Item -ItemType Directory -Path "$PSScriptRoot\@Resources\cache" -Force > $null 
    }
    
    # --- LÓGICA DE GENERACIÓN ---
    if (Test-Path $absolutePath) {
        if (!(Test-Path $processedPath)) {
            Write-Host "Generando carátula con bordes suaves: $($game.ID)" -ForegroundColor Yellow
            
            # Argumentos: Recorte rectangular con esquinas de radio 25 y blur de 10
            # --- LÓGICA DE GENERACIÓN ---
            if (Test-Path $absolutePath) {
                if (!(Test-Path $processedPath)) {
                    Write-Host "Generando carátula: $($game.ID)" -ForegroundColor Yellow
                    
                    # Usamos -virtual-pixel transparent y -blur para suavizar los bordes
                    # sin necesidad de dibujar máscaras que rompan el comando.
                    $magickArgs = @(
                        "`"$absolutePath`"",
                        "-alpha", "set",
                        "-virtual-pixel", "transparent",
                        "-channel", "A",
                        "-blur", "0x12",
                        "-level", "50%,100%",
                        "+channel",
                        "`"$processedPath`""
                    )
                    
                    Start-Process -FilePath "magick" -ArgumentList $magickArgs -NoNewWindow -Wait
                }
                $finalImage = $relativeProcessed
            }
            
            # Ejecución directa
            Start-Process -FilePath "magick" -ArgumentList $magickArgs -NoNewWindow -Wait
        }
        else {
            # Descomenta la siguiente línea si quieres ver qué imágenes ya estaban en caché
            # Write-Host "Imagen ya en caché: $($game.ID)" -ForegroundColor DarkGray
        }
        $finalImage = $relativeProcessed
    }
    else {
        $finalImage = "#@#default.jpg"
    }
    # --- FIN DE INTEGRACIÓN ---
   
  



    # --- CONSTRUCCIÓN DE LOS METERS ---
    # 1. El Meter de la carátula (Fondo)
    # 2. El Meter del Icono (Superpuesto) usando $game.Type
    # Definimos la comilla doble para evitar errores de escape en PowerShell
    # Definimos la comilla doble para evitar errores de escape en PowerShell
    $q = '"'

$incContent += @"

[Texture$count]
Meter=Image
ImageName=#@#texturas\texture1.png
W=($CWidth + 20)
H=$CHeight
X=($posX - 10)
Y=$posY
Tile=1
ImageAlpha=20
Group=Games

[Game$count]
Meter=Image
ImageName=$finalImage
ImageNotFound=#@#default.jpg
W=$CWidth
H=$CHeight
X=$posX
Y=$posY
PreserveAspectRatio=1
ImageAlpha=220
LeftMouseUpAction=$action
Group=Games
TransformationMatrix=1;0;0;1;0;0
MouseOverAction=[!SetOption Game$count ImageAlpha 255][!SetOption Game$count TransformationMatrix "1.05;0;0;1.05;$(-$posX * 0.05);$(-$posY * 0.05)"][!SetOption Texture$count ImageAlpha 120][!SetVariable NombreJuego $($q)$($game.Name)$($q)][!SetVariable IconoJuego $($q)#@#Icons\$($game.Type).png$($q)][!UpdateMeterGroup "GrupoInfo"][!Redraw]
MouseLeaveAction=[!SetOption Game$count ImageAlpha 180][!SetOption Game$count TransformationMatrix "1;0;0;1;0;0"][!SetOption Texture$count ImageAlpha 20][!SetVariable NombreJuego "" ][!SetVariable IconoJuego "" ][!UpdateMeterGroup "GrupoInfo"][!Redraw]

[Icon$count]
Meter=Image
ImageName=#@#Icons\$($game.Type).png
W=24
H=24
X=($posX + $CWidth - 28)
Y=($posY + 4)
Hidden=1
Group=Games
DynamicVariables=1
"@
    $count++
    if ($ModoGrid -eq "Manual" -and $count -ge 100) { break }
}
# ... (El resto del guardado del archivo y Refresh de Rainmeter) ...

# --- GUARDADO FINAL DEL ARCHIVO .INC ---

# Preparamos el encabezado con el modo que decidió el switch
$header = "[Variables]`nTotalGames=$count`nUltimaFecha=$((Get-Date).ToString("d 'de' MMMM 'del' yyyy"))`nVariableModo=$ModoGrid`n"

# Escribimos el archivo (asegurando UTF8 para Rainmeter)
($header + $incContent) | Out-File -FilePath $outputFile -Encoding unicode -Force

# Refrescamos el skin para ver los cambios al instante
if (Test-Path "C:\Program Files\Rainmeter\Rainmeter.exe") {
    & "C:\Program Files\Rainmeter\Rainmeter.exe" !Refresh "$skinName"
}

# ==========================================
# 6. Generación del HTML para Gallery (YASB)
# ==========================================

# ==========================================
# 6. Generación del HTML para Gallery (YASB)
# ==========================================

function Generate-GalleryHTML {
    param(
        [array]$Games,
        [string]$OutputDir,
        [string]$SkinName
    )

    $htmlPath = Join-Path $OutputDir "gallery.html"

    # Carpeta de imágenes accesible por el HTML
    $galleryImgDir = Join-Path $OutputDir "gallery_images"
    if (!(Test-Path $galleryImgDir)) {
        New-Item -ItemType Directory -Path $galleryImgDir -Force | Out-Null
    }

    # Copiar iconos de plataforma a gallery_images
    $iconsDir = Join-Path $OutputDir "Icons"
    foreach ($platform in @("Steam", "Epic", "Blizzard")) {
        $srcIcon  = Join-Path $iconsDir "$platform.png"
        $destIcon = Join-Path $galleryImgDir "$platform.png"
        if ((Test-Path $srcIcon) -and !(Test-Path $destIcon)) {
            Copy-Item $srcIcon $destIcon -Force
        }
    }

    # Construir array JSON de juegos
    $cardsJson = ($Games | Sort-Object Name | ForEach-Object {
        $game = $_

        # Imagen: primero intentar cache blur, luego .jpg original
        $cacheImg  = Join-Path $OutputDir "cache\$($game.ID)_blur.png"
        $srcImg    = Join-Path $OutputDir "$($game.ID).jpg"
        $destName  = "$($game.ID).jpg"
        $imgSrc    = "./gallery_images/$destName"

        if (Test-Path $cacheImg) {
            $destName = "$($game.ID)_blur.png"
            $imgSrc   = "./gallery_images/$destName"
            $destImg  = Join-Path $galleryImgDir $destName
            if (!(Test-Path $destImg)) { Copy-Item $cacheImg $destImg -Force }
        }
        elseif (Test-Path $srcImg) {
            $destImg = Join-Path $galleryImgDir $destName
            if (!(Test-Path $destImg)) { Copy-Item $srcImg $destImg -Force }
        }
        else {
            $imgSrc = "./default.jpg"
        }

        # URI de lanzamiento
        $blizzURIs = @{
            "Diablo III"   = "battlenet://DiabloIII"
            "StarCraft II" = "battlenet://S2"
            "Overwatch 2"  = "battlenet://Pro"
            "Hearthstone"  = "battlenet://WTCG"
            "World of Warcraft" = "battlenet://WoW"
            "Diablo IV"    = "battlenet://Fen"
        }
        $uri = switch ($game.Type) {
            "Steam"    { "steam://rungameid/$($game.ID)" }
            "Epic"     { $game.LaunchURI }
            "Blizzard" {
                if ($blizzURIs.ContainsKey($game.Name)) { $blizzURIs[$game.Name] }
                else { "battlenet://" }
            }
            default    { "" }
        }

        $name = ($game.Name -replace "`r`n|`r|`n", " ").Trim(); $name = $name -replace '"', '\"' -replace "'", "\'"
        $type = $game.Type

        "{`"id`":`"$($game.ID)`",`"name`":`"$name`",`"type`":`"$type`",`"img`":`"$imgSrc`",`"uri`":`"$uri`"}"
    }) -join ",`n"

    $totalGames = $Games.Count

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Nexus Grid — Gallery</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root {
    --bg:         #0d0d0f;
    --surface:    #131316;
    --border:     #1e1e24;
    --accent:     #c18dab;
    --accent2:    #ff9f50;
    --text:       #e0e0e0;
    --muted:      #555560;
    --steam:      #1a9fff;
    --epic:       #2ecc71;
    --blizzard:   #00aeff;
    --card-w:     110px;
    --card-h:     165px;
    --gap:        14px;
    --radius:     10px;
  }

  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  html, body {
    background: transparent;
    color: var(--text);
    font-family: 'Space Grotesk', sans-serif;
    overflow: hidden;
    user-select: none;
  }

  #app {
    display: flex;
    flex-direction: column;
    background: rgba(13, 13, 15, 0.90);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
    border-radius: 14px;
    border: 1px solid rgba(255,255,255,0.06);
  }

  #topbar {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 8px 16px;
    background: rgba(19, 19, 22, 0.85);
    border-bottom: 1px solid var(--border);
    border-radius: 14px 14px 0 0;
    flex-shrink: 0;
    -webkit-app-region: drag;
  }

  /* Elementos dentro del topbar no deben ser arrastrables */
  #topbar > * { -webkit-app-region: no-drag; }

  #logo {
    font-size: 13px;
    font-weight: 700;
    color: var(--accent2);
    letter-spacing: 0.12em;
    text-transform: uppercase;
    white-space: nowrap;
  }

  #search-wrap { flex: 1; position: relative; max-width: 380px; }
  #search-wrap svg {
    position: absolute; left: 10px; top: 50%;
    transform: translateY(-50%); opacity: 0.4; pointer-events: none;
  }
  #search {
    width: 100%;
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: 8px;
    color: var(--text);
    font-family: inherit;
    font-size: 13px;
    padding: 7px 12px 7px 34px;
    outline: none;
    transition: border-color 0.2s;
  }
  #search:focus { border-color: var(--accent); }
  #search::placeholder { color: var(--muted); }

  #filters { display: flex; gap: 6px; flex-shrink: 0; }
  .filter-btn {
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: 6px;
    color: var(--muted);
    font-family: inherit;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.06em;
    padding: 5px 10px;
    cursor: pointer;
    transition: all 0.18s;
    text-transform: uppercase;
  }
  .filter-btn:hover  { border-color: var(--accent); color: var(--accent); }
  .filter-btn.active { background: var(--accent); border-color: var(--accent); color: #0d0d0f; }
  .filter-btn[data-type="Steam"].active   { background: var(--steam);    border-color: var(--steam);    color: #fff; }
  .filter-btn[data-type="Epic"].active    { background: var(--epic);     border-color: var(--epic);     color: #fff; }
  .filter-btn[data-type="Blizzard"].active{ background: var(--blizzard); border-color: var(--blizzard); color: #fff; }

  #count { font-size: 11px; color: var(--muted); white-space: nowrap; }
  #count span { color: var(--accent2); font-weight: 600; }



  /* Grid */
  #grid-wrap {
    overflow: visible;
    padding: 20px;
    position: relative;
  }

  #grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, var(--card-w));
    gap: var(--gap);
    justify-content: center;
  }

  /* Card */
  .card {
    position: relative;
    width: var(--card-w); height: var(--card-h);
    border-radius: var(--radius);
    overflow: hidden;
    cursor: pointer;
    transition: transform 0.22s cubic-bezier(.34,1.4,.64,1), box-shadow 0.22s;
    background: var(--surface);
    border: 1px solid var(--border);
    animation: fadeIn 0.3s ease both;
  }
  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(8px) scale(0.97); }
    to   { opacity: 1; transform: translateY(0) scale(1); }
  }
  .card:hover {
    transform: scale(1.07) translateY(-3px);
    box-shadow: 0 12px 36px rgba(0,0,0,0.55), 0 0 0 1px var(--accent);
    z-index: 10;
  }
  .card > .cover { width: 100%; height: 100%; object-fit: cover; display: block; transition: filter 0.22s; }
  .card:hover > .cover { filter: brightness(1.08); }

  /* Badge con icono PNG */
  .badge {
    position: absolute; top: 5px; right: 5px;
    width: 20px; height: 20px;
    border-radius: 5px;
    overflow: hidden;
    opacity: 0.9;
    backdrop-filter: blur(4px);
    background: rgba(0,0,0,0.45);
    display: flex; align-items: center; justify-content: center;
  }
  .badge img { width: 14px; height: 14px; object-fit: contain; }

  /* Tooltip nombre */
  .card-tooltip {
    position: absolute; bottom: 0; left: 0; right: 0;
    background: linear-gradient(transparent, rgba(0,0,0,0.88) 60%);
    padding: 18px 6px 6px;
    font-size: 10px; font-weight: 500; color: #fff; line-height: 1.2;
    opacity: 0; transform: translateY(4px);
    transition: opacity 0.18s, transform 0.18s; pointer-events: none;
  }
  .card:hover .card-tooltip { opacity: 1; transform: translateY(0); }

  #empty { display: none; flex-direction: column; align-items: center; justify-content: center; height: 100%; gap: 12px; color: var(--muted); }
  #empty.visible { display: flex; }
  #empty svg { opacity: 0.3; }
  #empty p { font-size: 14px; }

  #grid-wrap { scrollbar-gutter: stable; }
  .card:nth-child(1)    { animation-delay: 0ms }
  .card:nth-child(2)    { animation-delay: 15ms }
  .card:nth-child(3)    { animation-delay: 30ms }
  .card:nth-child(4)    { animation-delay: 45ms }
  .card:nth-child(5)    { animation-delay: 60ms }
  .card:nth-child(6)    { animation-delay: 75ms }
  .card:nth-child(7)    { animation-delay: 90ms }
  .card:nth-child(8)    { animation-delay: 105ms }
  .card:nth-child(9)    { animation-delay: 120ms }
  .card:nth-child(10)   { animation-delay: 135ms }
  .card:nth-child(n+11) { animation-delay: 150ms }
</style>
</head>
<body>
<div id="app">
  <div id="topbar">
    <div id="logo">󰊴 Nexus Grid</div>
    <div id="search-wrap">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
      </svg>
      <input id="search" type="text" placeholder="Buscar juego..." autocomplete="off" spellcheck="false">
    </div>
    <div id="filters">
      <button class="filter-btn active" data-type="All">Todos</button>
      <button class="filter-btn" data-type="Steam">Steam</button>
      <button class="filter-btn" data-type="Epic">Epic</button>
      <button class="filter-btn" data-type="Blizzard">Blizzard</button>
    </div>
    <div id="count"><span id="visible-count">$totalGames</span> / $totalGames juegos</div>
  </div>
  <div id="grid-wrap">
    <div id="grid"></div>
    <div id="empty">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
        <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
      </svg>
      <p>Sin resultados para esa búsqueda</p>
    </div>
  </div>
</div>
<script>
const GAMES = [
$cardsJson
];
const TOTAL    = GAMES.length;
const grid     = document.getElementById('grid');
const searchEl = document.getElementById('search');
const emptyEl  = document.getElementById('empty');
const countEl  = document.getElementById('visible-count');
const filterBtns = document.querySelectorAll('.filter-btn');
let activeFilter = 'All';
let searchTerm   = '';

function sendToAhk(obj) {
  if (window.chrome && window.chrome.webview)
    window.chrome.webview.postMessage(JSON.stringify(obj));
}

// Ajustar SOLO el alto de la ventana al contenido del grid (ancho fijo)
function fitWindow() {
  requestAnimationFrame(() => {
    const topbarH = document.getElementById('topbar').offsetHeight;
    const gridEl  = document.getElementById('grid');
    const pad     = 20;

    // Medir el alto real del grid después de renderizar
    const gridH  = gridEl.offsetHeight;
    const totalH = topbarH + pad + gridH + pad;

    sendToAhk({ action: 'resize_h', h: Math.ceil(totalH) });
  });
}

function renderGrid() {
  const term = searchTerm.toLowerCase();
  const filtered = GAMES.filter(g => {
    const matchType = activeFilter === 'All' || g.type === activeFilter;
    const matchName = g.name.toLowerCase().includes(term);
    return matchType && matchName;
  });
  countEl.textContent = filtered.length;
  grid.innerHTML = '';
  emptyEl.classList.toggle('visible', filtered.length === 0);
  filtered.forEach(g => {
    const card = document.createElement('div');
    card.className = 'card';
    const cover = document.createElement('img');
    cover.className = 'cover';
    cover.src     = g.img;
    cover.alt     = g.name;
    cover.loading = 'lazy';
    cover.onerror = () => { cover.src = './default.jpg'; };
    const badge = document.createElement('div');
    badge.className = 'badge';
    const badgeImg = document.createElement('img');
    badgeImg.src = './gallery_images/' + g.type + '.png';
    badgeImg.alt = g.type;
    badge.appendChild(badgeImg);
    const tooltip = document.createElement('div');
    tooltip.className = 'card-tooltip';
    tooltip.textContent = g.name;
    card.append(cover, badge, tooltip);
    card.addEventListener('click', () => sendToAhk({ action: 'launch', uri: g.uri }));
    grid.appendChild(card);
  });
  fitWindow();
}

// Búsqueda
searchEl.addEventListener('input', () => { searchTerm = searchEl.value; renderGrid(); });

// Filtros
filterBtns.forEach(btn => {
  btn.addEventListener('click', () => {
    filterBtns.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    activeFilter = btn.dataset.type;
    renderGrid();
  });
});

// Teclas
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') sendToAhk({ action: 'close' });
  if ((e.ctrlKey || e.metaKey) && e.key === 'f') { e.preventDefault(); searchEl.focus(); }
});

renderGrid();
</script>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8 -Force
    Write-Host "`n[GALLERY] HTML generado: $htmlPath" -ForegroundColor Green
    Write-Host "[GALLERY] Total juegos incluidos: $($Games.Count)" -ForegroundColor Green
}

# Llamada condicional — solo se ejecuta si se pasa -GenerateHTML
if ($GenerateHTML) {
    Generate-GalleryHTML -Games $allGames -OutputDir $outputDir -SkinName $skinName
}

Write-Host "`nPROCESO TERMINADO - MODO ACTUAL: $ModoGrid" -ForegroundColor Magenta
