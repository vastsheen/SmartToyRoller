local PANEL_NAME = "智能玩具轮换"
local TOY_PAGE_SIZE = 27
local GROUP_TOY_SLOT_COUNT = 60
local PROFILE_X = 18
local GROUP_X = 220
local TOY_X = 612
local TOY_Y = -66
local ROTATION_STRATEGY_PRIORITY = "priority"
local ROTATION_STRATEGY_ACTIVE_INDEX = "activeIndex"

local panel
local actionPopup
local groupEditPopup
local strategyPopup
local selectedProfileID
local selectedGroupIndex = 1
local profileRows = {}
local groupRows = {}
local groupToySlots = {}
local toyRows = {}
local toyList = {}
local toyPage = 1
local groupToyContent

local KNOWN_TOY_AURAS = SmartToyRollerKnownToyAuras or {}

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7SmartToyRoller|r: " .. tostring(message))
end

local function Trim(value)
	return strtrim(tostring(value or ""))
end

local function ParseIDList(value)
	local ids = {}
	local seen = {}

	for token in tostring(value or ""):gmatch("%d+") do
		local id = tonumber(token)
		if id and id > 0 and not seen[id] then
			ids[#ids + 1] = id
			seen[id] = true
		end
	end

	return ids
end

local function JoinIDList(ids)
	local parts = {}
	if type(ids) == "table" then
		for _, id in ipairs(ids) do
			parts[#parts + 1] = tostring(id)
		end
	end
	return table.concat(parts, ", ")
end

local function Contains(list, value)
	if type(list) ~= "table" then
		return false
	end
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end

local function AddUnique(list, value)
	if not value or Contains(list, value) then
		return false
	end
	list[#list + 1] = value
	table.sort(list)
	return true
end

local function RemoveValue(list, value)
	if type(list) ~= "table" then
		return false
	end
	for index = #list, 1, -1 do
		if list[index] == value then
			table.remove(list, index)
			return true
		end
	end
	return false
end

local function StripColors(value)
	return tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
end

local function CreateLabel(parent, text, x, y, width, template)
	local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
	label:SetPoint("TOPLEFT", x, y)
	label:SetText(text)
	label:SetJustifyH("LEFT")
	if width then
		label:SetWidth(width)
	end
	return label
end

local function CreateEditBox(parent, label, x, y, width)
	CreateLabel(parent, label, x, y, width)
	local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	editBox:SetSize(width, 24)
	editBox:SetPoint("TOPLEFT", x + 4, y - 20)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject("GameFontHighlight")
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	editBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	return editBox
end

local function CreateButton(parent, text, x, y, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 84, 24)
	button:SetPoint("TOPLEFT", x, y)
	button:SetText(text)
	return button
end

local function CreateBorderBox(parent, x, y, width, height)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetPoint("TOPLEFT", x, y)
	box:SetSize(width, height)
	box:SetFrameLevel(parent:GetFrameLevel() + 1)
	box:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 10,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	box:SetBackdropBorderColor(0.85, 0.72, 0.36, 0.95)
	return box
end

local function GetDB()
	return SmartToyRoller.GetDB()
end

local function GetProfile()
	local db = GetDB()
	if not selectedProfileID or not db.profiles[selectedProfileID] then
		selectedProfileID = db.profileOrder[1]
	end
	return selectedProfileID and db.profiles[selectedProfileID] or nil, selectedProfileID
end

local function GetGroup()
	local profile = GetProfile()
	if not profile or type(profile.groups) ~= "table" or #profile.groups == 0 then
		selectedGroupIndex = 1
		return nil
	end
	if selectedGroupIndex < 1 or selectedGroupIndex > #profile.groups then
		selectedGroupIndex = 1
	end
	return profile.groups[selectedGroupIndex], selectedGroupIndex
end

local function GetToyDisplay(toyID)
	if not toyID then
		return nil, nil
	end
	local _, toyName, icon = C_ToyBox.GetToyInfo(toyID)
	return toyName, icon
end

local RefreshPanel
local RefreshToyList
local HideGroupEditPopup
local OpenGroupEditPopup
local HideStrategyPopup

local function NormalizeProfile(profile)
	profile.label = Trim(profile.label)
	if profile.label == "" then
		profile.label = "未命名方案"
	end
	profile.groups = profile.groups or {}
	profile.activeGroupIndex = profile.activeGroupIndex or 1
	if profile.rotationStrategy ~= ROTATION_STRATEGY_ACTIVE_INDEX then
		profile.rotationStrategy = ROTATION_STRATEGY_PRIORITY
	end
	if profile.buttonVisible == nil then
		profile.buttonVisible = false
	end
end

local function NormalizeGroup(group)
	group.label = Trim(group.label)
	if group.label == "" then
		group.label = "未命名分组"
	end
	group.skipAuraSpellIDs = group.skipAuraSpellIDs or {}
	for index, spellID in ipairs(group.skipAuraSpellIDs) do
		if spellID == 397827 then
			group.skipAuraSpellIDs[index] = 207700
		end
	end
	group.toys = group.toys or {}
end

local function SaveFields(silent)
	local db = GetDB()
	local profile, profileID = GetProfile()
	if not profile then
		if not silent then
			Print("请先新建方案。")
		end
		return nil
	end

	local newID = SmartToyRoller.SanitizeID(panel.profileID:GetText())
	if newID == "" then
		if not silent then
			Print("方案 ID 不能为空。")
		end
		return nil
	end

	if newID ~= profileID and db.profiles[newID] then
		if not silent then
			Print("方案 ID 已存在。")
		end
		return nil
	end

	profile.label = Trim(panel.profileLabel:GetText())
	NormalizeProfile(profile)

	if newID ~= profileID then
		db.profiles[newID] = profile
		db.profiles[profileID] = nil
		for index, id in ipairs(db.profileOrder) do
			if id == profileID then
				db.profileOrder[index] = newID
				break
			end
		end
		selectedProfileID = newID
	end

	SmartToyRoller.RefreshAll()
	return profile
end

local function SaveGroupEdit()
	local profile = SaveFields(true)
	local group = GetGroup()
	if not profile or not groupEditPopup or not group then
		return nil
	end

	group.label = Trim(groupEditPopup.groupLabel:GetText())
	group.skipAuraSpellIDs = ParseIDList(groupEditPopup.skipAuraIDs:GetText())
	NormalizeGroup(group)
	SmartToyRoller.RefreshAll()
	RefreshPanel()
	HideGroupEditPopup()
	return group
end

local function AddProfile()
	local db = GetDB()
	local index = #db.profileOrder + 1
	local profileID = "profile" .. index
	while db.profiles[profileID] do
		index = index + 1
		profileID = "profile" .. index
	end

	db.profiles[profileID] = {
		label = "新方案",
		buttonVisible = false,
		buttonLocked = false,
		activeGroupIndex = 1,
		rotationStrategy = ROTATION_STRATEGY_PRIORITY,
		groups = {
			{
				label = "分组 1",
				skipAuraSpellIDs = {},
				toys = {},
			},
		},
	}
	db.profileOrder[#db.profileOrder + 1] = profileID
	selectedProfileID = profileID
	selectedGroupIndex = 1
	SmartToyRoller.RefreshAll()
	RefreshPanel()
end

local function SetRotationStrategy(strategy)
	local profile = SaveFields(true)
	if not profile then
		return
	end

	if strategy == ROTATION_STRATEGY_ACTIVE_INDEX then
		profile.rotationStrategy = ROTATION_STRATEGY_ACTIVE_INDEX
	else
		profile.rotationStrategy = ROTATION_STRATEGY_PRIORITY
	end
	SmartToyRoller.RefreshAll()
	RefreshPanel()
end

HideStrategyPopup = function()
	if strategyPopup then
		strategyPopup:Hide()
	end
end

local function DeleteProfile()
	local db = GetDB()
	local _, profileID = GetProfile()
	if not profileID then
		return
	end

	db.profiles[profileID] = nil
	for index = #db.profileOrder, 1, -1 do
		if db.profileOrder[index] == profileID then
			table.remove(db.profileOrder, index)
		end
	end

	selectedProfileID = db.profileOrder[1]
	selectedGroupIndex = 1
	SmartToyRoller.RefreshAll()
	RefreshPanel()
end

local function AddGroup()
	local profile = SaveFields(true)
	if not profile then
		return nil
	end

	local group = {
		label = "分组 " .. (#profile.groups + 1),
		skipAuraSpellIDs = {},
		toys = {},
	}
	profile.groups[#profile.groups + 1] = group
	selectedGroupIndex = #profile.groups
	SmartToyRoller.RefreshAll()
	RefreshPanel()
	OpenGroupEditPopup()
	return group
end

local function DeleteGroup()
	local profile = SaveFields(true)
	if not profile or #profile.groups == 0 then
		return
	end

	table.remove(profile.groups, selectedGroupIndex)
	if selectedGroupIndex > #profile.groups then
		selectedGroupIndex = #profile.groups
	end
	if selectedGroupIndex < 1 then
		selectedGroupIndex = 1
	end
	if profile.activeGroupIndex > #profile.groups then
		profile.activeGroupIndex = 1
	end
	HideGroupEditPopup()
	SmartToyRoller.RefreshAll()
	RefreshPanel()
end

local function MoveGroup(delta)
	local profile = SaveFields(true)
	if not profile then
		return
	end

	local targetIndex = selectedGroupIndex + delta
	if targetIndex < 1 or targetIndex > #profile.groups then
		return
	end

	profile.groups[selectedGroupIndex], profile.groups[targetIndex] =
		profile.groups[targetIndex], profile.groups[selectedGroupIndex]
	selectedGroupIndex = targetIndex
	SmartToyRoller.RefreshAll()
	RefreshPanel()
end

local function AddToyToGroup(toyID, groupIndex)
	local profile = SaveFields(true)
	if not profile or not profile.groups[groupIndex] then
		return
	end

	local group = profile.groups[groupIndex]
	NormalizeGroup(group)
	AddUnique(group.toys, toyID)
	if #group.skipAuraSpellIDs == 0 and KNOWN_TOY_AURAS[toyID] then
		group.skipAuraSpellIDs = KNOWN_TOY_AURAS[toyID]
	end
	selectedGroupIndex = groupIndex
	SmartToyRoller.RefreshAll()
	RefreshPanel()
end

local function AddToyToNewGroup(toyID)
	local profile = SaveFields(true)
	if not profile then
		return
	end

	local toyName = GetToyDisplay(toyID) or "新分组"
	profile.groups[#profile.groups + 1] = {
		label = toyName,
		skipAuraSpellIDs = KNOWN_TOY_AURAS[toyID] or {},
		toys = { toyID },
	}
	selectedGroupIndex = #profile.groups
	SmartToyRoller.RefreshAll()
	RefreshPanel()
end

local function RemoveToyFromGroup(toyID, groupIndex)
	local profile = SaveFields(true)
	if not profile or not profile.groups[groupIndex] then
		return
	end

	RemoveValue(profile.groups[groupIndex].toys, toyID)
	selectedGroupIndex = groupIndex
	SmartToyRoller.RefreshAll()
	RefreshPanel()
end

local function HideActionPopup()
	if actionPopup then
		actionPopup:Hide()
	end
end

HideGroupEditPopup = function()
	if groupEditPopup then
		groupEditPopup:Hide()
	end
end

OpenGroupEditPopup = function()
	local group = GetGroup()
	if not group or not groupEditPopup then
		return
	end

	NormalizeGroup(group)
	groupEditPopup.groupLabel:SetText(group.label)
	groupEditPopup.skipAuraIDs:SetText(JoinIDList(group.skipAuraSpellIDs))
	groupEditPopup:ClearAllPoints()
	groupEditPopup:SetPoint("CENTER", panel, "CENTER", 0, 20)
	groupEditPopup:Show()
	groupEditPopup.groupLabel:SetFocus()
end

local function LayoutPopup(buttons)
	local y = -34
	for _, button in ipairs(actionPopup.buttons) do
		button:Hide()
	end
	for _, button in ipairs(buttons) do
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 12, y)
		button:Show()
		y = y - 26
	end
	actionPopup.closeButton:ClearAllPoints()
	actionPopup.closeButton:SetPoint("TOPLEFT", 12, y)
	actionPopup:SetHeight(math.abs(y) + 34)
end

local function OpenToyPopup(toyID)
	local profile = SaveFields(true)
	if not profile or not toyID then
		return
	end

	local toyName = GetToyDisplay(toyID) or "玩具"
	actionPopup.title:SetText(toyName)
	local buttons = {}

	actionPopup.newGroupButton:SetScript("OnClick", function()
		AddToyToNewGroup(toyID)
		HideActionPopup()
	end)
	buttons[#buttons + 1] = actionPopup.newGroupButton

	for index = 1, math.min(#profile.groups, #actionPopup.groupButtons) do
		local button = actionPopup.groupButtons[index]
		button:SetText("加入：" .. profile.groups[index].label)
		button:SetScript("OnClick", function()
			AddToyToGroup(toyID, index)
			HideActionPopup()
		end)
		buttons[#buttons + 1] = button
	end

	LayoutPopup(buttons)
	actionPopup:ClearAllPoints()
	actionPopup:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -118)
	actionPopup:Show()
end

local function OpenSlotPopup(toyID)
	local groupIndex = selectedGroupIndex
	local toyName = GetToyDisplay(toyID) or "玩具"
	actionPopup.title:SetText(toyName)
	actionPopup.removeButton:SetScript("OnClick", function()
		RemoveToyFromGroup(toyID, groupIndex)
		HideActionPopup()
	end)
	LayoutPopup({ actionPopup.removeButton })
	actionPopup:ClearAllPoints()
	actionPopup:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -118)
	actionPopup:Show()
end

local function BuildSearchTokens()
	local query = Trim(panel and panel.toySearch and panel.toySearch:GetText() or "")
	local tokens = {}
	for token in query:gmatch("%S+") do
		tokens[#tokens + 1] = strlower(token)
	end
	return tokens
end

local function MatchesToySearch(toyID, toyName, toyLink)
	local tokens = BuildSearchTokens()
	if #tokens == 0 then
		return true
	end

	local haystack = strlower(table.concat({
		tostring(toyID or ""),
		tostring(toyName or ""),
		StripColors(toyLink),
	}, " "))
	for _, token in ipairs(tokens) do
		if not haystack:find(token, 1, true) then
			return false
		end
	end
	return true
end

local function RebuildToyList()
	toyList = {}
	if not C_ToyBox or not C_ToyBox.GetNumToys or not C_ToyBox.GetToyFromIndex then
		return
	end

	for index = 1, C_ToyBox.GetNumToys() or 0 do
		local toyID = C_ToyBox.GetToyFromIndex(index)
		if toyID and PlayerHasToy(toyID) then
			local _, toyName, icon = C_ToyBox.GetToyInfo(toyID)
			local toyLink = C_ToyBox.GetToyLink and C_ToyBox.GetToyLink(toyID)
			if toyName and MatchesToySearch(toyID, toyName, toyLink) then
				toyList[#toyList + 1] = {
					id = toyID,
					name = toyName,
					icon = icon,
				}
			end
		end
	end

	table.sort(toyList, function(left, right)
		return left.name < right.name
	end)
	local maxPage = math.max(1, math.ceil(#toyList / TOY_PAGE_SIZE))
	toyPage = math.min(toyPage, maxPage)
end

local function UpdateSlot(slot, toyID, emptyText)
	slot.toyID = toyID
	if toyID then
		local toyName, icon = GetToyDisplay(toyID)
		slot.icon:SetTexture(icon or 134400)
		slot.icon:Show()
		slot.text:SetText(toyName or "未知玩具")
	else
		slot.icon:Hide()
		slot.text:SetText(emptyText)
	end
end

local function RefreshGroupSlots()
	local group = GetGroup()
	for index = 1, GROUP_TOY_SLOT_COUNT do
		local toyID = group and group.toys and group.toys[index]
		UpdateSlot(groupToySlots[index], toyID, "空")
	end
end

RefreshToyList = function()
	if not panel then
		return
	end

	RebuildToyList()
	local startIndex = ((toyPage - 1) * TOY_PAGE_SIZE) + 1
	local group = GetGroup()

	for index = 1, TOY_PAGE_SIZE do
		local row = toyRows[index]
		local toy = toyList[startIndex + index - 1]
		if toy then
			local suffix = group and Contains(group.toys, toy.id) and " [本组]" or ""
			row.toyID = toy.id
			row.icon:SetTexture(toy.icon or 134400)
			row.text:SetText(toy.name .. suffix)
			row:Show()
		else
			row.toyID = nil
			row:Hide()
		end
	end

	local maxPage = math.max(1, math.ceil(#toyList / TOY_PAGE_SIZE))
	panel.pageText:SetText("第 " .. toyPage .. " / " .. maxPage .. " 页，共 " .. #toyList .. " 个")
end

RefreshPanel = function()
	if not panel then
		return
	end

	HideActionPopup()
	HideStrategyPopup()

	local db = GetDB()
	local profile = GetProfile()
	GetGroup()

	for _, row in ipairs(profileRows) do
		row:Hide()
	end
	for _, row in ipairs(groupRows) do
		row:Hide()
	end

	for index, profileID in ipairs(db.profileOrder) do
		local row = profileRows[index]
		if not row then
			row = CreateButton(panel, "", PROFILE_X, -96 - ((index - 1) * 28), 176)
			profileRows[index] = row
		end
		local rowProfile = db.profiles[profileID]
		row:SetText((profileID == selectedProfileID and "* " or "") .. rowProfile.label)
		row:SetScript("OnClick", function()
			selectedProfileID = profileID
			selectedGroupIndex = 1
			RefreshPanel()
		end)
		row:Show()
	end

	if profile and type(profile.groups) == "table" then
		for index, rowGroup in ipairs(profile.groups) do
			local row = groupRows[index]
			if not row then
				row = CreateButton(panel, "", 0, 0, 68)
				row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				groupRows[index] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", GROUP_X + 10 + ((index - 1) * 72), -242)
			row:SetText((index == selectedGroupIndex and "* " or "") .. rowGroup.label)
			row:SetScript("OnClick", function(_, button)
				selectedGroupIndex = index
				RefreshPanel()
				if button == "RightButton" then
					OpenGroupEditPopup()
				end
			end)
			row:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(rowGroup.label, 1, 1, 1)
				GameTooltip:AddLine("左键：选择分组", 0.8, 0.8, 0.8)
				GameTooltip:AddLine("右键：编辑分组名称和跳过效果", 0.8, 0.8, 0.8)
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			row:Show()
		end
	end

	panel.emptyText:SetShown(not profile)
	panel.profileID:SetText(selectedProfileID or "")
	panel.profileLabel:SetText(profile and profile.label or "")
	panel.macroText:SetText(
		selectedProfileID and ("/click " .. SmartToyRoller.GetButtonName(selectedProfileID) .. " LeftButton") or ""
	)
	panel.toggleButton:SetText(profile and profile.buttonVisible == true and "隐藏按钮" or "显示按钮")
	panel.lockButton:SetText(profile and profile.buttonLocked and "解锁拖动" or "锁定拖动")
	panel.strategyButton:SetText(
		profile and profile.rotationStrategy == ROTATION_STRATEGY_ACTIVE_INDEX and "策略：轮转"
			or "策略：顺序"
	)

	RefreshGroupSlots()
	RefreshToyList()
end

local function CreateStrategyPopup(parent)
	local popup = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	popup:SetSize(104, 86)
	popup:SetFrameStrata("DIALOG")
	popup:SetFrameLevel(100)
	popup:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	popup:Hide()

	popup.priorityButton = CreateButton(popup, "顺序", 14, -18, 76)
	popup.priorityButton:SetScript("OnClick", function()
		SetRotationStrategy(ROTATION_STRATEGY_PRIORITY)
		HideStrategyPopup()
	end)
	popup.activeIndexButton = CreateButton(popup, "轮转", 14, -48, 76)
	popup.activeIndexButton:SetScript("OnClick", function()
		SetRotationStrategy(ROTATION_STRATEGY_ACTIVE_INDEX)
		HideStrategyPopup()
	end)
	return popup
end

local function CreateToyButton(parent, x, y, width, height)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height)
	button:SetPoint("TOPLEFT", x, y)

	button.bg = button:CreateTexture(nil, "BACKGROUND")
	button.bg:SetAllPoints()
	button.bg:SetColorTexture(0.08, 0.06, 0.04, 0.45)

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(28, 28)
	button.icon:SetPoint("LEFT", 4, 0)

	button.text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
	button.text:SetWidth(width - 42)
	if button.text.SetMaxLines then
		button.text:SetMaxLines(2)
	end
	button.text:SetJustifyH("LEFT")
	button.text:SetJustifyV("MIDDLE")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	return button
end

local function CreateGroupToySlot(parent, index)
	local col = (index - 1) % 3
	local row = math.floor((index - 1) / 3)
	local slot = CreateToyButton(parent, 8 + (col * 116), -8 - (row * 38), 108, 34)
	slot:SetScript("OnClick", function(self, button)
		if button == "RightButton" and self.toyID then
			OpenSlotPopup(self.toyID)
		end
	end)
	slot:SetScript("OnEnter", function(self)
		if self.toyID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetToyByItemID(self.toyID)
			GameTooltip:Show()
		end
	end)
	slot:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return slot
end

local function CreateToyRow(parent, index)
	local col = (index - 1) % 3
	local gridRow = math.floor((index - 1) / 3)
	local row = CreateToyButton(parent, TOY_X + (col * 106), -138 - (gridRow * 42), 100, 38)
	row.icon:SetSize(32, 32)
	row.text:SetWidth(56)
	row.text:SetHeight(34)
	row.text:SetWordWrap(true)
	row:SetScript("OnClick", function(self)
		if self.toyID then
			OpenToyPopup(self.toyID)
		end
	end)
	row:SetScript("OnEnter", function(self)
		if self.toyID then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetToyByItemID(self.toyID)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("右键：选择加入哪个分组", 0.8, 0.8, 0.8)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return row
end

local function CreateActionPopup(parent)
	local popup = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	popup:SetSize(176, 120)
	popup:SetFrameStrata("DIALOG")
	popup:SetFrameLevel(100)
	popup:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	popup:Hide()
	popup.buttons = {}
	popup.groupButtons = {}

	popup.title = CreateLabel(popup, "", 12, -10, 152, "GameFontNormalSmall")
	popup.newGroupButton = CreateButton(popup, "新建分组加入", 12, -34, 152)
	popup.buttons[#popup.buttons + 1] = popup.newGroupButton
	popup.removeButton = CreateButton(popup, "移出本组", 12, -60, 152)
	popup.buttons[#popup.buttons + 1] = popup.removeButton

	for index = 1, 12 do
		local button = CreateButton(popup, "", 12, -60 - (index * 26), 152)
		popup.groupButtons[index] = button
		popup.buttons[#popup.buttons + 1] = button
	end

	popup.closeButton = CreateButton(popup, "关闭", 12, -300, 152)
	popup.closeButton:SetScript("OnClick", HideActionPopup)
	return popup
end

local function CreateGroupEditPopup(parent)
	local popup = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	popup:SetSize(300, 210)
	popup:SetFrameStrata("DIALOG")
	popup:SetFrameLevel(120)
	popup:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	popup:Hide()

	CreateLabel(popup, "编辑分组", 18, -18, 180, "GameFontNormalLarge")
	popup.groupLabel = CreateEditBox(popup, "分组名称", 22, -54, 250)
	popup.skipAuraIDs = CreateEditBox(popup, "本组跳过效果 ID", 22, -114, 250)
	CreateLabel(popup, "多个 ID 可用逗号或空格分隔。", 26, -166, 250, "GameFontHighlightSmall")

	popup.saveButton = CreateButton(popup, "保存", 52, -182, 80)
	popup.saveButton:SetScript("OnClick", SaveGroupEdit)
	popup.closeButton = CreateButton(popup, "取消", 164, -182, 80)
	popup.closeButton:SetScript("OnClick", HideGroupEditPopup)
	return popup
end

local function CreateOptionsPanel()
	panel = CreateFrame("Frame", "SmartToyRollerOptionsFrame", UIParent, "BackdropTemplate")
	panel:SetSize(960, 650)
	panel:SetPoint("CENTER")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:SetClampedToScreen(true)
	panel:SetFrameStrata("DIALOG")
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	panel:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			self:StartMoving()
		end
	end)
	panel:SetScript("OnMouseUp", function(self)
		self:StopMovingOrSizing()
	end)

	CreateBorderBox(panel, 8, -8, 198, 624)
	CreateBorderBox(panel, 210, -8, 390, 188)
	CreateBorderBox(panel, 210, -206, 390, 426)
	CreateBorderBox(panel, 216, -214, 378, 92)
	CreateBorderBox(panel, 216, -312, 378, 308)
	CreateBorderBox(panel, 606, -48, 344, 584)

	CreateLabel(panel, PANEL_NAME, 18, -18, 240, "GameFontNormalLarge")
	panel.close = CreateButton(panel, "关闭", 866, -18, 72)
	panel.close:SetScript("OnClick", function()
		panel:Hide()
	end)

	CreateLabel(panel, "方案", PROFILE_X, -62)
	panel.addProfile = CreateButton(panel, "新建方案", PROFILE_X, -36, 84)
	panel.addProfile:SetScript("OnClick", AddProfile)
	panel.deleteProfile = CreateButton(panel, "删除方案", PROFILE_X + 92, -36, 84)
	panel.deleteProfile:SetScript("OnClick", DeleteProfile)

	panel.emptyText =
		CreateLabel(panel, "还没有方案。先点击“新建方案”。", GROUP_X, -88, 360, "GameFontHighlight")
	panel.profileID = CreateEditBox(panel, "方案 ID", GROUP_X, -62, 150)
	panel.profileLabel = CreateEditBox(panel, "显示名称", GROUP_X + 170, -62, 170)
	panel.macroText = CreateEditBox(panel, "动作条宏", GROUP_X, -122, 360)
	panel.macroText:SetEnabled(false)

	panel.toggleButton = CreateButton(panel, "显示按钮", GROUP_X, -158, 70)
	panel.toggleButton:SetScript("OnClick", function()
		local profile, profileID = GetProfile()
		if profile and profileID then
			SmartToyRoller.SetProfileButtonVisible(profileID, profile.buttonVisible == false)
			RefreshPanel()
		end
	end)
	panel.lockButton = CreateButton(panel, "锁定", GROUP_X + 76, -158, 58)
	panel.lockButton:SetScript("OnClick", function()
		local profile, profileID = GetProfile()
		if profile and profileID then
			SmartToyRoller.SetProfileButtonLocked(profileID, not profile.buttonLocked)
			RefreshPanel()
		end
	end)
	panel.saveProfile = CreateButton(panel, "保存", GROUP_X + 140, -158, 58)
	panel.saveProfile:SetScript("OnClick", function()
		if SaveFields(false) then
			RefreshPanel()
			Print("已保存方案。")
		end
	end)
	panel.strategyButton = CreateButton(panel, "策略：顺序", GROUP_X + 204, -158, 96)
	panel.strategyButton:SetScript("OnClick", function(self)
		if strategyPopup:IsShown() then
			HideStrategyPopup()
			return
		end
		strategyPopup:ClearAllPoints()
		strategyPopup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", -8, 4)
		strategyPopup:Show()
	end)

	CreateLabel(panel, "分组", GROUP_X + 10, -222)
	CreateLabel(panel, "当前分组操作", GROUP_X + 10, -272)
	panel.addGroup = CreateButton(panel, "新建分组", GROUP_X + 100, -270, 72)
	panel.addGroup:SetScript("OnClick", AddGroup)
	panel.deleteGroup = CreateButton(panel, "删除分组", GROUP_X + 176, -270, 72)
	panel.deleteGroup:SetScript("OnClick", DeleteGroup)
	panel.groupUp = CreateButton(panel, "上移", GROUP_X + 252, -270, 48)
	panel.groupUp:SetScript("OnClick", function()
		MoveGroup(-1)
	end)
	panel.groupDown = CreateButton(panel, "下移", GROUP_X + 304, -270, 48)
	panel.groupDown:SetScript("OnClick", function()
		MoveGroup(1)
	end)

	CreateLabel(panel, "本组玩具", GROUP_X + 10, -330)
	panel.groupToyScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	panel.groupToyScroll:SetPoint("TOPLEFT", GROUP_X + 10, -352)
	panel.groupToyScroll:SetSize(348, 232)
	groupToyContent = CreateFrame("Frame", nil, panel.groupToyScroll)
	groupToyContent:SetSize(348, math.ceil(GROUP_TOY_SLOT_COUNT / 3) * 38 + 16)
	panel.groupToyScroll:SetScrollChild(groupToyContent)
	for index = 1, GROUP_TOY_SLOT_COUNT do
		groupToySlots[index] = CreateGroupToySlot(groupToyContent, index)
	end

	CreateLabel(panel, "玩具选择", TOY_X, TOY_Y)
	panel.toySearch = CreateEditBox(panel, "搜索", TOY_X, TOY_Y - 26, 312)
	panel.toySearch:SetScript("OnTextChanged", function()
		toyPage = 1
		RefreshToyList()
	end)

	for index = 1, TOY_PAGE_SIZE do
		toyRows[index] = CreateToyRow(panel, index)
	end

	panel.prevButton = CreateButton(panel, "上一页", TOY_X, -558, 72)
	panel.prevButton:SetScript("OnClick", function()
		toyPage = math.max(1, toyPage - 1)
		RefreshToyList()
	end)
	panel.nextButton = CreateButton(panel, "下一页", TOY_X + 80, -558, 72)
	panel.nextButton:SetScript("OnClick", function()
		local maxPage = math.max(1, math.ceil(#toyList / TOY_PAGE_SIZE))
		toyPage = math.min(maxPage, toyPage + 1)
		RefreshToyList()
	end)
	panel.pageText = CreateLabel(panel, "", TOY_X, -588, 312, "GameFontHighlightSmall")

	actionPopup = CreateActionPopup(panel)
	groupEditPopup = CreateGroupEditPopup(panel)
	strategyPopup = CreateStrategyPopup(panel)

	RefreshPanel()
	panel:Hide()
end

function SmartToyRoller.OpenOptionsPanel()
	if not panel then
		CreateOptionsPanel()
	end

	if panel:IsShown() then
		panel:Hide()
	else
		RefreshPanel()
		panel:Show()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TOYS_UPDATED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		CreateOptionsPanel()
	elseif panel then
		RefreshToyList()
	end
end)
