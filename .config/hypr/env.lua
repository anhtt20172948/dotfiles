hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("QT_QPA_PLATFORMTHEME_QT6", "gtk3")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("TERMINAL", "kitty")
-- AQ_DRM_DEVICES is intentionally not set: a hardcoded /dev/dri/cardN breaks
-- when probe order changes, and the by-path names contain ":" which aquamarine
-- treats as the device-list separator. Aquamarine auto-detects the GPU.

hl.env("XCURSOR_THEME", "default")
hl.env("HYPRCURSOR_THEME", "default")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
