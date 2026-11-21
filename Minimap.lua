-- Pint's Fishing: a button on the minimap edge. Left-click: Where to Fish (for gold). Right-click: a menu of
-- everything else - Where to Fish for skill, Cook, the tracker, its expanded view, the fishing macro, options.
-- Drag it round the minimap to move it.
local PF = _G.PintsFishing
if not PF then return end

local b = CreateFrame("Button", "PintsFishingMinimapButton", Minimap)
b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local icon = b:CreateTexture(nil, "BACKGROUND"); icon:SetSize(20, 20); icon:SetPoint("TOPLEFT", 7, -5)
icon:SetTexture("Interface\\Icons\\Trade_Fishing")
local border = b:CreateTexture(nil, "OVERLAY"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function Place()
	local a = math.rad((PF.db and PF.db.minimapAngle) or 200)
	local r = (Minimap:GetWidth() / 2) + 10
	b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
b:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local s = Minimap:GetEffectiveScale()
		PF.db.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
		Place()
	end)
end)
b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

-- the menu
local menu = CreateFrame("Frame", "PintsFishingMinimapMenu", UIParent, "BackdropTemplate")
menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
menu:SetBackdropColor(0.02, 0.06, 0.08, 0.97); menu:SetBackdropBorderColor(0.4, 0.6, 0.8, 1)
menu:SetFrameStrata("DIALOG"); menu:Hide()
tinsert(UISpecialFrames, "PintsFishingMinimapMenu")
local ITEMS = {
	{ "Fishing panel", function() PF.TogglePanel() end },
	{ "Where to fish for gold", function() PF.ToggleWhere("gold") end },
	{ "Where to level fishing", function() PF.ToggleWhere("skill") end },
	{ "Cook your catch", function() PF.ToggleCook() end },
	{ "Fish tracker", function() PF.ToggleTracker() end },
	{ "Lifetime fishing details", function() PF.ToggleDetails() end },
	{ "Get the fishing macro", function() PF.MakeMacro() end },
	{ "Options", function() SlashCmdList.PINTSFISHING("") end },
}
local head = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal"); head:SetPoint("TOPLEFT", 10, -8); head:SetText("Pint's Fishing")
for i, it in ipairs(ITEMS) do
	local m = CreateFrame("Button", nil, menu)
	m:SetSize(200, 20); m:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 20)
	m.t = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); m.t:SetPoint("LEFT", 6, 0); m.t:SetText(it[1])
	m:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	m:SetScript("OnClick", function() menu:Hide(); local f = it[2]; pcall(f) end)
end
menu:SetSize(212, 32 + #ITEMS * 20)
-- (a click anywhere else closes it)
menu:SetScript("OnShow", function(self) self.t = 0 end)
menu:SetScript("OnUpdate", function(self, el)
	self.t = (self.t or 0) + el
	if self.t > 0.3 and not self:IsMouseOver() and not b:IsMouseOver() and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then self:Hide() end
end)

b:SetScript("OnClick", function(self, btn)
	if btn == "RightButton" then
		if menu:IsShown() then menu:Hide(); return end
		menu:ClearAllPoints(); menu:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", 0, 0); menu:Show()
	else
		menu:Hide()
		local wf = _G.PintsFishingWhere
		if wf and wf:IsShown() then wf:Hide() elseif PF.ToggleWhere then PF.ToggleWhere("gold") end
	end
end)
b:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Pint's Fishing")
	GameTooltip:AddLine("Left-click: where to fish for gold", 1, 1, 1)
	GameTooltip:AddLine("Right-click: skill, cooking, tracker and more", 1, 1, 1)
	GameTooltip:AddLine("Drag: move round the minimap", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
b:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- placed once settings have loaded; /pfish minimap hides or shows it
local ev = CreateFrame("Frame"); ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
	Place()
	b:SetShown(not (PF.db and PF.db.minimapHide))
end)
function PF.ToggleMinimap()
	PF.db.minimapHide = not PF.db.minimapHide
	b:SetShown(not PF.db.minimapHide)
end
