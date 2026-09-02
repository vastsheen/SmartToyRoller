local ADDON_NAME = ...

local DB_VERSION = 2

local DEFAULT_DB = {
	schemaVersion = DB_VERSION,
	profiles = {},
	profileOrder = {},
}

local state = {
	buttons = {},
	actions = {},
}

SmartToyRoller = SmartToyRoller or {}

local ROTATION_STRATEGY_PRIORITY = "priority"
local ROTATION_STRATEGY_ACTIVE_INDEX = "activeIndex"

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7SmartToyRoller|r: " .. tostring(message))
end

local function CopyDefaults(source, target)
	if type(source) ~= "table" then
		return target
	end

	if type(target) ~= "table" then
		target = {}
	end

	for key, value in pairs(source) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = CopyDefaults(value, nil)
			else
				target[key] = value
			end
		end
	end

	return target
end

local function RepairKnownAuraIDs(db)
	if type(db) ~= "table" or type(db.profiles) ~= "table" then
		return
	end

	for _, profile in pairs(db.profiles) do
		if type(profile.groups) == "table" then
			for _, group in ipairs(profile.groups) do
				if type(group.skipAuraSpellIDs) == "table" then
					for index, spellID in ipairs(group.skipAuraSpellIDs) do
						if spellID == 397827 then
							group.skipAuraSpellIDs[index] = 207700
						end
					end
				end
			end
		end
	end
end

local function GetDB()
	if type(SmartToyRollerDB) ~= "table" or SmartToyRollerDB.schemaVersion ~= DB_VERSION then
		SmartToyRollerDB = CopyDefaults(DEFAULT_DB, nil)
	else
		SmartToyRollerDB = CopyDefaults(DEFAULT_DB, SmartToyRollerDB)
	end

	RepairKnownAuraIDs(SmartToyRollerDB)
	return SmartToyRollerDB
end

local function SanitizeID(value)
	local id = tostring(value or ""):gsub("%s+", "_"):gsub("[^%w_]", "")
	if id == "" then
		id = "profile"
	end
	if id:match("^%d") then
		id = "p_" .. id
	end
	return id
end

local function GetButtonName(profileID)
	return "SmartToyRollerButton_" .. SanitizeID(profileID)
end

local function GetAuraBySpellID(spellID)
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		return C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	end

	for index = 1, 40 do
		local auraData = C_UnitAuras
			and C_UnitAuras.GetAuraDataByIndex
			and C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
		if not auraData then
			break
		end
		if auraData.spellId == spellID then
			return auraData
		end
	end

	return nil
end

local function GroupShouldSkip(group)
	if type(group) ~= "table" or type(group.skipAuraSpellIDs) ~= "table" then
		return false, nil
	end

	for _, spellID in ipairs(group.skipAuraSpellIDs) do
		if GetAuraBySpellID(spellID) then
			return true, spellID
		end
	end

	return false, nil
end

local function GetToyCooldown(toyID)
	if C_ToyBox and C_ToyBox.GetToyCooldown then
		return C_ToyBox.GetToyCooldown(toyID)
	end
	if C_Container and C_Container.GetItemCooldown then
		return C_Container.GetItemCooldown(toyID)
	end
	if GetItemCooldown then
		return GetItemCooldown(toyID)
	end
	return 0, 0, 1
end

local function ToyOnCooldown(toyID)
	local startTime, duration, enable = GetToyCooldown(toyID)
	if enable == 0 then
		return true
	end
	return startTime and startTime > 0 and duration and duration > 1.5
end

local function ToyUsable(toyID)
	return toyID
		and PlayerHasToy(toyID)
		and (not C_ToyBox.IsToyUsable or C_ToyBox.IsToyUsable(toyID))
		and not ToyOnCooldown(toyID)
end

local function GetToyUnavailableReason(toyID)
	if not toyID or not PlayerHasToy(toyID) then
		return "未拥有玩具"
	end
	if ToyOnCooldown(toyID) then
		return "cd 中"
	end
	if C_ToyBox.IsToyUsable and not C_ToyBox.IsToyUsable(toyID) then
		return "不可用"
	end
	return "不可用"
end

local function PickToy(group)
	if type(group) ~= "table" or type(group.toys) ~= "table" then
		return nil, "未配置玩具"
	end

	local candidates = {}
	local reasonCounts = {}
	for _, toyID in ipairs(group.toys) do
		if ToyUsable(toyID) then
			candidates[#candidates + 1] = toyID
		else
			local reason = GetToyUnavailableReason(toyID)
			reasonCounts[reason] = (reasonCounts[reason] or 0) + 1
		end
	end

	if #candidates == 0 then
		if #group.toys == 0 then
			return nil, "未配置玩具"
		end
		if reasonCounts["cd 中"] then
			return nil, "cd 中"
		end
		if reasonCounts["未拥有玩具"] then
			return nil, "未拥有玩具"
		end
		return nil, "不可用"
	end

	return candidates[random(#candidates)], nil
end

local function GetProfileStrategy(profile)
	if profile.rotationStrategy == ROTATION_STRATEGY_ACTIVE_INDEX then
		return ROTATION_STRATEGY_ACTIVE_INDEX
	end
	return ROTATION_STRATEGY_PRIORITY
end

local function PrintGroupSkip(profile, group, reason)
	Print((profile.label or "方案") .. "-" .. (group.label or "分组") .. "跳过-" .. reason)
end

local function ResolvePriorityAction(profile, reportSkips)
	for groupIndex = 1, #profile.groups do
		local group = profile.groups[groupIndex]
		local shouldSkip = GroupShouldSkip(group)
		if shouldSkip then
			if reportSkips then
				PrintGroupSkip(profile, group, "效果已存在")
			end
		else
			local toyID, unavailableReason = PickToy(group)
			if toyID then
				return "item", "item:" .. toyID, groupIndex, nil
			end
			if reportSkips then
				PrintGroupSkip(profile, group, unavailableReason or "不可用")
			end
		end
	end

	return nil, nil, nil, "没有可用玩具"
end

local function ResolveActiveIndexAction(profile)
	local startIndex = profile.activeGroupIndex or 1
	if startIndex < 1 or startIndex > #profile.groups then
		startIndex = 1
	end

	for offset = 0, #profile.groups - 1 do
		local groupIndex = ((startIndex + offset - 1) % #profile.groups) + 1
		local group = profile.groups[groupIndex]
		if not GroupShouldSkip(group) then
			local toyID = PickToy(group)
			if toyID then
				return "item", "item:" .. toyID, groupIndex, nil
			end
		end
	end

	return nil, nil, nil, "没有可用玩具"
end

local function ResolveProfileAction(profileID, reportSkips)
	local db = GetDB()
	local profile = db.profiles[profileID]
	if not profile then
		return nil, nil, nil, "profile 不存在"
	end

	if type(profile.groups) ~= "table" or #profile.groups == 0 then
		return nil, nil, nil, "没有分组"
	end

	if GetProfileStrategy(profile) == ROTATION_STRATEGY_ACTIVE_INDEX then
		return ResolveActiveIndexAction(profile)
	end

	return ResolvePriorityAction(profile, reportSkips)
end

local function AdvanceProfileAfterClick(profileID)
	local db = GetDB()
	local profile = db.profiles[profileID]
	local action = state.actions[profileID]
	if
		not profile
		or GetProfileStrategy(profile) ~= ROTATION_STRATEGY_ACTIVE_INDEX
		or type(profile.groups) ~= "table"
		or #profile.groups == 0
		or not action
		or not action.groupIndex
	then
		return
	end

	profile.activeGroupIndex = (action.groupIndex % #profile.groups) + 1
end

local function SetButtonAction(profileID, reportSkips)
	local button = state.buttons[profileID]
	if not button then
		return
	end

	local actionType, value, groupIndex, errorMessage = ResolveProfileAction(profileID, reportSkips)
	state.actions[profileID] = {
		actionType = actionType,
		value = value,
		groupIndex = groupIndex,
		errorMessage = errorMessage,
	}

	button:SetAttribute("type", nil)
	button:SetAttribute("type1", nil)
	button:SetAttribute("item", nil)
	button:SetAttribute("item1", nil)

	if actionType and value then
		button:SetAttribute("type", actionType)
		button:SetAttribute("type1", actionType)
		button:SetAttribute("item", value)
		button:SetAttribute("item1", value)
	end

	if button.icon then
		local itemID = value and tonumber(tostring(value):match("item:(%d+)"))
		button.icon:SetTexture((itemID and GetItemIcon(itemID)) or 134400)
	end
end

local function ApplyButtonVisibility(profileID)
	local db = GetDB()
	local profile = db.profiles[profileID]
	local button = state.buttons[profileID]
	if not profile or not button then
		return
	end

	if profile.buttonVisible ~= true then
		button:SetAlpha(0)
		button:EnableMouse(false)
	else
		button:SetAlpha(1)
		button:EnableMouse(true)
	end
	button:Show()
end

local function SaveButtonPosition(profileID)
	local db = GetDB()
	local profile = db.profiles[profileID]
	local button = state.buttons[profileID]
	if not profile or not button then
		return
	end

	profile.button = profile.button or {}
	local point, _, relativePoint, x, y = button:GetPoint()
	profile.button.point = point
	profile.button.relativePoint = relativePoint
	profile.button.x = x
	profile.button.y = y
end

local function EnsureProfileButton(profileID)
	local db = GetDB()
	local profile = db.profiles[profileID]
	if not profile or InCombatLockdown() then
		return nil
	end

	if state.buttons[profileID] then
		return state.buttons[profileID]
	end

	local button = CreateFrame("Button", GetButtonName(profileID), UIParent, "SecureActionButtonTemplate")
	state.buttons[profileID] = button
	profile.button = profile.button or {}

	button.profileID = profileID
	button:SetSize(44, 44)
	button:SetPoint(
		profile.button.point or "CENTER",
		UIParent,
		profile.button.relativePoint or "CENTER",
		profile.button.x or 0,
		profile.button.y or -120
	)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("useOnKeyDown", false)
	button:SetMovable(true)
	button:EnableMouse(true)
	button:SetClampedToScreen(true)

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexture(134400)

	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetPoint("TOPLEFT", -10, 10)
	button.border:SetPoint("BOTTOMRIGHT", 10, -10)
	button.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")

	button:SetScript("OnEnter", function(self)
		local currentDB = GetDB()
		local currentProfile = currentDB.profiles[self.profileID]
		local action = state.actions[self.profileID] or {}
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(currentProfile and currentProfile.label or self.profileID)
		GameTooltip:AddLine("左键：按分组顺序执行第一个可用玩具。", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Shift 拖动：移动按钮。", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("宏：/click " .. GetButtonName(self.profileID) .. " LeftButton", 0.6, 0.9, 1)
		if action.value then
			GameTooltip:AddLine("下一动作：" .. tostring(action.value), 0.6, 0.9, 1)
		elseif action.errorMessage then
			GameTooltip:AddLine(action.errorMessage, 1, 0.4, 0.4)
		end
		GameTooltip:Show()
	end)

	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	button:SetScript("OnMouseDown", function(self, mouseButton)
		local currentDB = GetDB()
		local currentProfile = currentDB.profiles[self.profileID]
		if
			mouseButton == "LeftButton"
			and IsShiftKeyDown()
			and currentProfile
			and currentProfile.buttonLocked ~= true
		then
			self:StartMoving()
		end
	end)

	button:SetScript("OnMouseUp", function(self)
		self:StopMovingOrSizing()
		SaveButtonPosition(self.profileID)
	end)

	button:HookScript("PostClick", function(self)
		AdvanceProfileAfterClick(self.profileID)
		SetButtonAction(self.profileID)
	end)
	button:HookScript("PreClick", function(self)
		SetButtonAction(self.profileID, true)
	end)

	SetButtonAction(profileID)
	ApplyButtonVisibility(profileID)
	return button
end

local function EnsureAllButtons()
	local db = GetDB()
	for _, profileID in ipairs(db.profileOrder) do
		EnsureProfileButton(profileID)
		SetButtonAction(profileID)
		ApplyButtonVisibility(profileID)
	end
end

local function HideRemovedButtons()
	local db = GetDB()
	for profileID, button in pairs(state.buttons) do
		if not db.profiles[profileID] then
			button:SetAttribute("type", nil)
			button:SetAttribute("type1", nil)
			button:SetAttribute("item", nil)
			button:SetAttribute("item1", nil)
			button:SetAlpha(0)
			button:EnableMouse(false)
			button:Show()
			state.actions[profileID] = nil
		end
	end
end

function SmartToyRoller.GetDB()
	return GetDB()
end

function SmartToyRoller.GetButtonName(profileID)
	return GetButtonName(profileID)
end

function SmartToyRoller.SanitizeID(value)
	return SanitizeID(value)
end

function SmartToyRoller.RefreshProfile(profileID)
	EnsureProfileButton(profileID)
	SetButtonAction(profileID)
	ApplyButtonVisibility(profileID)
end

function SmartToyRoller.RefreshAll()
	HideRemovedButtons()
	EnsureAllButtons()
end

function SmartToyRoller.SetProfileButtonVisible(profileID, visible)
	local db = GetDB()
	local profile = db.profiles[profileID]
	if not profile then
		return
	end

	profile.buttonVisible = not not visible
	SmartToyRoller.RefreshProfile(profileID)
end

function SmartToyRoller.SetProfileButtonLocked(profileID, locked)
	local db = GetDB()
	local profile = db.profiles[profileID]
	if profile then
		profile.buttonLocked = not not locked
	end
end

function SmartToyRoller.GetRotationStrategies()
	return ROTATION_STRATEGY_PRIORITY, ROTATION_STRATEGY_ACTIVE_INDEX
end

function SmartToyRoller.OpenOptions()
	if SmartToyRoller.OpenOptionsPanel then
		SmartToyRoller.OpenOptionsPanel()
	else
		Print("配置面板尚不可用。")
	end
end

SLASH_SMARTTOYROLLEROPTIONS1 = "/stro"
SlashCmdList.SMARTTOYROLLEROPTIONS = function()
	SmartToyRoller.OpenOptions()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UNIT_AURA")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		GetDB()
		EnsureAllButtons()
	elseif event == "PLAYER_LOGIN" then
		math.randomseed(time())
		EnsureAllButtons()
	elseif event == "PLAYER_ENTERING_WORLD" then
		EnsureAllButtons()
	elseif event == "PLAYER_REGEN_ENABLED" then
		EnsureAllButtons()
	elseif event == "UNIT_AURA" and arg1 == "player" then
		EnsureAllButtons()
	end
end)
