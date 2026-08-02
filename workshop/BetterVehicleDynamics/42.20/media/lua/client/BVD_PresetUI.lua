-- BVD_PresetUI.lua — when the Mode combobox changes in the sandbox UI,
-- cascade the preset's values to the affected option widgets so the player
-- sees the numbers update immediately (instead of only on next reload).
--
-- This patches SandboxOptionsScreen:onComboBoxSelected, which fires on any
-- combo change. We super-call the original first, then layer on our cascade.

require "OptionScreens/SandboxOptions"
require "ISUI/AdminPanel/ISServerSandboxOptionsUI"

local PRESET_OPTION_NAME = "BetterVehicleDynamics.Mode"
local OPTION_PREFIX      = "BetterVehicleDynamics."

local function cascadePreset(self, combo, optionName)
    if optionName ~= PRESET_OPTION_NAME then return end
    if not (BVD and BVD.getPresetName and BVD.getPresetValues) then return end

    local presetName = BVD.getPresetName(combo.selected)
    if presetName == "Custom" then return end

    local values = BVD.getPresetValues(presetName)
    if not values then return end

    for key, val in pairs(values) do
        local control = self.controls and self.controls[OPTION_PREFIX .. key]
        if control then
            if type(val) == "boolean" and control.setSelected then
                control:setSelected(1, val)
            elseif control.setText then
                control:setText(tostring(val))
            end
        end
    end
end

local function patchClass(cls)
    if not cls then return end
    local original = cls.onComboBoxSelected
    cls.onComboBoxSelected = function(self, combo, optionName)
        if original then original(self, combo, optionName) end
        cascadePreset(self, combo, optionName)
    end
end

patchClass(SandboxOptionsScreen)     -- main-menu newgame screen
patchClass(ISServerSandboxOptionsUI) -- in-game pause-menu screen
