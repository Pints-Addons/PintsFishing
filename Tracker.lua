-- Pint's Fishing: the fish tracker, laid out like FisherMate. A small panel while you fish: total and session casts and
-- catches (with the catch rate), catches and gold per hour, estimated gold made, your Fishing skill, lure and food.
-- Its title is a drop-down for what the totals cover; "Expanded View" lists every catch with its price.
--   It shows while you fish and hides a minute after you stop. /pfish tracker shows or hides it by hand.
local PF = _G.PintsFishing
if not PF then return end

-- (WoW Forever has no plain GetItemInfo any more - the C_Item one first)
local GII = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

local function Spot()
	local zone = GetRealZoneText() or "?"
	local sub = GetSubZoneText()
	return (sub and sub ~= "" and sub ~= zone) and (zone .. " - " .. sub) or zone
end
-- your Fishing skill: (rank, max, bonus) - from the professions list on newer clients, the skills list on Classic. The
-- bonus is everything on top of your rank right now: lure, pole, gear and buffs
local function Num(v) if type(issecretvalue) == "function" and issecretvalue(v) then return 0 end return tonumber(v) or 0 end
local function Skill()
	if GetProfessions and GetProfessionInfo then
		local _, _, _, fish = GetProfessions()
		if fish then local _, _, rank, max, _, _, _, mod = GetProfessionInfo(fish); return rank, max, Num(mod) end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank, temp, mod, max = GetSkillLineInfo(i)
			if not header and name == PF.FISHING then return rank, max, Num(mod) + Num(temp) end
		end
	end
end

-- this session: every spot fished, each with its own casts, catches and items
local S = { spots = {}, startSkill = nil, started = nil, last = 0 }
local CHAR = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
local ME = UnitName("player") or "?"
-- what the totals cover: here or every water, this character or all of them (the session is always this character)
local VIEWS = {
	{ "here_char", "Here - %s" }, { "char", "All waters - %s" },
	{ "here_all", "Here - all characters" }, { "all", "All waters - all characters" },
}
local view = 1
local db

---------------------------------------------------------------- prices
-- what a catch is worth: Pint's Auctions' latest auction price when it has one, else what a vendor pays
local function Price(id)
	local PA = _G.PintsAuctions
	if PA and PA.Price then
		local ok, m = pcall(PA.Price, id)
		if ok and type(m) == "number" and m > 0 then return m, "ah" end
	end
	local sell = select(11, GII(id))
	if sell and sell > 0 then return sell, "vendor" end
	return 0
end
local function Money(c)
	c = math.floor(c or 0)
	local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	local out = {}
	if g > 0 then out[#out + 1] = "|cffffffff" .. g .. "|r|cffffd700g|r" end
	if g > 0 or sv > 0 then out[#out + 1] = "|cffffffff" .. sv .. "|r|cffc7c7cfs|r" end
	out[#out + 1] = "|cffffffff" .. cp .. "|r|cffeda55fc|r"
	return table.concat(out, " ")
end
-- (shared with the Where to Fish and Cook windows)
PF.Price, PF.Money, PF.Skill = Price, Money, Skill
-- your own seconds per cast this session (14 until there's enough to go on)
function PF.SecPerCast()
	local n = 0
	for _, sp in pairs(S.spots) do n = n + (sp.casts or 0) end
	if S.started and n >= 5 then return math.max(6, (GetTime() - S.started) / n) end
	return 14
end
function PF.CharSpots() return db and db.chars and db.chars[CHAR] and db.chars[CHAR].spots or {} end
local function Clock(sec)
	sec = math.floor(sec or 0)
	local h, m, sc = math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, sc) end
	return ("%d:%02d"):format(m, sc)
end

---------------------------------------------------------------- adding up
-- every spot record the view covers: lifetime (this character or all) and this session, here or everywhere
local function Sources()
	local here = Spot()
	local key = VIEWS[view][1]
	local life, sess = {}, {}
	local onlyHere = key:find("^here") ~= nil
	local chars = {}
	if key:find("char$") then chars[1] = CHAR else for c in pairs(db and db.chars or {}) do chars[#chars + 1] = c end end
	for _, c in ipairs(chars) do
		local spots = db.chars[c] and db.chars[c].spots or {}
		if onlyHere then life[#life + 1] = spots[here] else for _, sp in pairs(spots) do life[#life + 1] = sp end end
	end
	if onlyHere then sess[1] = S.spots[here] else for _, sp in pairs(S.spots) do sess[#sess + 1] = sp end end
	return life, sess, here, onlyHere
end
local function Sum(list)
	local casts, catches, items, byId = 0, 0, 0, {}
	for _, sp in pairs(list) do
		casts = casts + (sp.casts or 0)
		local n = 0
		for id, e in pairs(sp.items or {}) do byId[id] = (byId[id] or 0) + e.n; n = n + e.n end
		items = items + n
		-- (catches are counted from 1.0 on; older records only know the items - one item a catch, near enough)
		catches = catches + (sp.catches or math.min(n, sp.casts or n))
	end
	return casts, catches, items, byId
end
local function Worth(byId)
	local g = 0
	for id, n in pairs(byId) do if not (db.exclude and db.exclude[id]) then g = g + n * Price(id) end end
	return g
end
local function Pct(a, b) return b > 0 and ("%.1f%%"):format(a / b * 100) or "-" end

---------------------------------------------------------------- the panel
local f = CreateFrame("Frame", "PintsFishingTracker", UIParent, "BackdropTemplate")
f:SetSize(300, 100); f:SetPoint("CENTER", UIParent, "CENTER", 300, 120)
f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
f:SetBackdropColor(0.05, 0.15, 0.17, 0.92)
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	if db then local p, _, rp, x, y = self:GetPoint(1); db.trackerPos = { p, rp, x, y } end
end)
f:Hide()
local title = CreateFrame("Button", nil, f)
title:SetPoint("TOP", 0, -14); title:SetHeight(22); title:SetWidth(270)
title.t = title:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title.t:SetPoint("CENTER"); title.t:SetWordWrap(false)
local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); sub:SetPoint("TOP", title, "BOTTOM", 0, -1)
title:RegisterForClicks("LeftButtonUp")
-- what the totals cover: a little drop-down under the title
local menu = CreateFrame("Frame", "PintsFishingTrackerMenu", f, "BackdropTemplate")
menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
menu:SetBackdropColor(0.02, 0.04, 0.08, 0.97); menu:SetBackdropBorderColor(0.4, 0.6, 0.8, 1)
menu:SetFrameStrata("DIALOG"); menu:SetSize(280, #VIEWS * 22 + 12); menu:Hide()
menu:SetPoint("TOP", title, "BOTTOM", 0, -2)
menu.items = {}
for i in ipairs(VIEWS) do
	local b = CreateFrame("Button", nil, menu)
	b:SetSize(268, 22); b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 22)
	b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); b.t:SetPoint("LEFT", 6, 0); b.t:SetJustifyH("LEFT")
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	b:SetScript("OnClick", function()
		view = i
		if db then db.trackerVue = view end
		menu:Hide(); PF.DrawTracker()
	end)
	menu.items[i] = b
end
menu:SetScript("OnShow", function(self)
	for i, b in ipairs(self.items) do b.t:SetText((i == view and "|cffffd100" or "|cffffffff") .. VIEWS[i][2]:format(ME) .. "|r") end
end)
title:SetScript("OnClick", function() if menu:IsShown() then menu:Hide() else menu:Show() end end)
f:HookScript("OnHide", function() menu:Hide(); if not InCombatLockdown() then _G.PintsFishingLure:Hide() end end)
title:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine("Pint's Fishing")
	GameTooltip:AddLine("Click: what the totals cover (here or all waters, this character or all)", 1, 1, 1, true)
	GameTooltip:AddLine("Drag the panel to move it", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
title:SetScript("OnLeave", function() GameTooltip:Hide() end)
-- the figures: a label on the left, the number on the right of it (FisherMate's layout)
local lines = {}
local function Line(i)
	local l = lines[i]
	if l then return l end
	l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); l:SetJustifyH("LEFT")
	l:SetPoint("TOPLEFT", 18, -52 - (i - 1) * 20)
	lines[i] = l
	return l
end
local life = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate"); life:SetSize(22, 22)
life.t = life:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); life.t:SetPoint("LEFT", life, "RIGHT", 2, 0); life.t:SetText("Lifetime")
life:SetScript("OnClick", function(self) db.goldLifetime = self:GetChecked() and true or false; PF.DrawTracker() end)
life:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Gold made: everything caught (on) or this session (off)", 1, 1, 1, true); GameTooltip:Show() end)
life:SetScript("OnLeave", function() GameTooltip:Hide() end)
local expand = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); expand:SetSize(110, 22); expand:SetText("Expanded View")
expand:SetScript("OnClick", function() if PF.ToggleDetails then PF.ToggleDetails() end end)
local whereB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); whereB:SetSize(90, 22); whereB:SetText("Where to Fish")
whereB:SetScript("OnClick", function() if PF.ToggleWhere then PF.ToggleWhere() end end)
local cookB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); cookB:SetSize(60, 22); cookB:SetText("Cook")
cookB:SetScript("OnClick", function() if PF.ToggleCook then PF.ToggleCook() end end)

local G = "|cff40ff40%s|r"

-- Apply lure: a button on the panel's corner when your pole has no lure (or it's running out) - the best lure in your
-- bags goes on the pole. (A secure button of its own: using an item on your pole needs one.)
local LURES = { { 6533, 100 }, { 7307, 75 }, { 6532, 75 }, { 6811, 50 }, { 6530, 50 }, { 6529, 25 } }   -- id, bonus; best first
local lb = CreateFrame("Button", "PintsFishingLure", UIParent, "SecureActionButtonTemplate")
lb:SetSize(36, 36); lb:RegisterForClicks("AnyUp"); lb:Hide()
lb.icon = lb:CreateTexture(nil, "ARTWORK"); lb.icon:SetAllPoints()
lb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
lb.glow = lb:CreateTexture(nil, "OVERLAY"); lb.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); lb.glow:SetBlendMode("ADD")
lb.glow:SetSize(66, 66); lb.glow:SetPoint("CENTER")
lb:SetScript("OnEnter", function(self) if self.item then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.item); GameTooltip:AddLine("Click: put it on your pole", 0.4, 1, 0.4); GameTooltip:Show() end end)
lb:SetScript("OnLeave", function() GameTooltip:Hide() end)
local function BestLure()
	local count = (C_Item and C_Item.GetItemCount) or GetItemCount
	for _, l in ipairs(LURES) do if count(l[1]) > 0 then return l[1], l[2] end end
end
function PF.PlaceLureButton(lure)
	if InCombatLockdown() then return end
	local want = f:IsShown() and (lure == false or (lure and lure < 60))
	local id = want and BestLure()
	if not id then lb:Hide(); return end
	if lb.item ~= id then
		lb.item = id
		lb:SetAttribute("type", "macro")
		lb:SetAttribute("macrotext", "/use item:" .. id .. "\n/use 16")
		lb.icon:SetTexture((GIcon and GIcon(id)) or 134400)
	end
	lb:ClearAllPoints(); lb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -46)
	lb:Show()
end
-- a warning a minute before the lure runs out (once per lure)
local warned
local function LureWarn(lure)
	if lure and lure < 60 and lure > 0 then
		if not warned then warned = true; if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, "Your lure runs out in a minute", ChatTypeInfo["RAID_WARNING"]) end end
	else warned = nil end
end
PF.LureWarn = LureWarn
function PF.DrawTracker()
	if PF.DrawDetails then PF.DrawDetails() end
	if not f:IsShown() then return end
	local lifeL, sessL, here, onlyHere = Sources()
	local lc, lk, lItems, lById = Sum(lifeL)
	local sc, sk, _, sById = Sum(sessL)
	title.t:SetText((onlyHere and here or "All waters") .. " |cffffd100v|r")
	sub:SetText(VIEWS[view][2]:format(ME))
	local hours = S.started and math.max((GetTime() - S.started) / 3600, 1 / 60) or nil
	local goldLife = db.goldLifetime
	local gold = goldLife and Worth(lById) or Worth(sById)
	local t = {}
	t[#t + 1] = "Total # casts: " .. G:format(lc)
	t[#t + 1] = "Total fish caught: " .. G:format(lk) .. " (" .. G:format(Pct(lk, lc)) .. ")"
	t[#t + 1] = "Casts this session: " .. G:format(sc)
	t[#t + 1] = "Catches this session: " .. G:format(sk) .. " (" .. G:format(Pct(sk, sc)) .. ")"
	-- (a cast that brought nothing up: it got away, or the bobber timed out)
	if sc > sk then t[#t + 1] = "Missed this session: |cffff8040" .. (sc - sk) .. "|r" end
	t[#t + 1] = "Catches per hour: " .. G:format(hours and ("%.1f"):format(sk / hours) or "-")
	t[#t + 1] = "Est. gold made: " .. Money(gold)
	local goldRow = #t
	t[#t + 1] = "Gold per hour: " .. (hours and Money(Worth(sById) / hours) or "-")
	local rank, max, bonus = Skill()
	if rank then
		local gained = (S.startSkill and rank > S.startSkill) and ("  |cff40ff40+" .. (rank - S.startSkill) .. "|r") or ""
		local all = (bonus and bonus > 0) and ("  (|cff40ff40%d|r with buffs)"):format(rank + bonus) or ""
		t[#t + 1] = ("Fishing: |cff40ff40%d|r/%d%s%s"):format(rank, max or 0, gained, all)
	end
	if S.started then t[#t + 1] = "Session time: " .. G:format(Clock(GetTime() - S.started)) end
	local lure = PF.LureLeft()
	LureWarn(lure)
	if lure == false then t[#t + 1] = "Lure: |cffff4040none|r"
	elseif lure then t[#t + 1] = "Lure: " .. G:format(Clock(lure)) .. (lure < 60 and " |cffff8040(running out)|r" or "") end
	local food = PF.FoodLeft()
	if food == false then t[#t + 1] = "Food: |cffff4040no Well Fed|r"
	elseif food then t[#t + 1] = "Food: " .. G:format(food > 0 and Clock(food) or "on") end
	-- bag space: a catch with nowhere to go is lost
	local free = 0
	local C = C_Container or {}
	for bag = 0, 4 do
		local n, fam = (C.GetContainerNumFreeSlots or GetContainerNumFreeSlots)(bag)
		if (fam or 0) == 0 then free = free + (n or 0) end
	end
	if free <= 4 then t[#t + 1] = "Bags: " .. (free == 0 and "|cffff4040full - catches will be lost|r" or ("|cffff8040" .. free .. " free|r")) end
	-- the running count of each fish: this session / every catch the view covers (and its share of them)
	local ids = {}
	for id in pairs(lById) do ids[#ids + 1] = id end
	for id in pairs(sById) do if not lById[id] then ids[#ids + 1] = id end end
	table.sort(ids, function(a, b)
		local x, y = sById[a] or 0, sById[b] or 0
		if x ~= y then return x > y end
		x, y = lById[a] or 0, lById[b] or 0
		if x ~= y then return x > y end
		return a < b
	end)
	if #ids > 0 then
		t[#t + 1] = "|cffffd100Fish|r  |cff999999this session / total (share)|r"
		for i = 1, math.min(#ids, 12) do
			local id = ids[i]
			local name, _, q = GII(id)
			local col = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
			local cname = (col and col.r) and ("|cff%02x%02x%02x%s|r"):format(col.r * 255, col.g * 255, col.b * 255, name or ("item " .. id)) or (name or ("item " .. id))
			local icon = (GIcon and GIcon(id)) or 134400
			t[#t + 1] = ("|T%s:16|t %s: %s / %s (%s)"):format(icon, cname, G:format(sById[id] or 0), G:format(lById[id] or 0), Pct(lById[id] or 0, lItems))
		end
		if #ids > 12 then t[#t + 1] = ("|cff999999...and %d more - Expanded View|r"):format(#ids - 12) end
	end
	PF.PlaceLureButton(lure)
	local widest = 0
	for i, txt in ipairs(t) do
		local l = Line(i); l:SetText(txt); l:Show()
		local w = l.GetUnboundedStringWidth and l:GetUnboundedStringWidth() or l:GetStringWidth()
		if i == goldRow then w = w + 90 end
		widest = math.max(widest, w)
	end
	for i = #t + 1, #lines do lines[i]:Hide() end
	life:ClearAllPoints(); life:SetPoint("LEFT", lines[goldRow], "RIGHT", 10, 0); life:SetChecked(goldLife and true or false)
	local tw = title.t.GetUnboundedStringWidth and title.t:GetUnboundedStringWidth() or title.t:GetStringWidth()
	local w = math.max(300, math.ceil(math.max(widest + 36, tw + 40)))
	f:SetWidth(w); title:SetWidth(w - 30); menu:SetWidth(math.min(w - 20, 300))
	expand:ClearAllPoints(); expand:SetPoint("TOP", lines[#t], "BOTTOM", 0, -12); expand:SetPoint("LEFT", f, "CENTER", -132, 0)
	whereB:ClearAllPoints(); whereB:SetPoint("LEFT", expand, "RIGHT", 4, 0)
	cookB:ClearAllPoints(); cookB:SetPoint("LEFT", whereB, "RIGHT", 4, 0)
	f:SetHeight(52 + #t * 20 + 12 + 22 + 16)
end

---------------------------------------------------------------- expanded view: every catch, lifetime and this session
local d = CreateFrame("Frame", "PintsFishingDetails", UIParent, "BackdropTemplate")
d:SetSize(640, 420); d:SetPoint("CENTER")
d:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
d:SetBackdropColor(0.05, 0.15, 0.17, 0.95)
d:SetMovable(true); d:EnableMouse(true); d:RegisterForDrag("LeftButton"); d:SetClampedToScreen(true); d:SetFrameStrata("HIGH")
d:SetScript("OnDragStart", d.StartMoving); d:SetScript("OnDragStop", d.StopMovingOrSizing)
d:Hide()
tinsert(UISpecialFrames, "PintsFishingDetails")
local dt = d:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); dt:SetPoint("TOP", 0, -16); dt:SetText("Lifetime Fishing Details")
local ds = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ds:SetPoint("TOP", dt, "BOTTOM", 0, -2)
local dclose = CreateFrame("Button", nil, d, "UIPanelCloseButton"); dclose:SetPoint("TOPRIGHT", -4, -4)
local COLS = { { "Fish", 16 }, { "Lifetime", 300 }, { "This Session", 380 }, { "Price", 470 }, { "Exclude?", 545 } }
for _, c in ipairs(COLS) do
	local h = d:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", c[2] + 8, -62); h:SetText(c[1])
end
local sf = CreateFrame("ScrollFrame", "PintsFishingDetailsScroll", d, "UIPanelScrollFrameTemplate")
sf:SetPoint("TOPLEFT", 14, -82); sf:SetPoint("BOTTOMRIGHT", -34, 16)
local content = CreateFrame("Frame", nil, sf); content:SetSize(590, 1); sf:SetScrollChild(content)
local drows = {}
local DROW = 26
local function DRow(i)
	local r = drows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, content); r:SetSize(590, DROW); r:SetPoint("TOPLEFT", 0, -(i - 1) * DROW)
	r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0.08)
	r.del = CreateFrame("Button", nil, r); r.del:SetSize(16, 16); r.del:SetPoint("LEFT", 4, 0)
	r.del:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up"); r.del:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
	r.del:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Delete this row"); GameTooltip:AddLine("Takes it out of the records these totals cover", 1, 1, 1, true); GameTooltip:Show() end)
	r.del:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 26, 0)
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetWidth(240); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
	r.life = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.life:SetPoint("LEFT", 300, 0)
	r.sess = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.sess:SetPoint("LEFT", 380, 0)
	r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.price:SetPoint("RIGHT", r, "LEFT", 535, 0); r.price:SetJustifyH("RIGHT")
	r.ex = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate"); r.ex:SetSize(24, 24); r.ex:SetPoint("LEFT", 560, 0)
	local hov = CreateFrame("Frame", nil, r); hov:SetPoint("TOPLEFT", 24, 0); hov:SetSize(260, DROW)
	hov:SetScript("OnEnter", function() if r.id then GameTooltip:SetOwner(r, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(r.id); GameTooltip:Show() end end)
	hov:SetScript("OnLeave", function() GameTooltip:Hide() end)
	drows[i] = r
	return r
end
function PF.DrawDetails()
	if not d:IsShown() or not db then return end
	local lifeL, sessL, here, onlyHere = Sources()
	local _, _, _, lById = Sum(lifeL)
	local _, _, _, sById = Sum(sessL)
	ds:SetText((onlyHere and here or "All waters") .. "  -  " .. VIEWS[view][2]:format(ME))
	local ids = {}
	for id in pairs(lById) do ids[#ids + 1] = id end
	for id in pairs(sById) do if not lById[id] then ids[#ids + 1] = id end end
	table.sort(ids, function(a, b) local x, y = lById[a] or 0, lById[b] or 0; if x ~= y then return x > y end return a < b end)
	for i, id in ipairs(ids) do
		local r = DRow(i)
		r.id = id
		local name, _, q = GII(id)
		local col = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
		r.icon:SetTexture((GIcon and GIcon(id)) or 134400)
		r.name:SetText(name or ("item " .. id))
		if col and col.r then r.name:SetTextColor(col.r, col.g, col.b) else r.name:SetTextColor(1, 1, 1) end
		r.life:SetText(G:format(lById[id] or 0)); r.sess:SetText(G:format(sById[id] or 0))
		local p, src = Price(id)
		r.price:SetText(p > 0 and (Money(p) .. (src == "vendor" and " |cff888888v|r" or "")) or "|cff888888-|r")
		r.ex:SetChecked(db.exclude and db.exclude[id] and true or false)
		r.ex:SetScript("OnClick", function(self) db.exclude = db.exclude or {}; db.exclude[id] = self:GetChecked() and true or nil; PF.DrawTracker() end)
		r.del:SetScript("OnClick", function()
			for _, sp in ipairs(lifeL) do if sp.items then sp.items[id] = nil end end
			for _, sp in ipairs(sessL) do if sp.items then sp.items[id] = nil end end
			PF.DrawTracker()
		end)
		r:Show()
	end
	for i = #ids + 1, #drows do drows[i]:Hide() end
	content:SetHeight(math.max(1, #ids * DROW))
end
d:SetScript("OnShow", function() PF.DrawDetails() end)
function PF.ToggleDetails() if d:IsShown() then d:Hide() else d:Show() end end

---------------------------------------------------------------- what happens
local function Showing() return db and db.tracker ~= false end
local hideTimer
-- (the tracker can't come or go during a fight - the lure button hangs off it - so a hide waits for the fight to end)
local function SafeHide() if InCombatLockdown() then PF.hideLater = true else PF.hideLater = nil; f:Hide() end end
local function KeepUp()
	if not Showing() then return end
	if not f:IsShown() then if InCombatLockdown() then return end; f:Show() end
	if hideTimer then hideTimer:Cancel() end
	-- (a minute after the last cast, unless you put it up by hand)
	hideTimer = C_Timer.NewTimer(60, function() hideTimer = nil; if not PF.trackerPinned then SafeHide() end end)
	PF.DrawTracker()
end
---------------------------------------------------------------- lure and food
local function HasPole()
	local link = GetInventoryItemLink("player", 16)
	if not link then return false end
	local GIII = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local _, _, _, _, _, classID, subID = GIII(link)
	return classID == 2 and subID == 20
end
-- seconds of lure left on the pole; false = no lure; nil = no pole in hand (nothing to say)
function PF.LureLeft()
	if not HasPole() or not GetWeaponEnchantInfo then return nil end
	local has, ms = GetWeaponEnchantInfo()
	if issecretvalue and (issecretvalue(has) or issecretvalue(ms)) then return nil end
	if not has then return false end
	return (ms or 0) / 1000
end
-- seconds of Well Fed left; 0 = on (time unknown); false = none; nil = can't tell
local WELL_FED = (GetSpellInfo and GetSpellInfo(19705)) or (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(19705) and C_Spell.GetSpellInfo(19705).name) or "Well Fed"
function PF.FoodLeft()
	local A = C_UnitAuras
	if A and A.GetAuraDataBySpellName then
		local ok, d = pcall(A.GetAuraDataBySpellName, "player", WELL_FED, "HELPFUL")
		if not ok or (d and issecretvalue and issecretvalue(d)) then return nil end
		if not d then return false end
		local exp = d.expirationTime
		if issecretvalue and issecretvalue(exp) then return 0 end
		return (exp and exp > 0) and math.max(0, exp - GetTime()) or 0
	end
	if UnitBuff then
		for i = 1, 40 do
			local name, _, _, _, _, exp = UnitBuff("player", i)
			if not name then return false end
			if name == WELL_FED then return (exp and exp > 0) and math.max(0, exp - GetTime()) or 0 end
		end
		return false
	end
end
-- a fanfare when a lure goes on, a sad sound when it runs out (only with the pole in hand)
local lureWas
local function Sound(id) if id then pcall(PlaySound, id, "Master") end end
local lureTick = CreateFrame("Frame")
local lacc = 0
lureTick:SetScript("OnUpdate", function(_, el)
	lacc = lacc + el
	if lacc < 1 then return end
	lacc = 0
	local l = PF.LureLeft()
	if l == nil then lureWas = nil; return end              -- (no pole: forget it, so swapping back in makes no noise)
	local on = l and true or false
	if lureWas ~= nil and on ~= lureWas and db and db.lureSound ~= false then
		if on then Sound(SOUNDKIT and SOUNDKIT.LEVEL_UP or 888)                         -- conquering: the level-up fanfare
		else Sound(SOUNDKIT and SOUNDKIT.IG_QUEST_FAILED or 847) end                    -- defeat: the quest-failed sound
	end
	lureWas = on
end)

function PF.OnLoad()
	db = PF.db
	-- catches are kept per character, per spot (the first version kept one list for everyone: it goes to whoever logs
	-- in first, which is the character who fished it)
	db.chars = db.chars or {}
	db.chars[CHAR] = db.chars[CHAR] or { spots = {} }
	if db.spots then
		local mine = db.chars[CHAR].spots
		for k, v in pairs(db.spots) do if not mine[k] then mine[k] = v end end
		db.spots = nil
	end
	view = db.trackerVue or 1
	if not VIEWS[view] then view = 1 end
	local p = db.trackerPos
	if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
end
function PF.OnCast()
	if not S.started then S.started = GetTime(); S.startSkill = Skill() end
	S.last = GetTime()
	local here = Spot()
	S.spots[here] = S.spots[here] or { casts = 0, items = {} }
	S.spots[here].casts = S.spots[here].casts + 1
	local mine = db.chars[CHAR].spots
	mine[here] = mine[here] or { casts = 0, items = {} }
	mine[here].casts = mine[here].casts + 1
	KeepUp()
end
function PF.OnCatch(got)
	if not db then return end
	local here = Spot()
	S.spots[here] = S.spots[here] or { casts = 0, items = {} }
	local mine = db.chars[CHAR].spots
	mine[here] = mine[here] or { casts = 0, items = {} }
	for _, sp in ipairs({ S.spots[here], mine[here] }) do sp.catches = (sp.catches or 0) + 1 end
	for _, g in ipairs(got) do
		if g.id then
			for _, sp in ipairs({ S.spots[here], mine[here] }) do
				local e = sp.items[g.id] or { name = g.name, n = 0 }
				e.n = e.n + g.n; e.name = e.name or g.name
				sp.items[g.id] = e
			end
		end
	end
	KeepUp()
end
-- skill-ups and the clock
local tick = CreateFrame("Frame")
tick:RegisterEvent("SKILL_LINES_CHANGED"); tick:RegisterEvent("ZONE_CHANGED"); tick:RegisterEvent("ZONE_CHANGED_NEW_AREA")
tick:RegisterEvent("PLAYER_REGEN_DISABLED"); tick:RegisterEvent("PLAYER_REGEN_ENABLED"); tick:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
tick:SetScript("OnEvent", function(_, e, slot)
	if e == "PLAYER_REGEN_DISABLED" then if not PF.trackerPinned then SafeHide() end; return end
	if e == "PLAYER_REGEN_ENABLED" then if PF.hideLater and not PF.trackerPinned then SafeHide() end; PF.hideLater = nil; return end
	-- (the pole comes off: the panel goes, unless you put it up by hand)
	if e == "PLAYER_EQUIPMENT_CHANGED" then
		if slot == 16 and not HasPole() and not PF.trackerPinned then
			if hideTimer then hideTimer:Cancel(); hideTimer = nil end
			SafeHide()
		end
		return
	end
	PF.DrawTracker()
end)
local acc = 0
f:SetScript("OnUpdate", function(_, el) acc = acc + el; if acc >= 1 then acc = 0; PF.DrawTracker() end end)

-- (for the fishing panel) this session: casts, catches, junk items, what it's worth, when it started, skill then
function PF.SessionStats()
	local casts, catches, junk, byId = 0, 0, 0, {}
	for _, sp in pairs(S.spots) do
		casts = casts + (sp.casts or 0); catches = catches + (sp.catches or 0)
		for id, e in pairs(sp.items or {}) do
			byId[id] = (byId[id] or 0) + e.n
			if select(3, GII(id)) == 0 then junk = junk + e.n end
		end
	end
	return casts, catches, junk, db and Worth(byId) or 0, S.started, S.startSkill
end
-- this character's lifetime casts and catches where you're standing
function PF.SpotStats()
	local here = Spot()
	local sp = db and db.chars and db.chars[CHAR] and db.chars[CHAR].spots[here]
	return sp and sp.casts or 0, sp and (sp.catches or 0) or 0, here
end
function PF.ToggleTracker()
	if InCombatLockdown() then print("|cff33ccffPint's Fishing:|r the tracker can't open or close during a fight."); return end
	if f:IsShown() then f:Hide(); PF.trackerPinned = nil
	else PF.trackerPinned = true; f:Show(); PF.DrawTracker() end
end
-- /pfish tracker reset: start the session over
function PF.ResetSession() S = { spots = {}, last = 0 }; PF.DrawTracker() end
