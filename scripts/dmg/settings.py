"""dmgbuild settings for Ortus.dmg. Run by scripts/make-dmg.sh, which passes -D app=<path> -D here=<this folder>.

The window is fixed at 600x340 (content; the window adds the 28pt title bar) with no toolbar, sidebar, status or path bar. The
background (background.png and background@2x.png beside this file) has the headline
and the arrow; the two icons sit on its left and right at the same height as the arrow.
"""
import os

here = defines["here"]  # noqa: F821
app = defines["app"]  # noqa: F821  (dmgbuild injects `defines`)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

background = os.path.join(here, "background.png")  # dmgbuild also picks up background@2x.png
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
window_rect = ((200, 120), (600, 368))
default_view = "icon-view"

icon_size = 112
text_size = 13
arrange_by = None
label_pos = "bottom"
icon_locations = {
    app_name: (170, 215),
    "Applications": (430, 215),
}
