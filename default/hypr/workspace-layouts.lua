-- Restore workspace layouts saved by omarchy-hyprland-workspace-layout-toggle.

local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

-- Hardcoded to ~/.local/state to match the writer, which ignores XDG_STATE_HOME,
-- and the bootstrap package.path that resolves omarchy.workspace-layouts.* modules.
local layouts_dir = paths.home .. "/.local/state/omarchy/workspace-layouts"

require_all.files(layouts_dir, "omarchy.workspace-layouts", { reload = true })
