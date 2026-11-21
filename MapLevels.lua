-- Pint's Fishing: fishing levels on the world map. Under the zone name the map shows when you point at a zone (on a zone,
-- continent or world map), a line in the same style: "(Fishing 55-150)" - the lowest skill anything bites at, and where
-- nothing gets away - coloured for your skill: green - nothing gets away, yellow - some do, red - nothing bites for you
-- yet. On a zone's own map (pointing at nothing) its name and level show the same way.
-- Zone skills are Classic's, plus WoW Forever's new waters (from Wowhead).  /pfish maplevels turns it off or on.
local PF = _G.PintsFishing
if not (PF and WorldMapFrame and C_Map and C_Map.GetMapInfo) then return end

local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
local function On() return not (PintsFishingDB and PintsFishingDB.mapLevels == false) end

local function ZoneOf(mapID)
	local info = C_Map.GetMapInfo(mapID)
	while info and info.mapType and info.mapType > ZONE and info.parentMapID and info.parentMapID > 0 do
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	return info
end
-- "(Fishing 55-150)" coloured for your skill
local function Short(name)
	local base = PF.ZONE_BASE and PF.ZONE_BASE[name]
	if not base then return end
	local skill = (PF.Skill and PF.Skill()) or 0
	local c = PF.Chance and PF.Chance(skill, base) or 0
	local col = (c >= 1 and "|cff40ff40") or (c > 0 and "|cffffd100") or "|cffff6060"
	return ("%s(Fishing %d-%d)|r"):format(col, math.max(1, base + 5), base + 95)
end
PF.ZoneFishingShort = Short

-- the map's own zone-name label (the big name when you point at a zone): our line goes under it, in its own font
local label
local function FindLabel()
	if label then return label end
	for dp in pairs(WorldMapFrame.dataProviders or {}) do
		local l = type(dp) == "table" and dp.Label
		if type(l) == "table" and l.Name and l.Description and l.Name.GetText then label = l; return l end
	end
end
-- our own copy of that label's look, for a zone's own map when you're pointing at nothing
local holder = WorldMapFrame.ScrollContainer or WorldMapFrame
local own = CreateFrame("Frame", nil, holder); own:SetAllPoints(holder); own:SetFrameLevel((holder:GetFrameLevel() or 1) + 40)
own.name = own:CreateFontString(nil, "OVERLAY", "WorldMapTextFont" and _G.WorldMapTextFont and "WorldMapTextFont" or "GameFontNormalHuge")
own.name:SetPoint("TOP", own, "TOP", 0, -12)
own.sub = own:CreateFontString(nil, "OVERLAY", "SubZoneTextFont" and _G.SubZoneTextFont and "SubZoneTextFont" or "GameFontHighlightLarge")
own.sub:SetPoint("TOP", own.name, "BOTTOM", 0, -2)
own:Hide()

local mine          -- our line under the game's label (its own font string, so the game never overwrites it)
local acc = 0
local watch = CreateFrame("Frame", nil, WorldMapFrame)
watch:SetScript("OnUpdate", function(_, el)
	acc = acc + el
	if acc < 0.05 then return end
	acc = 0
	local l = FindLabel()
	if l and not mine then
		mine = l:CreateFontString(nil, "OVERLAY")
		local font, size, flags = l.Description:GetFont()
		if font then mine:SetFont(font, size or 14, flags) else mine:SetFontObject("GameFontHighlightLarge") end
		mine:SetShadowColor(0, 0, 0, 1); mine:SetShadowOffset(1, -1)
	end
	local shown = l and l:IsShown() and l.Name:IsShown() and l.Name:GetText()
	if shown and shown ~= "" then
		own:Hide()
		local f = On() and Short(shown)
		if f then
			local d = l.Description:IsShown() and l.Description:GetText()
			mine:ClearAllPoints(); mine:SetPoint("TOP", (d and d ~= "") and l.Description or l.Name, "BOTTOM", 0, -2)
			mine:SetText(f); mine:Show()
		else mine:Hide() end
		return
	end
	if mine then mine:Hide() end
	-- nothing pointed at: a zone's own map shows its name and fishing level the same way
	local id = WorldMapFrame:GetMapID()
	local info = id and C_Map.GetMapInfo(id)
	local f, z
	if On() and info and info.mapType and info.mapType >= ZONE then z = ZoneOf(id); f = z and Short(z.name) end
	if f then own.name:SetText(z.name); own.sub:SetText(f); own:Show() else own:Hide() end
end)
WorldMapFrame:HookScript("OnHide", function() own:Hide(); if mine then mine:Hide() end end)

-- /pfish maplevels
local prev = SlashCmdList.PINTSFISHING
SlashCmdList.PINTSFISHING = function(msg)
	local m = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if m == "maplevels" or m == "map" then
		PintsFishingDB = PintsFishingDB or {}
		PintsFishingDB.mapLevels = not On() and true or false
		print("|cff33ccffPint's Fishing|r: fishing levels on the world map " .. (On() and "on" or "off") .. ".")
	elseif prev then prev(msg) end
end
