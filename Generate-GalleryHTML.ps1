# ==========================================
# NEXUS GRID — Generate-GalleryHTML
# Agregar esta función al Core_Browser.ps1
# y llamarla al final del script cuando
# se recibe el parámetro -GenerateHTML
# ==========================================
#
# INSTRUCCIONES DE INTEGRACIÓN:
# 1. Agrega el parámetro al bloque param() existente:
#       param([string]$NuevoModo, [switch]$GenerateHTML)
#
# 2. Copia la función Generate-GalleryHTML completa a tu Core_Browser.ps1
#
# 3. Al final del script (después del Write-Host "PROCESO TERMINADO"),
#    agrega este bloque:
#
#       if ($GenerateHTML) {
#           Generate-GalleryHTML -Games $allGames -OutputDir $outputDir -SkinName $skinName
#       }
#
# 4. Para llamarlo desde Gallery.ahk o Rainmeter, el comando es:
#       powershell.exe -File "Core_Browser.ps1" -GenerateHTML
# ==========================================

function Generate-GalleryHTML {
    param(
        [array]$Games,
        [string]$OutputDir,
        [string]$SkinName
    )

    $htmlPath = Join-Path (Split-Path $OutputDir -Parent) "@Resources\gallery.html"

    # --- Construir los cards JSON para el JS ---
    $cardsJson = ($Games | Sort-Object Name | ForEach-Object {
        $game = $_
        $imgFile = "$($game.ID).jpg"
        $imgPath = Join-Path $OutputDir $imgFile
        $imgSrc  = if (Test-Path $imgPath) { "./gallery_images/$($game.ID).jpg" } else { "./default.jpg" }

        # Copiar imagen a carpeta accesible por el HTML (file://)
        $galleryImgDir = Join-Path $OutputDir "gallery_images"
        if (!(Test-Path $galleryImgDir)) { New-Item -ItemType Directory -Path $galleryImgDir -Force | Out-Null }
        if (Test-Path $imgPath) {
            $destImg = Join-Path $galleryImgDir "$($game.ID).jpg"
            if (!(Test-Path $destImg)) { Copy-Item $imgPath $destImg -Force }
        }

        $uri = switch ($game.Type) {
            "Steam"   { "steam://rungameid/$($game.ID)" }
            "Epic"    { $game.LaunchURI }
            "Blizzard"{ $game.SourcePath -replace '\\', '/' }
            default   { "" }
        }

        $name = $game.Name -replace '"', '\"' -replace "'", "\'"
        $type = $game.Type

        "{`"id`":`"$($game.ID)`",`"name`":`"$name`",`"type`":`"$type`",`"img`":`"$imgSrc`",`"uri`":`"$uri`"}"
    }) -join ",`n"

    $totalGames = $Games.Count

    # --- HTML ---
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
    height: 100%;
    background: var(--bg);
    color: var(--text);
    font-family: 'Space Grotesk', sans-serif;
    overflow: hidden;
    user-select: none;
  }

  /* ── LAYOUT ── */
  #app {
    display: flex;
    flex-direction: column;
    height: 100vh;
  }

  /* ── TOPBAR ── */
  #topbar {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 12px 20px;
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  #logo {
    font-size: 13px;
    font-weight: 700;
    color: var(--accent2);
    letter-spacing: 0.12em;
    text-transform: uppercase;
    white-space: nowrap;
  }

  #search-wrap {
    flex: 1;
    position: relative;
    max-width: 380px;
  }

  #search-wrap svg {
    position: absolute;
    left: 10px;
    top: 50%;
    transform: translateY(-50%);
    opacity: 0.4;
    pointer-events: none;
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

  /* Filtros de plataforma */
  #filters {
    display: flex;
    gap: 6px;
    flex-shrink: 0;
  }

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

  #count {
    font-size: 11px;
    color: var(--muted);
    white-space: nowrap;
    margin-left: auto;
    padding-right: 4px;
  }
  #count span { color: var(--accent2); font-weight: 600; }

  /* ── GRID ── */
  #grid-wrap {
    flex: 1;
    overflow-y: auto;
    padding: 20px;
    scrollbar-width: thin;
    scrollbar-color: var(--border) transparent;
  }
  #grid-wrap::-webkit-scrollbar       { width: 5px; }
  #grid-wrap::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }

  #grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, var(--card-w));
    gap: var(--gap);
    justify-content: start;
  }

  /* ── CARD ── */
  .card {
    position: relative;
    width: var(--card-w);
    height: var(--card-h);
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

  .card img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
    transition: filter 0.22s;
  }
  .card:hover img { filter: brightness(1.08); }

  /* Badge de plataforma */
  .badge {
    position: absolute;
    top: 5px;
    right: 5px;
    width: 18px;
    height: 18px;
    border-radius: 4px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 9px;
    font-weight: 800;
    letter-spacing: 0;
    opacity: 0.85;
    backdrop-filter: blur(6px);
  }
  .badge-Steam    { background: var(--steam);    color: #fff; }
  .badge-Epic     { background: var(--epic);     color: #fff; }
  .badge-Blizzard { background: var(--blizzard); color: #fff; }

  /* Tooltip nombre */
  .card-tooltip {
    position: absolute;
    bottom: 0; left: 0; right: 0;
    background: linear-gradient(transparent, rgba(0,0,0,0.88) 60%);
    padding: 18px 6px 6px;
    font-size: 10px;
    font-weight: 500;
    color: #fff;
    line-height: 1.2;
    opacity: 0;
    transform: translateY(4px);
    transition: opacity 0.18s, transform 0.18s;
    pointer-events: none;
  }
  .card:hover .card-tooltip {
    opacity: 1;
    transform: translateY(0);
  }

  /* Estado vacío */
  #empty {
    display: none;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    gap: 12px;
    color: var(--muted);
  }
  #empty.visible { display: flex; }
  #empty svg { opacity: 0.3; }
  #empty p { font-size: 14px; }

  /* ── SCROLLBAR INVISIBLE en Firefox ── */
  #grid-wrap { scrollbar-gutter: stable; }

  /* Animación stagger */
  .card:nth-child(1)  { animation-delay: 0ms }
  .card:nth-child(2)  { animation-delay: 15ms }
  .card:nth-child(3)  { animation-delay: 30ms }
  .card:nth-child(4)  { animation-delay: 45ms }
  .card:nth-child(5)  { animation-delay: 60ms }
  .card:nth-child(6)  { animation-delay: 75ms }
  .card:nth-child(7)  { animation-delay: 90ms }
  .card:nth-child(8)  { animation-delay: 105ms }
  .card:nth-child(9)  { animation-delay: 120ms }
  .card:nth-child(10) { animation-delay: 135ms }
  .card:nth-child(n+11) { animation-delay: 150ms }

</style>
</head>
<body>
<div id="app">

  <!-- TOPBAR -->
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

  <!-- GRID -->
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

const TOTAL = GAMES.length;
const grid = document.getElementById('grid');
const searchEl = document.getElementById('search');
const emptyEl  = document.getElementById('empty');
const countEl  = document.getElementById('visible-count');
const filterBtns = document.querySelectorAll('.filter-btn');

let activeFilter = 'All';
let searchTerm   = '';

function badgeLabel(type) {
  if (type === 'Steam')    return 'S';
  if (type === 'Epic')     return 'E';
  if (type === 'Blizzard') return 'B';
  return '?';
}

function renderGrid() {
  const term = searchTerm.toLowerCase();
  const filtered = GAMES.filter(g => {
    const matchType = activeFilter === 'All' || g.type === activeFilter;
    const matchName = g.name.toLowerCase().includes(term);
    return matchType && matchName;
  });

  // Actualizar contador
  countEl.textContent = filtered.length;

  // Vaciar grid
  grid.innerHTML = '';
  emptyEl.classList.toggle('visible', filtered.length === 0);

  // Crear cards
  filtered.forEach((g, i) => {
    const card = document.createElement('div');
    card.className = 'card';

    const img = document.createElement('img');
    img.src     = g.img;
    img.alt     = g.name;
    img.loading = 'lazy';
    img.onerror = () => { img.src = './default.jpg'; };

    const badge = document.createElement('div');
    badge.className = `badge badge-\${g.type}`;
    badge.textContent = badgeLabel(g.type);

    const tooltip = document.createElement('div');
    tooltip.className = 'card-tooltip';
    tooltip.textContent = g.name;

    card.append(img, badge, tooltip);

    card.addEventListener('click', () => {
      if (window.chrome && window.chrome.webview) {
        // Enviar mensaje a AHK para lanzar el juego
        window.chrome.webview.postMessage(JSON.stringify({ action: 'launch', uri: g.uri }));
      } else {
        // Fallback para debug en navegador
        console.log('Launch:', g.uri);
      }
    });

    grid.appendChild(card);
  });
}

// Búsqueda
searchEl.addEventListener('input', () => {
  searchTerm = searchEl.value;
  renderGrid();
});

// Filtros
filterBtns.forEach(btn => {
  btn.addEventListener('click', () => {
    filterBtns.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    activeFilter = btn.dataset.type;
    renderGrid();
  });
});

// Tecla Escape → cerrar ventana
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(JSON.stringify({ action: 'close' }));
    }
  }
  if (e.key === 'f' && (e.ctrlKey || e.metaKey)) {
    e.preventDefault();
    searchEl.focus();
  }
});

// Render inicial
renderGrid();
</script>
</body>
</html>
"@

    # Guardar
    $html | Out-File -FilePath $htmlPath -Encoding UTF8 -Force
    Write-Host "`n[GALLERY] HTML generado: $htmlPath" -ForegroundColor Green
    Write-Host "[GALLERY] Total juegos incluidos: $($Games.Count)" -ForegroundColor Green
}
