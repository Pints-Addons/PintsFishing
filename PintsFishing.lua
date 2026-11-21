-- Pint's Fishing: fish with one key. Press it to cast; when the bobber splashes, press the same key to hook the fish
-- (it interacts with the bobber through the game's soft targeting). Optional: double right-click to cast, louder
-- splashes while you fish, and instant looting of everything (fish or not) without the loot window flashing up.
--   Keybinding: Options > Keybindings > Pint's Fishing > Cast and hook.   /pfish for the options.
local ADDON = ...
local PF = {}
_G.PintsFishing = PF

local DEFAULTS = {
	enabled = true,        -- Fishing ON/OFF (the panel's big button): off, keys work as normal and nothing changes
	tracker = true,        -- the fish tracker overlay while you fish
	lureSound = true,      -- a sound when a lure goes on / runs out
	doubleClick = false,   -- double right-click on the world to cast (while a fishing pole is equipped)
	sound = true,          -- louder sound effects, music and ambience down, while fishing
	softTarget = true,     -- turn on soft targeting of objects while fishing (so the key can hook the bobber)
	fastLoot = true,       -- loot everything at once when auto loot is on (any loot, not just fish)
	poleOnly = true,       -- double right-click only with a fishing pole in hand
}
local db
local function Print(msg) print("|cffd4a017Pint's Fishing:|r " .. msg) end

local GetSpellInfo = GetSpellInfo or function(s)
	local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s)
	if i then return i.name, nil, i.iconID end
end
local FISHING = GetSpellInfo(7620) or "Fishing"
PF.FISHING = FISHING

---------------------------------------------------------------- the cast button (secure: only it may cast a spell)
local cast = CreateFrame("Button", "PintsFishingCast", UIParent, "SecureActionButtonTemplate")
cast:SetAttribute("type", "spell")
cast:SetAttribute("spell", FISHING)
cast:RegisterForClicks("AnyUp")   -- (the same as Pint's Heals' bars, which click fine on every client)
cast:Hide()   -- (a hidden secure button still clicks through a binding)

-- which keys are bound to "Cast and hook", and what they do right now: cast, or hook (interact with the bobber)
local owner = CreateFrame("Frame")
local mode            -- "cast" or "hook"
local function Keys()
	local k = { GetBindingKey("PINTSFISHING_CAST") }
	return k
end

-- The macro: put it on any action bar button and that button's key (a mouse button too) fishes as well. Clicking it
-- casts; while the line is out, its key hooks the fish instead.
local MACRO = "PintsFishing"
local BAR_COMMANDS = {   -- action slots -> the binding that presses them
	{ 1, 12, "ACTIONBUTTON" }, { 61, 72, "MULTIACTIONBAR1BUTTON" }, { 49, 60, "MULTIACTIONBAR2BUTTON" },
	{ 25, 36, "MULTIACTIONBAR3BUTTON" }, { 37, 48, "MULTIACTIONBAR4BUTTON" },
}
-- (on WoW Forever a macro that shows a spell reports that spell's id, not the macro's number - so its name is checked)
function PF.IsOurs(slot, mi)
	local kind, id = GetActionInfo(slot)
	if kind ~= "macro" then return false end
	if id == mi then return true end
	local t = GetActionText and GetActionText(slot)
	return t == MACRO
end
local function MacroKeys()
	local out = {}
	local mi = GetMacroIndexByName and GetMacroIndexByName(MACRO)
	if not mi or mi == 0 then return out end
	local slots = {}
	for slot = 1, 180 do if PF.IsOurs(slot, mi) then slots[slot] = true end end
	if not next(slots) then return out end
	local function Add(cmd) for _, k in ipairs({ GetBindingKey(cmd) }) do out[#out + 1] = k end end
	for _, r in ipairs(BAR_COMMANDS) do
		for slot = r[1], r[2] do if slots[slot] then Add(r[3] .. (slot - r[1] + 1)) end end
	end
	-- other bar add-ons' buttons (Pint's Bars and the like): any action button holding the macro, by its click binding
	local f = EnumerateFrames()
	while f do
		if not f:IsForbidden() and f.GetAttribute and f:GetName() then
			local ok, a = pcall(f.GetAttribute, f, "action")
			if ok and type(a) == "number" and slots[a] then Add("CLICK " .. f:GetName() .. ":LeftButton") end
		end
		f = EnumerateFrames(f)
	end
	return out
end
function PF.MakeMacro()
	if InCombatLockdown() then Print("not in a fight."); return end
	-- (it casts Fishing itself - a /click of our button did nothing from a bar on WoW Forever - and not while the line
	-- is out, so a click can't recast and lose the bobber; the hooking is done by its key)
	local body = "#showtooltip " .. FISHING .. "\n/cast [nochanneling:" .. FISHING .. "] " .. FISHING
	local mi = GetMacroIndexByName(MACRO)
	if mi == 0 then
		local nG = GetNumMacros()
		if nG >= (MAX_ACCOUNT_MACROS or 120) then Print("your account macros are full - delete one first."); return end
		mi = CreateMacro(MACRO, "INV_Misc_Fish_02", body, nil)
	else
		EditMacro(mi, MACRO, "INV_Misc_Fish_02", body)
	end
	if mi and mi > 0 then
		PickupMacro(mi)
		Print("drag the macro onto any action bar button - its key (or mouse button) then casts and hooks.")
	end
end

local lastSig
local function SetMode(m, force)
	if InCombatLockdown() then PF.pending = true; return end
	if db and db.enabled == false then
		ClearOverrideBindings(owner); cast:SetAttribute("type", "spell"); mode = "cast"; lastSig = nil
		return
	end
	local keys, mkeys = Keys(), MacroKeys()
	local sig = m .. "|" .. table.concat(keys, ",") .. "|" .. table.concat(mkeys, ",")
	if sig == lastSig and not force then return end      -- (nothing changed: setting them again would loop)
	lastSig = sig
	mode = m
	ClearOverrideBindings(owner)
	-- casting: our own key clicks the cast button; the macro's keys stay as they are (the bar button casts)
	-- hooking: all of them interact with the bobber, and the cast button stops casting (so a click can't recast)
	for _, key in ipairs(keys) do
		if m == "hook" then SetOverrideBinding(owner, true, key, "INTERACTTARGET")
		else SetOverrideBindingClick(owner, true, key, "PintsFishingCast", "LeftButton") end
	end
	if m == "hook" then for _, key in ipairs(mkeys) do SetOverrideBinding(owner, true, key, "INTERACTTARGET") end end
	cast:SetAttribute("type", m == "hook" and "" or "spell")
	PF.dblArmed = nil
end

---------------------------------------------------------------- while fishing: soft targeting and sound
-- (settings are changed only while you fish, and put back as they were a little while after you stop)
local saved
local SOFT = { SoftTargetInteract = "3", SoftTargetIconGameObject = "1", SoftTargetInteractArc = "2", SoftTargetInteractRange = "40" }
-- (music and ambience down only: turning sound effects up made other anglers' splashes as loud as yours)
local LOUD = { Sound_MusicVolume = "0", Sound_AmbienceVolume = "0" }
local function Session(on)
	if on then
		if saved then return end
		saved = {}
		local function Apply(t) for k, v in pairs(t) do local cur = GetCVar(k); if cur ~= nil then saved[k] = cur; pcall(SetCVar, k, v) end end end
		if db.softTarget then Apply(SOFT) end
		if db.sound then Apply(LOUD); if not GetCVarBool("Sound_EnableSFX") then saved.Sound_EnableSFX = "0"; pcall(SetCVar, "Sound_EnableSFX", "1") end end
		db.savedCVars = saved
	else
		if not saved then return end
		for k, v in pairs(saved) do pcall(SetCVar, k, v) end
		saved = nil
		db.savedCVars = nil
	end
end
local idleTimer
local function KeepSession()
	Session(true)
	if idleTimer then idleTimer:Cancel() end
	-- (20 seconds after the last cast ends, everything goes back to how it was)
	idleTimer = C_Timer.NewTimer(20, function() idleTimer = nil; if not UnitChannelInfo("player") then Session(false) end end)
end

local function Fishing()
	local name = UnitChannelInfo("player")
	return name and not (issecretvalue and issecretvalue(name)) and name == FISHING
end

---------------------------------------------------------------- double right-click to cast
-- The first right-click on the world arms the right mouse button for a moment; the second one casts.
local function HasPole()
	local link = GetInventoryItemLink("player", 16)
	if not link then return false end
	local GIII = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local _, _, _, _, _, classID, subID = GIII(link)
	return classID == 2 and subID == 20
end
local dblOwner = CreateFrame("Frame")
local lastDown = 0
WorldFrame:HookScript("OnMouseDown", function(_, button)
	if button ~= "RightButton" or not db or not db.doubleClick or InCombatLockdown() then return end
	if db.poleOnly and not HasPole() then return end
	if UnitExists("mouseover") or Fishing() then return end
	local now = GetTime()
	if now - lastDown < 0.4 then return end
	lastDown = now
	SetOverrideBindingClick(dblOwner, true, "BUTTON2", "PintsFishingCast", "LeftButton")
	PF.dblArmed = true
	C_Timer.After(0.4, function() if not InCombatLockdown() then ClearOverrideBindings(dblOwner) end; PF.dblArmed = nil end)
end)

---------------------------------------------------------------- fast loot
-- With auto loot on, every slot is taken the moment the loot is ready, and the loot window stays out of sight (it
-- comes back if something can't be taken - bags full, a roll, a quest item you can't carry).
local looting = false
local lf = CreateFrame("Frame")
lf:RegisterEvent("LOOT_READY"); lf:RegisterEvent("LOOT_CLOSED")
pcall(lf.RegisterEvent, lf, "LOOT_OPENED")
lf:SetScript("OnEvent", function(_, e, auto)
	-- a catch: what came up, for the tracker (read before anything is looted)
	if e == "LOOT_CLOSED" then PF.recorded = nil
	elseif not PF.recorded and IsFishingLoot and IsFishingLoot() and PF.OnCatch then
		PF.recorded = true
		local got = {}
		for i = 1, GetNumLootItems() do
			local link = GetLootSlotLink(i)
			local _, name, qty = GetLootSlotInfo(i)
			if link then got[#got + 1] = { id = tonumber(link:match("item:(%d+)")), name = name, n = qty or 1 } end
		end
		pcall(PF.OnCatch, got)
	end
	if not db or not db.fastLoot then return end
	if e == "LOOT_CLOSED" then
		looting = false
		if LootFrame then LootFrame:SetAlpha(1) end
		return
	end
	if looting then return end
	local autoLoot = auto
	if autoLoot == nil then autoLoot = GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") end
	if not autoLoot then return end
	looting = true
	if LootFrame then LootFrame:SetAlpha(0) end
	for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
	-- anything left a moment later couldn't be taken: show the window so you can deal with it
	C_Timer.After(0.3, function()
		if looting and GetNumLootItems() > 0 and LootFrame then LootFrame:SetAlpha(1) end
	end)
end)

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS" }) do pcall(ev.RegisterEvent, ev, e) end
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_CHANNEL_START", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_CHANNEL_STOP", "player")
ev:SetScript("OnEvent", function(_, e, a1)
	if e == "ADDON_LOADED" then
		if a1 ~= ADDON then return end
		PintsFishingDB = PintsFishingDB or {}
		db = PintsFishingDB
		for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
		PF.db = db
		if PF.OnLoad then pcall(PF.OnLoad) end
		-- settings left changed by a game crash mid-fishing get put back
		if db.savedCVars then for k, v in pairs(db.savedCVars) do pcall(SetCVar, k, v) end; db.savedCVars = nil end
	elseif e == "PLAYER_LOGIN" and GetMacroIndexByName and GetMacroIndexByName(MACRO) > 0 and not InCombatLockdown() then
		local mi = GetMacroIndexByName(MACRO)
		local _, _, body = GetMacroInfo(mi)
		if body and body:find("/click PintsFishingCast", 1, true) then
			EditMacro(mi, MACRO, "INV_Misc_Fish_02", "#showtooltip " .. FISHING .. "\n/cast [nochanneling:" .. FISHING .. "] " .. FISHING)
		end
		C_Timer.After(0.3, function() SetMode(Fishing() and "hook" or "cast") end)
	elseif e == "PLAYER_LOGIN" or e == "UPDATE_BINDINGS" or e == "ACTIONBAR_SLOT_CHANGED" or e == "UPDATE_MACROS" then
		-- (these come in bursts: look once, a moment after the last)
		if PF.soon then return end
		PF.soon = true
		C_Timer.After(0.3, function() PF.soon = nil; SetMode(Fishing() and "hook" or "cast") end)
	elseif e == "UNIT_SPELLCAST_CHANNEL_START" then
		if Fishing() then
			if db.enabled ~= false then KeepSession(); SetMode("hook") end
			if PF.OnCast then pcall(PF.OnCast) end
		end
	elseif e == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if mode == "hook" then SetMode("cast"); KeepSession() end
	elseif e == "PLAYER_REGEN_DISABLED" then
		Session(false)
	elseif e == "PLAYER_REGEN_ENABLED" then
		if PF.pending then PF.pending = nil; SetMode(Fishing() and "hook" or "cast") end
	end
end)
-- (so a crash mid-fishing doesn't leave the volume or targeting changed: remembered until the next login)
local out = CreateFrame("Frame"); out:RegisterEvent("PLAYER_LOGOUT")
out:SetScript("OnEvent", function() Session(false) end)

-- pressing the key when it isn't set up (in a fight, or before the first login finished)
function PintsFishing_Key()
	if db and db.enabled == false then Print("fishing is off - turn it on in the panel (/pfish panel).")
	elseif InCombatLockdown() then Print("can't fish in a fight.") else SetMode("cast"); Print("ready - press the key again to cast.") end
end

-- (for the fishing panel)
PF.Keys, PF.MacroKeys, PF.IsFishing, PF.HasPole = Keys, MacroKeys, Fishing, HasPole
function PF.SetEnabled(on)
	if InCombatLockdown() then Print("not in a fight."); return end
	db.enabled = on and true or false
	lastSig = nil
	if not on then Session(false) end
	SetMode((on and Fishing()) and "hook" or "cast", true)
	Print(on and "fishing on." or "fishing off - your keys work as normal.")
end

---------------------------------------------------------------- options: /pfish
local OPTS = {
	{ "doubleClick", "Double right-click to cast" },
	{ "poleOnly", "  ...only with a fishing pole equipped" },
	{ "sound", "Clearer splashes while fishing (music and ambience down)" },
	{ "softTarget", "Soft targeting while fishing (lets the key hook the bobber)" },
	{ "fastLoot", "Fast loot: take everything at once when auto loot is on" },
	{ "tracker", "Fish tracker while fishing (casts, catches, skill, lure, food)" },
	{ "lureSound", "Fanfare when a lure goes on, a sad sound when it runs out" },
}
local panel
local function Panel()
	if panel then return panel end
	panel = CreateFrame("Frame", "PintsFishingOptions", UIParent, "BackdropTemplate")
	panel:SetSize(420, 70 + #OPTS * 26 + 70); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG")
	panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	panel:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
	panel:EnableMouse(true); panel:SetMovable(true); panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving); panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PintsFishingOptions")
	local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); t:SetPoint("TOP", 0, -12); t:SetText("|cffd4a017Pint's|r Fishing")
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)
	for i, o in ipairs(OPTS) do
		local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		c:SetSize(24, 24); c:SetPoint("TOPLEFT", 16, -40 - (i - 1) * 26)
		local l = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); l:SetPoint("LEFT", c, "RIGHT", 4, 0); l:SetText(o[2])
		c:SetScript("OnShow", function(self) self:SetChecked(db[o[1]] and true or false) end)
		c:SetScript("OnClick", function(self) db[o[1]] = self:GetChecked() and true or false end)
	end
	local mb = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	mb:SetSize(200, 22); mb:SetPoint("TOPLEFT", 18, -46 - #OPTS * 26)
	mb:SetText("Get the fishing macro"); mb:SetScript("OnClick", function() PF.MakeMacro() end)
	local key = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	key:SetPoint("BOTTOMLEFT", 16, 14); key:SetWidth(390); key:SetJustifyH("LEFT")
	panel:SetScript("OnShow", function()
		local k = Keys()[1]
		key:SetText(k and ("Cast and hook: |cffffd100" .. GetBindingText(k) .. "|r   (Options > Keybindings > Pint's Fishing)")
			or "No key yet: Options > Keybindings > Pint's Fishing > Cast and hook")
	end)
	panel:Hide()
	return panel
end
SLASH_PINTSFISHING1 = "/pfish"
SLASH_PINTSFISHING2 = "/pintsfishing"
SlashCmdList.PINTSFISHING = function(msg)
	if (msg or ""):lower():match("minimap") and PF.ToggleMinimap then PF.ToggleMinimap(); return end
	if (msg or ""):lower():match("panel") and PF.TogglePanel then PF.TogglePanel(); return end
	if (msg or ""):lower():match("macro") then PF.MakeMacro(); return end
	if (msg or ""):lower():match("where") and PF.ToggleWhere then PF.ToggleWhere((msg:lower():match("gold") and "gold") or "skill"); return end
	if (msg or ""):lower():match("cook") and PF.ToggleCook then PF.ToggleCook(); return end
	if (msg or ""):lower():match("reset") and PF.ResetSession then PF.ResetSession(); Print("session tracker started over."); return end
	if (msg or ""):lower():match("track") and PF.ToggleTracker then PF.ToggleTracker(); return end
	if (msg or ""):lower():match("diag") then
		local mi = GetMacroIndexByName(MACRO)
		local body = mi > 0 and GetMacroBody(mi) or "(no macro)"
		Print("macro #" .. mi .. ": " .. tostring(body):gsub("\n", " | "))
		local slots = {}
		for slot = 1, 180 do if PF.IsOurs(slot, mi) then slots[#slots + 1] = slot end end
		Print("on action slots: " .. (#slots > 0 and table.concat(slots, ", ") or "none"))
		Print("keys it fishes with: " .. table.concat(MacroKeys(), ", ") .. "   Pint's Fishing key: " .. table.concat(Keys(), ", ") .. "   mode: " .. tostring(mode))
		local ok, r = pcall(SecureCmdOptionParse, "[nochanneling:" .. FISHING .. "] " .. FISHING)
		Print("the macro would cast: " .. tostring(ok and r) .. "   (Fishing is called '" .. FISHING .. "')")
		return
	end
	local p = Panel()
	if p:IsShown() then p:Hide() else p:Show() end
end
