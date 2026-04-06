"""
Nexus Grid — Games Library Widget para YASB
Coloca este archivo en: C:/Users/{tu usuario}/.config/yasb/src/core/widgets/yasb/games_library.py
(o donde tengas instalado YASB, en la carpeta core/widgets/yasb/)
"""

import os
import json
import subprocess
import logging
from PyQt6.QtWidgets import (
    QLabel, QHBoxLayout, QVBoxLayout, QWidget,
    QScrollArea, QGridLayout, QFrame, QApplication, QSizePolicy
)
from PyQt6.QtGui import QPixmap, QCursor, QColor, QPainter, QPainterPath
from PyQt6.QtCore import Qt, QSize, QThread, pyqtSignal, QPoint, QTimer, QPropertyAnimation, QEasingCurve, QRect

from core.widgets.base import BaseWidget
from core.validation.widgets.yasb.games_library import GamesLibraryConfig

logger = logging.getLogger(__name__)


# ── Hilo para leer el .inc sin bloquear la UI ──────────────────────────────
class GamesLoaderThread(QThread):
    loaded = pyqtSignal(list)

    def __init__(self, inc_path: str, resources_path: str):
        super().__init__()
        self.inc_path = inc_path
        self.resources_path = resources_path

    def run(self):
        games = []
        try:
            if not os.path.exists(self.inc_path):
                self.loaded.emit([])
                return

            content = open(self.inc_path, encoding="utf-16").read()
            import re

            # Extraer bloques [GameN]
            blocks = re.findall(
                r'\[Game(\d+)\](.*?)(?=\[Game\d+\]|\[Icon\d+\]|\[Texture\d+\]|$)',
                content, re.DOTALL
            )

            for idx, block in blocks:
                img_match  = re.search(r'ImageName=([^\n]+)', block)
                left_match = re.search(r'LeftMouseUpAction=\["?([^"\]\n]+)"?\]', block)
                name_match = re.search(r'NombreJuego\s+"?([^"\]]+)"?', block)

                img_rel = img_match.group(1).strip() if img_match else ""
                # Convierte rutas relativas Rainmeter (#@#...) a absolutas
                img_abs = img_rel.replace("#@#", self.resources_path + os.sep)

                uri     = left_match.group(1).strip() if left_match else ""
                name    = name_match.group(1).strip() if name_match else f"Juego {idx}"

                # Inferir nombre desde URI si no hay variable
                if not name or name == f"Juego {idx}":
                    if "rungameid" in uri:
                        name = f"Steam #{uri.split('/')[-1]}"
                    elif "epicgames" in uri.lower():
                        name = "Epic Game"
                    else:
                        name = os.path.basename(uri).replace(".exe", "")

                # Inferir tipo desde URI
                if "steam://" in uri:
                    gtype = "Steam"
                elif "epicgames" in uri.lower():
                    gtype = "Epic"
                else:
                    gtype = "Blizzard"

                games.append({
                    "index": int(idx),
                    "name":  name,
                    "type":  gtype,
                    "img":   img_abs,
                    "uri":   uri,
                })

        except Exception as e:
            logger.error(f"[GamesLibrary] Error leyendo .inc: {e}")

        self.loaded.emit(games)


# ── Card individual ────────────────────────────────────────────────────────
class GameCard(QFrame):
    BADGE_COLORS = {
        "Steam":    "#1a9fff",
        "Epic":     "#2ecc71",
        "Blizzard": "#00aeff",
    }

    def __init__(self, game: dict, card_w: int, card_h: int, radius: int, parent=None):
        super().__init__(parent)
        self.game    = game
        self.card_w  = card_w
        self.card_h  = card_h
        self.radius  = radius
        self.setFixedSize(card_w, card_h)
        self.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.setObjectName("game-card")

        # Imagen
        self._pixmap = None
        self._load_image()

        # Tooltip con el nombre
        self.setToolTip(game["name"])

    def _load_image(self):
        path = self.game.get("img", "")
        # Intentar cache blur primero, luego original
        cache_path = path.replace(".jpg", "_blur.png") if "_blur" not in path else path
        for p in [cache_path, path]:
            if p and os.path.exists(p):
                self._pixmap = QPixmap(p)
                return
        self._pixmap = None

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)

        # Clip con esquinas redondeadas
        path = QPainterPath()
        path.addRoundedRect(0, 0, self.card_w, self.card_h, self.radius, self.radius)
        painter.setClipPath(path)

        # Fondo oscuro
        painter.fillRect(0, 0, self.card_w, self.card_h, QColor("#1a1a22"))

        # Imagen
        if self._pixmap and not self._pixmap.isNull():
            scaled = self._pixmap.scaled(
                self.card_w, self.card_h,
                Qt.AspectRatioMode.KeepAspectRatioByExpanding,
                Qt.TransformationMode.SmoothTransformation
            )
            x = (self.card_w  - scaled.width())  // 2
            y = (self.card_h  - scaled.height()) // 2
            painter.drawPixmap(x, y, scaled)
        else:
            # Placeholder
            painter.fillRect(0, 0, self.card_w, self.card_h, QColor("#1e1e2e"))
            painter.setPen(QColor("#444455"))
            painter.drawText(
                QRect(0, 0, self.card_w, self.card_h),
                Qt.AlignmentFlag.AlignCenter,
                "?"
            )

        # Badge de plataforma (círculo de color en esquina)
        badge_color = self.BADGE_COLORS.get(self.game.get("type", ""), "#888888")
        painter.setClipping(False)
        painter.setBrush(QColor(badge_color))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawEllipse(self.card_w - 14, 5, 9, 9)

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            uri = self.game.get("uri", "")
            if uri:
                try:
                    if uri.startswith("steam://") or uri.startswith("com.epicgames"):
                        os.startfile(uri)
                    else:
                        subprocess.Popen([uri], shell=True)
                except Exception as e:
                    logger.error(f"[GamesLibrary] Error lanzando {uri}: {e}")
        super().mousePressEvent(event)

    def enterEvent(self, event):
        self.setStyleSheet("QFrame#game-card { border: 1px solid rgba(193,141,171,0.7); }")
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.setStyleSheet("")
        super().leaveEvent(event)


# ── Popup de la gallery ────────────────────────────────────────────────────
class GamesGalleryPopup(QWidget):
    def __init__(self, games: list, options: dict, bar_widget: QWidget):
        super().__init__(None, Qt.WindowType.Tool | Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)

        self._options    = options
        self._bar_widget = bar_widget
        self._games      = games
        self._setup_ui()
        self._position_popup()
        self._animate_in()

    def _setup_ui(self):
        card_w   = self._options.get("image_width", 110)
        card_h   = self._options.get("image_height", 165)
        spacing  = self._options.get("image_spacing", 12)
        radius   = self._options.get("image_corner_radius", 10)
        per_page = self._options.get("image_per_page", 10)

        # Contenedor con fondo
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)

        self._container = QFrame(self)
        self._container.setObjectName("games-gallery-popup")
        self._container.setStyleSheet("""
            QFrame#games-gallery-popup {
                background-color: rgba(13, 13, 20, 0.96);
                border-radius: 12px;
                border: 1px solid rgba(193,141,171,0.25);
            }
        """)
        outer.addWidget(self._container)

        inner = QVBoxLayout(self._container)
        inner.setContentsMargins(10, 10, 10, 10)
        inner.setSpacing(8)

        # Scroll horizontal (una fila, como el widget de wallpapers)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setStyleSheet("background: transparent;")

        content = QWidget()
        content.setStyleSheet("background: transparent;")
        row = QHBoxLayout(content)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(spacing)

        for game in self._games[:per_page]:
            card = GameCard(game, card_w, card_h, radius)
            row.addWidget(card)

        row.addStretch()
        scroll.setWidget(content)

        # Altura fija del scroll = altura de card + margen
        scroll.setFixedHeight(card_h + 4)
        # Ancho = cards visibles
        popup_w = min(len(self._games), per_page) * (card_w + spacing) + spacing
        popup_w = min(popup_w, QApplication.primaryScreen().geometry().width() - 40)
        self._container.setFixedWidth(popup_w + 20)

        inner.addWidget(scroll)

    def _position_popup(self):
        bar_geo  = self._bar_widget.window().geometry()
        btn_geo  = self._bar_widget.mapToGlobal(QPoint(0, 0))
        popup_w  = self._container.sizeHint().width() + 20
        screen_w = QApplication.primaryScreen().geometry().width()

        x = btn_geo.x()
        x = max(8, min(x, screen_w - popup_w - 8))
        y = bar_geo.bottom() + 6

        self.move(x, y)

    def _animate_in(self):
        self.setWindowOpacity(0)
        self.show()
        anim = QPropertyAnimation(self, b"windowOpacity", self)
        anim.setDuration(180)
        anim.setStartValue(0.0)
        anim.setEndValue(1.0)
        anim.setEasingCurve(QEasingCurve.Type.OutCubic)
        anim.start()
        self._anim = anim

    def _animate_out(self, callback=None):
        anim = QPropertyAnimation(self, b"windowOpacity", self)
        anim.setDuration(140)
        anim.setStartValue(1.0)
        anim.setEndValue(0.0)
        anim.setEasingCurve(QEasingCurve.Type.InCubic)
        if callback:
            anim.finished.connect(callback)
        anim.start()
        self._anim_out = anim

    def close_animated(self):
        self._animate_out(self.close)

    def leaveEvent(self, event):
        # Cerrar al salir del popup
        QTimer.singleShot(120, self._check_close)
        super().leaveEvent(event)

    def _check_close(self):
        if not self.underMouse() and not self._bar_widget.underMouse():
            self.close_animated()


# ── Widget principal ───────────────────────────────────────────────────────
class GamesLibraryWidget(BaseWidget):
    validation_schema = GamesLibraryConfig

    def __init__(
        self,
        label: str,
        class_name: str,
        inc_path: str,
        resources_path: str,
        gallery: dict,
        **kwargs
    ):
        super().__init__(class_name=class_name, **kwargs)
        self._label         = label
        self._inc_path      = inc_path
        self._resources_path = resources_path
        self._gallery       = gallery
        self._games         = []
        self._popup         = None
        self._loader        = None

        self._setup_ui()
        self._load_games()

    def _setup_ui(self):
        self._lbl = QLabel(self._label)
        self._lbl.setObjectName("label")
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self._lbl)
        self.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))

    def _load_games(self):
        self._loader = GamesLoaderThread(self._inc_path, self._resources_path)
        self._loader.loaded.connect(self._on_games_loaded)
        self._loader.start()

    def _on_games_loaded(self, games):
        self._games = games
        count = len(games)
        self._lbl.setToolTip(f"{count} juegos en biblioteca")

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self._toggle_popup()
        super().mousePressEvent(event)

    def _toggle_popup(self):
        if self._popup and self._popup.isVisible():
            self._popup.close_animated()
            self._popup = None
            return

        if not self._games:
            self._load_games()
            # Retry tras breve espera
            QTimer.singleShot(800, self._open_popup)
        else:
            self._open_popup()

    def _open_popup(self):
        if not self._games:
            return
        self._popup = GamesGalleryPopup(self._games, self._gallery, self)
