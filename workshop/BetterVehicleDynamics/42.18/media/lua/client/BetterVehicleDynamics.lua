require "PZAPI/ModOptions"

local keyOptions = PZAPI.ModOptions:create("BetterVehicleDynamics",getText("IGUI_BVD_ModOptionsName"))

local Options = PZAPI.ModOptions.Options
function Options:addSmartNumberEntry(id, name, _tooltip, value, min, max)

    local option = { type = "textentry", id = id, name = name, value = tostring(value), tooltip = _tooltip .. " <LINE>Min: "..tostring(min) .. " Max: " .. tostring(max) .. " Default: " .. tostring(value), isEnabled = true, defaultvalue = value, min = min, max = max }

    option.getValue = function(self) return self.value end
    option.setValue = function(self, value)
        self.value = value
        if self.element ~= nil then
            self.element:setText(value)
        end
    end
    option.setEnabled = function(self, bool)
        self.isEnabled = bool
        if self.element ~= nil then
            self.element:setEditable(bool)
        end
    end

    table.insert(self.data, option)
    self.dict[id] = option
    return option
end

function validateOption(option)
	local value = tonumber(option:getValue())
	if value == nil then
		option:setValue(tostring(option.defaultvalue));
	elseif value > option.max then
		option:setValue(tostring(option.max))
	elseif value < option.min then
		option:setValue(tostring(option.min))
	end
	return tonumber(option:getValue());
end

function applyOptions()
-- read options and write LUA table
BetterVehicleDynamicsMod.manualShift = keyOptions:getOption("ManualShift"):getValue();
BetterVehicleDynamicsMod.autoReverse = keyOptions:getOption("AutomaticReverse"):getValue();
BetterVehicleDynamicsMod.skidVolume = keyOptions:getOption("SkidVolume"):getValue();
BetterVehicleDynamicsMod.towSkidding = keyOptions:getOption("TowSkidding"):getValue();
BetterVehicleDynamicsMod.useAnalogThrottle = keyOptions:getOption("UseAnalogThrottle"):getValue();
BetterVehicleDynamicsMod.JoystickThrottle = keyOptions:getOption("JoystickThrottle"):getValue();
BetterVehicleDynamicsMod.CustomizableSteering = keyOptions:getOption("CustomizableSteering"):getValue();

BetterVehicleDynamicsMod.SteeringFactorLowSpeed = validateOption(keyOptions:getOption("SteeringFactorLowSpeed"));
BetterVehicleDynamicsMod.SteeringFactorHighSpeed = validateOption(keyOptions:getOption("SteeringFactorHighSpeed"));
BetterVehicleDynamicsMod.SteeringCenteringLowSpeed = validateOption(keyOptions:getOption("SteeringCenteringLowSpeed"));
BetterVehicleDynamicsMod.SteeringCenteringHighSpeed = validateOption(keyOptions:getOption("SteeringCenteringHighSpeed"));
BetterVehicleDynamicsMod.SteeringSnapback = validateOption(keyOptions:getOption("SteeringSnapback"));
BetterVehicleDynamicsMod.SteeringHighSpeed = validateOption(keyOptions:getOption("SteeringHighSpeed"));
end

keyOptions:addSlider("SkidVolume", getText("IGUI_BVD_SkidVolume"), 0, 1, 0.01, 0.6, getText("IGUI_BVD_SkidVolume_Tooltip"))
keyOptions:addTickBox("TowSkidding", getText("IGUI_BVD_TowedSkidding"), false, getText("IGUI_BVD_TowedSkidding_Tooltip") )
keyOptions:addSeparator()

keyOptions:addDescription(getText("IGUI_BVD_ModOptionHeaderTransmission"))
keyOptions:addTickBox("ManualShift", getText("IGUI_BVD_ManualShift"), false, getText("IGUI_BVD_ManualShift_Tooltip") )
keyOptions:addTickBox("AutomaticReverse", getText("IGUI_BVD_AutomaticReverse"), true, getText("IGUI_BVD_AutomaticReverse_Tooltip"))


keyOptions:addSeparator()
keyOptions:addDescription(getText("IGUI_BVD_ModOptionHeaderKeybinds"))
keyOptions:addTickBox("UseAnalogThrottle", getText("IGUI_BVD_AnalogThrottle"), false, getText("IGUI_BVD_AnalogThrottle_Tooltip") )
keyOptions:addTickBox("JoystickThrottle", getText("IGUI_BVD_JoystickThrottle"), false, getText("IGUI_BVD_JoystickThrottle_Tooltip"))
--keyOptions:addTextEntry("ThrottleAxis", "Throttle Axis", "5", "throttle Axis here, 5 is typical")


local shiftup = keyOptions:addKeyBind("ShiftUp", getText("IGUI_BVD_ShiftUp") , Keyboard.KEY_UP, getText("IGUI_BVD_ShiftUp_Tooltip"))
local shiftdown = keyOptions:addKeyBind("ShiftDown", getText("IGUI_BVD_ShiftDown") , Keyboard.KEY_DOWN, getText("IGUI_BVD_ShiftDown_Tooltip"))
local driftBind = keyOptions:addKeyBind("DriftKey", getText("IGUI_BVD_DriftKey"), Keyboard.KEY_LSHIFT, getText("IGUI_BVD_DriftKey_Tooltip"))
keyOptions.apply = applyOptions;

keyOptions:addTickBox("CustomizableSteering", getText("IGUI_BVD_CustomizableSteering"), true, getText("IGUI_BVD_CustomizableSteering_Tooltip"))

keyOptions:addSmartNumberEntry("SteeringFactorLowSpeed", getText("Sandbox_BVD_SteeringFactorLowSpeed"), getText("Sandbox_BVD_SteeringFactorLowSpeed_tooltip"),1,0,10)
keyOptions:addSmartNumberEntry("SteeringFactorHighSpeed", getText("Sandbox_BVD_SteeringFactorHighSpeed"), getText("Sandbox_BVD_SteeringFactorHighSpeed_tooltip"),0.1,0,10)
keyOptions:addSmartNumberEntry("SteeringCenteringLowSpeed", getText("Sandbox_BVD_SteeringCenteringLowSpeed"), getText("Sandbox_BVD_SteeringCenteringLowSpeed_tooltip"),1,0,10)
keyOptions:addSmartNumberEntry("SteeringCenteringHighSpeed", getText("Sandbox_BVD_SteeringCenteringHighSpeed"), getText("Sandbox_BVD_SteeringCenteringHighSpeed_tooltip"),0.1,0,10)
keyOptions:addSmartNumberEntry("SteeringSnapback", getText("Sandbox_BVD_SteeringSnapback"), getText("Sandbox_BVD_SteeringSnapback_tooltip"),3,0,10)
keyOptions:addSmartNumberEntry("SteeringHighSpeed", getText("Sandbox_BVD_SteeringHighSpeed"), getText("Sandbox_BVD_SteeringHighSpeed_tooltip"),75,10,120)

function ShiftDetect(key)
	if key == shiftup:getValue() then
		BetterVehicleDynamicsMod.forceGear = BetterVehicleDynamicsMod.forceGear + 1
	end
	if key == shiftdown:getValue() then
		BetterVehicleDynamicsMod.forceGear = BetterVehicleDynamicsMod.forceGear - 1
	end
end

-- Todo: Consider using https://projectzomboid.com/chat_colours.txt to make error message fancier.
local VersionCheckConfirmed = false;
local function onConfirm()
	UIManager.getSpeedControls():SetCurrentGameSpeed(1);
end

function BetterVehicleDynamicsVersionCheck()
	if BetterVehicleDynamicsMod.javaVersion == "not installed" and not VersionCheckConfirmed then
		VersionCheckConfirmed = true;
		local width = 400;
		local modal = ISModalDialog:new((getCore():getScreenWidth() - width) / 2,getCore():getScreenHeight() / 4, width, 150, getText("IGUI_BVD_NotProperlyInstalled"), false, nil, onConfirm, 0)
		modal:initialise()
		modal:addToUIManager()
		UIManager.getSpeedControls():SetCurrentGameSpeed(0);
	elseif BetterVehicleDynamicsMod.javaVersion ~= "3.4" and not VersionCheckConfirmed then
		VersionCheckConfirmed = true;
		local width = 400;
		local modal = ISModalDialog:new((getCore():getScreenWidth() - width) / 2,getCore():getScreenHeight() / 4, width, 150, getText("IGUI_BVD_Outdated"),false, nil, onConfirm, 0)
		modal:initialise()
		modal:addToUIManager()
		UIManager.getSpeedControls():SetCurrentGameSpeed(0);
	end
end



Events.OnInitGlobalModData.Add(applyOptions)
Events.OnKeyStartPressed.Add(ShiftDetect);
Events.OnSpawnVehicleEnd.Add(BetterVehicleDynamicsVersionCheck)

print("Better Vehicle Dynamics Client Side Loaded")
