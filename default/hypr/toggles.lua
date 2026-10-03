local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

local toggles_dir = paths.state_home .. "/omarchy/toggles/hypr"
local toggles_package_path = toggles_dir .. "/?.lua;"
if not (";" .. package.path):find(";" .. toggles_package_path, 1, true) then
  package.path = toggles_package_path .. package.path
end

-- touchpad-disabled.lua / touchscreen-disabled.lua were generated Lua in older
-- versions and could carry an injected USB device name. They must never be loaded
-- as code again: exclude them so a not-yet-migrated install cannot execute a
-- leftover payload on reload. The migration recovers the name and deletes them.
require_all.files(toggles_dir, nil, {
  reload = true,
  exclude = {
    ["touchpad-disabled"] = true,
    ["touchscreen-disabled"] = true,
  },
})

local disabled_input_device = require("default.hypr.disabled-input-device")
disabled_input_device("touchpad")
disabled_input_device("touchscreen")

require("default.hypr.workspace-layouts")
