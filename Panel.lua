-- Pint's Fishing: the fishing panel (laid out like FishMate's). Everything at a glance while you fish: on/off, your keys,
-- what the key does right now, skill and catches per skill point, getaways here, lure (with an apply button), pole and
-- weapon swap, this session's casts, catches, junk and value, the Stranglethorn contest countdown, containers to open,
-- selling grey items, the last fishing pool you saw here - and buttons for everything else.
--   /pfish panel, or "Fishing panel" on the minimap button's right-click menu.
local PF = _G.PintsFishing
if not PF then return end
local GII = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GIII = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local Count = (C_Item and C_Item.GetItemCount) or GetItemCount
local C = C_Container or {}
local NumSlots = C.GetContainerNumSlots or GetContainerNumSlots
local ItemID = C.GetContainerItemID or GetContainerItemID
local ItemInfo = C.GetContainerItemInfo
local UseItem = C.UseContainerItem or UseContainerItem
local CHAR = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
local W = 330

local function Clock(sec)
	sec = math.floor(sec or 0)
	local h, m, s = math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60
	if h > 0 then return ("%dh %dm"):format(h, m) end
	if m > 0 then return ("%dm %ds"):format(m, s) end
	return s .. "s"
end
local Y, G, R, O, D = "|cffffd100%s|r", "|cff40ff40%s|r", "|cffff4040%s|r", "|cffff8040%s|r", "|cff999999%s|r"

---------------------------------------------------------------- the window
local f = CreateFrame("Frame", "PintsFishingPanel", UIParent, "BackdropTemplate")
f:SetSize(W, 400); f:SetPoint("CENTER", -300, 60)
f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
f:SetBackdropColor(0.05, 0.15, 0.17, 0.95)
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local p, _, rp, x, y = self:GetPoint(1); PF.db.panelPos = { p, rp, x, y }
end)
f:Hide()
local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -16); title:SetText("|cffd4a017Pint's|r Fishing")
local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
close:SetScript("OnClick", function() f:Hide(); PF.db.panelShown = false end)
local function Btn(text, w, h, secure)
	local b = CreateFrame("Button", nil, f, secure and "SecureActionButtonTemplate,UIPanelButtonTemplate" or "UIPanelButtonTemplate")
	b:SetSize(w, h or 22); b:SetText(text)
	if secure then b:RegisterForClicks("AnyUp") end
	return b
end
local function Tip(b, ...)
	local lines = { ... }
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		for i, l in ipairs(lines) do if i == 1 then GameTooltip:AddLine(l) else GameTooltip:AddLine(l, 1, 1, 1, true) end end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local settings = Btn("Settings", 74, 20); settings:SetPoint("TOPLEFT", 14, -14)
settings:SetScript("OnClick", function() SlashCmdList.PINTSFISHING("") end)

-- the parts, top to bottom (laid out again on every redraw, since lines come and go)
local onoff = Btn("Fishing: ON", W - 28, 26)
onoff:SetScript("OnClick", function() PF.SetEnabled(PF.db.enabled == false) ; PF.DrawPanel() end)
Tip(onoff, "Fishing on or off", "Off: your keys and mouse buttons work as normal, and nothing is changed while you fish (sound, targeting).")
local function Text(font)
	local t = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	t:SetWidth(W - 32); t:SetJustifyH("LEFT"); t:SetSpacing(2)
	return t
end
local keysT, statusT, skillT = Text(), Text(), Text()
local lureT = Text(); lureT:SetWidth(150)
local lureB = Btn("Lure", 150, 22, true)
Tip(lureB, "Apply a lure", "Puts the best lure in your bags on your fishing pole.")
local poleB = Btn("Pole", 146, 22, true)
local weapB = Btn("Weapon", 146, 22, true)
Tip(poleB, "Fishing pole", "Equips the best fishing pole in your bags.")
Tip(weapB, "Weapons", "Puts back the weapons you had on before the pole.")
local sessT, contestT = Text(), Text()
local openB = Btn("No containers", 146, 22, true)
Tip(openB, "Open containers", "Opens the next clam, crate, trunk or bloated fish in your bags - one each click.")
local greyB = Btn("Sell grey", 146, 22)
Tip(greyB, "Sell grey", "Sells every grey item in your bags. Works with a vendor open.")
local poolT = Text()
local GRID = {
	{ "Tracker", function() PF.ToggleTracker() end }, { "Details", function() PF.ToggleDetails() end },
	{ "Reset", function() PF.ResetSession(); PF.DrawPanel() end },
	{ "Where: skill", function() PF.ToggleWhere("skill") end }, { "Where: gold", function() PF.ToggleWhere("gold") end },
	{ "Cook", function() PF.ToggleCook() end },
	{ "Get macro", function() PF.MakeMacro() end }, { "Minimap", function() if PF.ToggleMinimap then PF.ToggleMinimap() end end },
	{ "Help", function()
		print("|cffd4a017Pint's Fishing:|r bind Options > Keybindings > Pint's Fishing > Cast and hook, or put the fishing macro on a bar button (\"Get macro\"). Press once to cast, again on the splash to hook.")
	end },
}
local grid = {}
for i, g in ipairs(GRID) do
	local b = Btn(g[1], 96, 22); b:SetScript("OnClick", function() pcall(g[2]) end)
	grid[i] = b
end
Tip(grid[3], "Reset", "Starts this session's counts over.")
Tip(grid[8], "Minimap button", "Hides or shows the minimap button.")

---------------------------------------------------------------- what's in your bags
local LURES = { { 6533, 100 }, { 7307, 75 }, { 6532, 75 }, { 6811, 50 }, { 6530, 50 }, { 6529, 25 } }   -- best first
local function BestLure() for _, l in ipairs(LURES) do local n = Count(l[1]); if n and n > 0 then return l[1], l[2], n end end end
local function IsPole(id) if not id then return false end local _, _, _, _, _, c, s = GIII(id); return c == 2 and s == 20 end
local function Bags(fn)
	for bag = 0, 4 do
		for slot = 1, (NumSlots(bag) or 0) do
			local id = ItemID(bag, slot)
			if id and fn(bag, slot, id) then return end
		end
	end
end
local function BestPole()
	local best, lvl
	Bags(function(_, _, id)
		if IsPole(id) then local l = select(4, GII(id)) or 0; if not best or l > lvl then best, lvl = id, l end end
	end)
	return best
end
-- something to open: anything in your bags that has loot inside (clams, crates, trunks, bloated fish...)
local function Openable()
	local first, n
	n = 0
	if not ItemInfo then return nil, 0 end
	Bags(function(bag, slot)
		local info = ItemInfo(bag, slot)
		if info and info.hasLoot and not info.isLocked then n = n + 1; first = first or { bag, slot } end
	end)
	return first, n
end
local function Greys()
	local n, value = 0, 0
	Bags(function(bag, slot, id)
		local _, _, q, _, _, _, _, _, _, _, sell = GII(id)
		if q == 0 and (sell or 0) > 0 then
			local info = ItemInfo and ItemInfo(bag, slot)
			local c = info and info.stackCount or 1
			n = n + c; value = value + sell * c
		end
	end)
	return n, value
end
greyB:SetScript("OnClick", function()
	if not (MerchantFrame and MerchantFrame:IsShown()) then UIErrorsFrame:AddMessage("Open a vendor first", 1, 0.3, 0.3); return end
	Bags(function(bag, slot, id)
		local _, _, q, _, _, _, _, _, _, _, sell = GII(id)
		if q == 0 and (sell or 0) > 0 then UseItem(bag, slot) end
	end)
end)

-- your weapons, remembered whenever you're holding something other than a pole
local function RememberWeapons()
	local db = PF.db
	if not db then return end
	local mh = GetInventoryItemID("player", 16)
	if not mh or IsPole(mh) then return end
	db.weapons = db.weapons or {}
	db.weapons[CHAR] = { mh = mh, oh = GetInventoryItemID("player", 17) }
end

---------------------------------------------------------------- the contest: Stranglethorn Fishing Extravaganza, Sundays 2-4pm realm time
local function Contest()
	if not (C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime) then return end
	local ok, t = pcall(C_DateAndTime.GetCurrentCalendarTime)
	if not ok or not t or not t.weekday then return end
	local now = (t.weekday - 1) * 1440 + t.hour * 60 + t.minute
	local start, stop = 14 * 60, 16 * 60
	if now >= start and now < stop then return "|cff40ff40on now|r - ends in " .. Clock((stop - now) * 60) end
	local wait = (now < start) and (start - now) or (7 * 1440 - now + start)
	local d, h, m = math.floor(wait / 1440), math.floor((wait % 1440) / 60), wait % 60
	return d > 0 and ("in %dd %dh"):format(d, h) or ("in %dh %dm"):format(h, m)
end

---------------------------------------------------------------- pools: noted when you mouse over one
local POOL = { "School", "Pool", "Wreckage", "Debris", "Floating", "Oily", "Swarm", "Elemental Water", "Shoal" }
local function Zone() return GetRealZoneText() or "?" end
GameTooltip:HookScript("OnShow", function(tt)
	if not PF.db then return end
	if tt.GetUnit then local ok, u = pcall(tt.GetUnit, tt); if ok and u then return end end
	if tt.GetItem then local ok, n = pcall(tt.GetItem, tt); if ok and n then return end end
	local l = _G.GameTooltipTextLeft1
	local name = l and l:GetText()
	if not name or (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then return end
	local hit
	for _, w in ipairs(POOL) do if name:find(w, 1, true) then hit = true; break end end
	if not hit or name:find("Fishing", 1, true) then return end
	local x, y
	if C_Map and C_Map.GetBestMapForUnit then
		local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
		if ok and map then
			local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
			if ok2 and pos then local px, py = pos:GetXY(); if not (issecretvalue and issecretvalue(px)) then x, y = px, py end end
		end
	end
	PF.db.pools = PF.db.pools or {}
	PF.db.pools[Zone()] = { name = name, x = x, y = y, t = time() }
end)

---------------------------------------------------------------- drawing
local secureSet = {}
local function SetMacro(b, text)
	if secureSet[b] == text then return end
	secureSet[b] = text
	b:SetAttribute("type", text and "macro" or nil); b:SetAttribute("macrotext", text)
end
function PF.DrawPanel()
	if not f:IsShown() or not PF.db or InCombatLockdown() then return end
	local db = PF.db
	local on = db.enabled ~= false
	onoff:SetText(on and "|cff40ff40Fishing: ON|r" or "|cffff4040Fishing: OFF|r")

	-- keys
	local k = PF.Keys and PF.Keys() or {}
	local mk = PF.MacroKeys and PF.MacroKeys() or {}
	local names = {}
	for _, key in ipairs(k) do names[#names + 1] = GetBindingText(key) end
	for _, key in ipairs(mk) do names[#names + 1] = GetBindingText(key) .. " (macro)" end
	local kt = "Cast and hook: " .. (#names > 0 and Y:format(table.concat(names, ", ")) or R:format("no key yet") .. " - Options > Keybindings > Pint's Fishing, or Get macro")
	if db.doubleClick then kt = kt .. "\nor double right-click the world to cast" .. (db.poleOnly and " (with a pole on)" or "") end
	keysT:SetText(kt)

	-- what the key does right now
	local pole = PF.HasPole and PF.HasPole()
	local st
	if not on then st = D:format("Off - your keys work as normal")
	elseif PF.IsFishing and PF.IsFishing() then st = G:format("Line out - press the key on the splash to hook")
	elseif not pole then st = O:format("No fishing pole on - the Pole button puts one on")
	else st = G:format("Ready - press the key to cast") end
	statusT:SetText(st)

	-- skill, catches per skill point, getaways here
	local rank, max = PF.Skill and PF.Skill()
	local s = {}
	if rank then
		local per = rank < 75 and 1 or ((rank - 75) / 25 + 1)
		local line = ("Skill: |cff40ff40%d|r/%d"):format(rank, max or 0)
		if max and rank >= max then line = line .. (max < 300 and O:format("  - train Fishing to go higher") or "")
		else line = line .. (", ~%.1f catches per point"):format(per) end
		s[#s + 1] = line
	end
	local casts, catches, here = 0, 0, Zone()
	if PF.SpotStats then casts, catches, here = PF.SpotStats() end
	s[#s + 1] = Y:format(here) .. (casts > 0 and ("\nGetaways %d%% of %d casts here"):format(math.floor((casts - catches) / casts * 100 + 0.5), casts) or D:format("  - no casts here yet"))
	skillT:SetText(table.concat(s, "\n"))

	-- lure
	local lure = PF.LureLeft and PF.LureLeft()
	if lure == nil then lureT:SetText("Lure: " .. D:format("no pole on"))
	elseif lure == false then lureT:SetText("Lure: " .. R:format("none"))
	else lureT:SetText("Lure: " .. (lure < 60 and O or G):format(Clock(lure))) end
	local lid, bonus, ln = BestLure()
	if lid then SetMacro(lureB, "/use item:" .. lid .. "\n/use 16"); lureB:SetText(("Lure +%d (%d)"):format(bonus, ln)); lureB:Enable()
	else SetMacro(lureB, nil); lureB:SetText("No lures"); lureB:Disable() end

	-- pole and weapons
	local bp = BestPole()
	if pole then poleB:SetText("Pole (on)"); poleB:Disable(); SetMacro(poleB, nil)
	elseif bp then poleB:SetText("Pole"); poleB:Enable(); SetMacro(poleB, "/equipslot 16 item:" .. bp)
	else poleB:SetText("No pole in bags"); poleB:Disable(); SetMacro(poleB, nil) end
	local wp = db.weapons and db.weapons[CHAR]
	if pole and wp and wp.mh and Count(wp.mh) > 0 then
		weapB:SetText("Weapon"); weapB:Enable()
		SetMacro(weapB, "/equipslot 16 item:" .. wp.mh .. (wp.oh and ("\n/equipslot 17 item:" .. wp.oh) or ""))
	else weapB:SetText(pole and "No weapon noted" or "Weapon (on)"); weapB:Disable(); SetMacro(weapB, nil) end

	-- this session
	local sc, sk, junk, value, started, startSkill = 0, 0, 0, 0
	if PF.SessionStats then sc, sk, junk, value, started, startSkill = PF.SessionStats() end
	local sess = {}
	if started then
		local secs = GetTime() - started
		sess[#sess + 1] = ("Session %s: %s casts, %s catches, %s junk"):format(Clock(secs), G:format(sc), G:format(sk), D:format(junk))
		sess[#sess + 1] = ("Getaways %s (%s)"):format(O:format(math.max(0, sc - sk)), sc > 0 and ("%.0f%%"):format((sc - sk) / sc * 100) or "-")
		local hours = math.max(secs / 3600, 1 / 60)
		sess[#sess + 1] = "Value: " .. PF.Money(value) .. "   per hour: " .. PF.Money(value / hours)
		if rank and startSkill and rank > startSkill then sess[#sess + 1] = "Skill gained: " .. G:format("+" .. (rank - startSkill)) end
	else
		sess[#sess + 1] = D:format("Session: no casts yet")
	end
	sessT:SetText(table.concat(sess, "\n"))
	local ct = Contest()
	contestT:SetText(ct and ("Stranglethorn contest: " .. ct) or "")

	-- containers and greys
	local first, n = Openable()
	if first then openB:SetText(("Open (%d)"):format(n)); openB:Enable(); SetMacro(openB, "/use " .. first[1] .. " " .. first[2])
	else openB:SetText("No containers"); openB:Disable(); SetMacro(openB, nil) end
	local gn, gv = Greys()
	local vendor = MerchantFrame and MerchantFrame:IsShown()
	greyB:SetText(gn > 0 and ("Sell grey (%d)"):format(gn) or "No grey")
	greyB:SetEnabled(gn > 0 and vendor and true or false)
	greyB.value = gv

	-- the last pool you saw in this zone
	local p = db.pools and db.pools[Zone()]
	if p then
		local where = p.x and (" (%.1f, %.1f)"):format(p.x * 100, p.y * 100) or ""
		poolT:SetText("Pool: " .. Y:format(p.name) .. where .. " - " .. Clock(time() - p.t) .. " ago")
	else poolT:SetText("Pool: " .. D:format("none seen here yet (mouse over one to note it)")) end

	-- lay it all out
	local y = 44
	local function Place(r, h, x) r:ClearAllPoints(); r:SetPoint("TOPLEFT", x or 14, -y); y = y + h end
	local function PlaceText(t) if (t:GetText() or "") == "" then t:Hide(); return end t:Show(); Place(t, t:GetStringHeight() + 8, 16) end
	Place(onoff, 32)
	PlaceText(keysT); PlaceText(statusT); PlaceText(skillT)
	lureT:ClearAllPoints(); lureT:SetPoint("LEFT", f, "TOPLEFT", 16, -(y + 11)); lureT:Show()
	lureB:ClearAllPoints(); lureB:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -y); y = y + 28
	Place(poleB, 0); weapB:ClearAllPoints(); weapB:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -y); y = y + 32
	PlaceText(sessT); PlaceText(contestT)
	Place(openB, 0); greyB:ClearAllPoints(); greyB:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -y); y = y + 30
	PlaceText(poolT)
	y = y + 4
	for i, b in ipairs(grid) do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		b:ClearAllPoints(); b:SetPoint("TOPLEFT", 14 + col * 101, -(y + row * 26))
	end
	y = y + math.ceil(#grid / 3) * 26 + 12
	f:SetHeight(y)
end

---------------------------------------------------------------- when it updates
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
	"UPDATE_BINDINGS", "SKILL_LINES_CHANGED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_CHANNEL_START", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
local reopen
ev:SetScript("OnEvent", function(_, e)
	if e == "PLAYER_LOGIN" then
		local p = PF.db and PF.db.panelPos
		if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
		RememberWeapons()
		if PF.db and PF.db.panelShown then f:Show() end
	elseif e == "PLAYER_EQUIPMENT_CHANGED" then
		RememberWeapons()
	elseif e == "PLAYER_REGEN_DISABLED" then
		-- (it holds secure buttons: out of the way in a fight, back after)
		if f:IsShown() then reopen = true; f:Hide() end
		return
	elseif e == "PLAYER_REGEN_ENABLED" then
		if reopen then reopen = nil; f:Show() end
	end
	PF.DrawPanel()
end)
local acc = 0
f:SetScript("OnUpdate", function(_, el) acc = acc + el; if acc >= 1 then acc = 0; PF.DrawPanel() end end)
f:SetScript("OnShow", function() PF.DrawPanel() end)
function PF.TogglePanel()
	if InCombatLockdown() then return end
	if f:IsShown() then f:Hide(); PF.db.panelShown = false else f:Show(); PF.db.panelShown = true end
end
