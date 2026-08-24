# dmgbuild settings (scripts/dmg.sh drives this). The window is 660x500;
# icons ride at y=430 so Finder's own labels clip below the window edge —
# the white captions live in the background art, identical for every
# viewer regardless of light or dark mode.
import os.path

app = defines.get("app", "dist/Chiaro.app")  # noqa: F821
appname = os.path.basename(app)

format = "ULFO"
files = [app]
symlinks = {"Applications": "/Applications"}

background = "scripts/dmg-bg.tiff"
window_rect = ((400, 200), (660, 500))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 116
text_size = 12
arrange_by = None
icon_locations = {
    appname: (165, 388),
    "Applications": (495, 388),
    ".background.tiff": (165, 900),
    ".VolumeIcon.icns": (495, 900),
    ".DS_Store": (330, 900),
    ".Trashes": (330, 900),
    ".fseventsd": (495, 900),
}
