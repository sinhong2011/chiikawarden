# dmgbuild settings for the release DMG (scripts/release.sh). Run from the repository root:
#   dmgbuild -s scripts/dmg-settings.py -D app=path/to/Triwarden.app "Triwarden 1.2.3" out.dmg
# The background and the icon positions come from Design/DMG/generate.py; keep them in step.
import os

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)

format = "UDZO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}

# The app's own icon on a removable-disk icon, for the mounted volume.
badge_icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

background = "Design/DMG/background.tiff"
window_rect = ((200, 300), (660, 400))  # origin is bottom-left, in screen points
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 175),
    "Applications": (490, 175),
}
