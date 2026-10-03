-- Restore workspace layouts saved by omarchy-hyprland-workspace-layout-toggle.

local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

-- Hardcoded to ~/.local/state to match omarchy-hyprland-workspace-layout-toggle,
-- which writes there regardless of XDG_STATE_HOME, and bootstrap.lua's
-- package.path, which resolves omarchy.workspace-layouts.* there too.
local layouts_dir = paths.home .. "/.local/state/omarchy/workspace-layouts"

require_all.files(layouts_dir, "omarchy.workspace-layouts", { reload = true })
