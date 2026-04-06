"""
Schema de validación para GamesLibraryWidget.
Coloca este archivo en:
  core/validation/widgets/yasb/games_library.py
"""

from core.validation.widgets.base import BaseWidgetConfig
from typing import Any


GamesLibraryConfig = BaseWidgetConfig.extend({
    "label":          {"type": str,  "default": "<span>\uf11b</span>"},
    "class_name":     {"type": str,  "default": "games-library"},
    "inc_path":       {"type": str,  "default": ""},   # Ruta al SteamGames.inc
    "resources_path": {"type": str,  "default": ""},   # Ruta a @Resources/
    "gallery": {
        "type": dict,
        "default": {
            "image_width":         110,
            "image_height":        165,
            "image_spacing":       12,
            "image_corner_radius": 10,
            "image_per_page":      10,
        }
    },
})
