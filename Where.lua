-- Pint's Fishing: Where to Fish. Two lists, like FishMate's:
--   For skill - the zones where your Fishing skill catches every time (no getaways), and the ones where only a few
--               fish get away, nearest first.
--   For gold  - the zones ranked by what an hour's fishing there is worth: the fish that bite there, priced from
--               Pint's Auctions (else what a vendor pays), your catch chance and your own time per cast.
-- Zone skills are Classic's; WoW Forever's new waters (Zephras Isle, the Riverglades, Shen'dralas, Mount Hyjal) are set from
-- what Wowhead's WoW Forever database shows biting there (November 2026). Your own catches at a zone (20 or more) replace
-- the built-in list of what bites there, so the estimate gets better the more you fish.
local PF = _G.PintsFishing
if not PF then return end
local GII = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

-- zone, base skill (no getaways at base + 95), continent (K Kalimdor, E Eastern Kingdoms), whose capital
local ZONES = {
	{ "Elwynn Forest", -70, "E" }, { "Dun Morogh", -70, "E" }, { "Tirisfal Glades", -70, "E" },
	{ "Durotar", -70, "K" }, { "Mulgore", -70, "K" }, { "Teldrassil", -70, "K" },
	{ "Westfall", -20, "E" }, { "Loch Modan", -20, "E" }, { "Silverpine Forest", -20, "E" },
	{ "Darkshore", -20, "K" }, { "The Barrens", -20, "K" },
	{ "Stormwind City", -20, "E", "Alliance" }, { "Ironforge", -20, "E", "Alliance" }, { "Undercity", -20, "E", "Horde" },
	{ "Orgrimmar", -20, "K", "Horde" }, { "Thunder Bluff", -20, "K", "Horde" }, { "Darnassus", -20, "K", "Alliance" },
	{ "Redridge Mountains", 55, "E" }, { "Duskwood", 55, "E" }, { "Wetlands", 55, "E" }, { "Hillsbrad Foothills", 55, "E" },
	{ "Ashenvale", 55, "K" }, { "Stonetalon Mountains", 55, "K" },
	{ "Arathi Highlands", 130, "E" }, { "Alterac Mountains", 130, "E" }, { "Stranglethorn Vale", 130, "E" },
	{ "Swamp of Sorrows", 130, "E" },
	{ "Desolace", 130, "K" }, { "Dustwallow Marsh", 130, "K" }, { "Thousand Needles", 130, "K" },
	{ "The Hinterlands", 205, "E" }, { "Western Plaguelands", 205, "E" },
	{ "Feralas", 205, "K" }, { "Tanaris", 205, "K" }, { "Felwood", 205, "K" }, { "Azshara", 205, "K" },
	{ "Un'Goro Crater", 205, "K" }, { "Moonglade", 205, "K" },
	{ "Eastern Plaguelands", 330, "E" }, { "Burning Steppes", 330, "E" }, { "Deadwind Pass", 330, "E" },
	{ "Silithus", 330, "K" }, { "Winterspring", 330, "K" },
	-- WoW Forever's new waters (absent on Classic Era, so never listed there)
	{ "Zephras Isle", -70, "Z", nil, true }, { "Riverglades", 130, "E", nil, true }, { "Shen'dralas", 130, "K", nil, true },
	{ "Mount Hyjal", 330, "K", nil, true },
}
-- (for the world map: zone name -> its water's base skill)
PF.ZONE_BASE = {}
for _, z in ipairs(ZONES) do PF.ZONE_BASE[z[1]] = z[2] end
-- what bites, by how hard the water is (an even share each - the real loot tables vary by spot, and coast or lake)
local BITES = {
	[-70] = { 6291, 6303, 6289 },
	[-20] = { 6289, 6308, 6361, 6358, 6303 },
	[55]  = { 6308, 6362, 6358, 6359, 6361 },
	[130] = { 8365, 4603, 6362, 6359, 6358 },
	[205] = { 13758, 13759, 13760, 13754, 4603, 13756 },
	[330] = { 13758, 13759, 13760, 13754, 13888, 13893, 13889, 13422 },
}
-- the chance a bite is landed rather than getting away, from your skill against the water's
local function Chance(skill, base)
	local need = base + 95
	if skill >= need then return 1 end
	return math.max(0, math.min(1, (skill - base + 5) / 100))
end
PF.Chance = Chance

---------------------------------------------------------------- the window
local w = CreateFrame("Frame", "PintsFishingWhere", UIParent, "BackdropTemplate")
w:SetSize(620, 520); w:SetPoint("CENTER")
w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
w:SetBackdropColor(0.05, 0.15, 0.17, 0.95)
w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton"); w:SetClampedToScreen(true); w:SetFrameStrata("HIGH")
w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
w:Hide()
tinsert(UISpecialFrames, "PintsFishingWhere")
local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -16)
local close = CreateFrame("Button", nil, w, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
local mode = "skill"
local tabs = {}
for i, t in ipairs({ { "skill", "For skill" }, { "gold", "For gold" } }) do
	local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); b:SetSize(140, 22); b:SetText(t[2])
	b:SetPoint("TOPLEFT", 22 + (i - 1) * 148, -40)
	b:SetScript("OnClick", function() mode = t[1]; PF.DrawWhere() end)
	tabs[t[1]] = b
end
local note = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); note:SetPoint("TOPLEFT", 24, -70); note:SetWidth(570); note:SetJustifyH("LEFT")
local head = w:CreateFontString(nil, "OVERLAY", "GameFontNormal"); head:SetPoint("TOPLEFT", 24, -118)
local line = w:CreateTexture(nil, "ARTWORK"); line:SetColorTexture(0.8, 0.65, 0.3, 0.6); line:SetHeight(1); line:SetPoint("TOPLEFT", 24, -134); line:SetWidth(570)
local cols = {}
for i = 1, 5 do local c = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c:SetPoint("TOPLEFT", 24, -140); cols[i] = c end
local foot = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); foot:SetPoint("BOTTOMLEFT", 24, 16); foot:SetWidth(570); foot:SetJustifyH("LEFT")
local rows = {}
local ROW = 20
local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, w); r:SetSize(570, ROW); r:SetPoint("TOPLEFT", 24, -158 - (i - 1) * ROW)
	r.c = {}
	for k = 1, 5 do local c = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.c[k] = c end
	r:EnableMouse(true)
	r:SetScript("OnEnter", function(self) if self.zone then PF.WhatBites(self, self.zone) end end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = r
	return r
end
local function Place(fs, x, right)
	fs:ClearAllPoints()
	if right then fs:SetPoint("RIGHT", fs:GetParent(), "LEFT", x, 0); fs:SetJustifyH("RIGHT") else fs:SetPoint("LEFT", x, 0); fs:SetJustifyH("LEFT") end
end
local function MyContinent()
	local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	while m do
		local info = C_Map.GetMapInfo(m)
		if not info then break end
		if info.mapType == 2 then return (info.name == "Kalimdor") and "K" or "E" end
		m = info.parentMapID
	end
end

-- the fish of a zone and how much of each, value per catch, how much of it has a price: your own catches when you
-- have 20 or more there, else the built-in list
local function Mix(z)
	local own, n = {}, 0
	for spot, sp in pairs(PF.CharSpots()) do
		if spot == z[1] or spot:sub(1, #z[1] + 3) == z[1] .. " - " then
			for id, e in pairs(sp.items or {}) do own[id] = (own[id] or 0) + e.n; n = n + e.n end
		end
	end
	local mix = {}
	if n >= 20 then for id, c in pairs(own) do mix[#mix + 1] = { id, c / n } end
	else
		local list = BITES[z[2]] or BITES[-20]
		for _, id in ipairs(list) do mix[#mix + 1] = { id, 1 / #list } end
	end
	local value, priced = 0, 0
	for _, m in ipairs(mix) do
		local p, src = PF.Price(m[1])
		value = value + p * m[2]
		if src == "ah" then priced = priced + m[2] end
	end
	return mix, value, priced, n >= 20
end
function PF.WhatBites(owner, z)
	local mix, _, _, own = Mix(z)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(z[1])
	GameTooltip:AddLine(own and "From your own catches here" or "What usually bites here (your own catches replace this after 20)", 0.7, 0.7, 0.7, true)
	table.sort(mix, function(a, b) return a[2] > b[2] end)
	for _, m in ipairs(mix) do
		local name = GII(m[1]) or ("item " .. m[1])
		local p, src = PF.Price(m[1])
		GameTooltip:AddDoubleLine(("|T%s:14|t %s  |cffaaaaaa%d%%|r"):format((GIcon and GIcon(m[1])) or 134400, name, m[2] * 100 + 0.5),
			p > 0 and (PF.Money(p) .. (src == "vendor" and " |cff888888vendor|r" or "")) or "-", 1, 1, 1)
	end
	GameTooltip:Show()
end

function PF.DrawWhere()
	if not w:IsShown() then return end
	local skill = PF.Skill() or 0
	local myFac = UnitFactionGroup("player")
	local here = MyContinent()
	for k, b in pairs(tabs) do if k == mode then b:LockHighlight() else b:UnlockHighlight() end end
	local list = {}
	for _, z in ipairs(ZONES) do
		if not (z[4] and z[4] ~= myFac) and not (z[5] and type(issecretvalue) ~= "function") then list[#list + 1] = z end
	end
	local out = {}
	if mode == "skill" then
		title:SetText("Where to level fishing")
		note:SetText(("Your skill: %d. Skill-ups don't depend on the zone, but getaways slow you down - pick zones at 100%%. Zone skills are Classic's (WoW Forever's new waters from Wowhead).\nHover a zone to see what bites there."):format(skill))
		head:SetText("Clean catches (no getaways) and nearly")
		for _, z in ipairs(list) do
			local c = Chance(skill, z[2])
			-- the hardest waters you can fish cleanly, plus the ones just past that
			if c >= 0.9 and z[2] + 95 >= skill - 100 then out[#out + 1] = { z = z, c = c } end
		end
		table.sort(out, function(a, b)
			if a.c ~= b.c then return a.c > b.c end
			local ah, bh = a.z[3] == here, b.z[3] == here
			if ah ~= bh then return ah end
			return a.z[2] > b.z[2]
		end)
		local hd = { { "Zone", 0 }, { "Chance", 230, true }, { "Clean from", 320, true }, { "Where", 360 } }
		for i, c in ipairs(cols) do local h = hd[i]; if h then c:SetText(h[1]); c:ClearAllPoints(); if h[3] then c:SetPoint("TOPRIGHT", w, "TOPLEFT", 24 + h[2], -140) else c:SetPoint("TOPLEFT", 24 + h[2], -140) end; c:Show() else c:Hide() end end
		for i, o in ipairs(out) do
			if i > 16 then break end
			local r = Row(i); r.zone = o.z
			local col = o.c >= 1 and "|cff40ff40" or "|cffffd100"
			r.c[1]:SetText(col .. o.z[1] .. "|r"); Place(r.c[1], 0)
			r.c[2]:SetText(col .. math.floor(o.c * 100 + 0.5) .. "%|r"); Place(r.c[2], 230, true)
			r.c[3]:SetText(o.z[2] + 95 <= 0 and "any" or tostring(o.z[2] + 95)); Place(r.c[3], 320, true)
			r.c[4]:SetText(o.z[3] == here and "|cffffffffthis continent|r" or "|cff888888other continent|r"); Place(r.c[4], 360)
			r.c[5]:SetText("")
			r:Show()
		end
		foot:SetText("")
	else
		title:SetText("Where to fish for gold")
		local spc = PF.SecPerCast()
		note:SetText(("Estimate from what bites there and prices (Pint's Auctions, otherwise vendor), about %d s per cast (your own pace once you've made a few casts). Getaways are counted.\nHover a zone to see what bites there and how often."):format(spc))
		head:SetText("Best money")
		for _, z in ipairs(list) do
			local c = Chance(skill, z[2])
			if c > 0 then
				local _, value, priced = Mix(z)
				out[#out + 1] = { z = z, c = c, per = value, hour = value * c * 3600 / spc, priced = priced }
			end
		end
		table.sort(out, function(a, b) return a.hour > b.hour end)
		local hd = { { "Zone", 0 }, { "Chance", 230, true }, { "Per catch", 330, true }, { "Per hour", 450, true }, { "Prices", 540, true } }
		for i, c in ipairs(cols) do local h = hd[i]; c:SetText(h[1]); c:ClearAllPoints(); c:SetPoint("TOPRIGHT", w, "TOPLEFT", 24 + h[2], -140); if not h[3] then c:ClearAllPoints(); c:SetPoint("TOPLEFT", 24, -140) end; c:Show() end
		for i, o in ipairs(out) do
			if i > 16 then break end
			local r = Row(i); r.zone = o.z
			local col = o.c >= 1 and "|cff40ff40" or "|cffffd100"
			r.c[1]:SetText(col .. o.z[1] .. "|r"); Place(r.c[1], 0)
			r.c[2]:SetText(col .. math.floor(o.c * 100 + 0.5) .. "%|r"); Place(r.c[2], 230, true)
			r.c[3]:SetText(PF.Money(o.per)); Place(r.c[3], 330, true)
			r.c[4]:SetText(PF.Money(o.hour)); Place(r.c[4], 450, true)
			r.c[5]:SetText("|cffaaaaaa" .. math.floor(o.priced * 100 + 0.5) .. "%|r"); Place(r.c[5], 540, true)
			r:Show()
		end
		foot:SetText("\"Prices\" is how much of the catch has an auction price - the lower it is, the rougher the estimate. Scan the auction house with Pint's Auctions to fill it in.")
	end
	for i = math.min(#out, 16) + 1, #rows do rows[i]:Hide() end
	w:SetHeight(158 + math.min(#out, 16) * ROW + 50)
end
w:SetScript("OnShow", PF.DrawWhere)
function PF.ToggleWhere(m) if m then mode = m end; if w:IsShown() and not m then w:Hide() else w:Show(); PF.DrawWhere() end end
