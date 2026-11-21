-- Pint's Fishing: Cook. Every fish in your bags that cooks into something: what it makes, and what each way of
-- getting rid of it is worth - selling it raw or cooked, at the auction house (Pint's Auctions' prices) or to a
-- vendor - with the best one picked out. Cook all of it with one button (your Cooking window has to be open: the
-- game only cooks from there), light a Basic Campfire, or open Cooking.
local PF = _G.PintsFishing
if not PF then return end
local GII = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local Count = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetSpellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo

-- raw fish -> what it cooks into (one each)
local COOKS = {
	[6291] = 6290, [6303] = 787, [6289] = 4592, [6317] = 6316, [6361] = 5095, [6308] = 4593, [6362] = 4594,
	[8365] = 8364, [4603] = 6887, [13754] = 13927, [13758] = 13930, [13759] = 13931, [13760] = 13932,
	[13889] = 13935, [13888] = 13933, [13893] = 13934, [6522] = 6657, [21071] = 21072, [21153] = 21217,
}

---------------------------------------------------------------- the window
local w = CreateFrame("Frame", "PintsFishingCook", UIParent, "BackdropTemplate")
w:SetSize(560, 300); w:SetPoint("CENTER", 0, 60)
w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
w:SetBackdropColor(0.05, 0.15, 0.17, 0.95)
w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton"); w:SetClampedToScreen(true); w:SetFrameStrata("HIGH")
w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
w:Hide()
tinsert(UISpecialFrames, "PintsFishingCook")
local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -16); title:SetText("Cook: what to make from your catch")
local close = CreateFrame("Button", nil, w, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
local status = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); status:SetPoint("TOPLEFT", 22, -42); status:SetWidth(516); status:SetJustifyH("LEFT")
local rows = {}
local ROW = 46
local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, w); r:SetSize(516, ROW); r:SetPoint("TOPLEFT", 22, -66 - (i - 1) * ROW)
	r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(30, 30); r.icon:SetPoint("TOPLEFT", 0, -2)
	r.top = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.top:SetPoint("TOPLEFT", 38, -2); r.top:SetWidth(360); r.top:SetJustifyH("LEFT"); r.top:SetWordWrap(false)
	r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.sub:SetPoint("TOPLEFT", 38, -20); r.sub:SetWidth(380); r.sub:SetJustifyH("LEFT")
	r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.btn:SetSize(96, 22); r.btn:SetPoint("TOPRIGHT", 0, -4)
	rows[i] = r
	return r
end
-- Open Cooking and Campfire cast spells, so they're secure buttons (set up once, never changed in a fight)
local function SpellButton(text, spellID, x)
	local b = CreateFrame("Button", nil, w, "SecureActionButtonTemplate,UIPanelButtonTemplate")
	b:SetSize(150, 22); b:SetPoint("BOTTOM", x, 16); b:SetText(text)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("type", "spell"); b:SetAttribute("spell", GetSpellName(spellID) or text)
	return b
end
SpellButton("Open Cooking", 2550, -160)
SpellButton("Campfire", 818, 0)
local ah = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); ah:SetSize(150, 22); ah:SetPoint("BOTTOM", 160, 16); ah:SetText("Prices (AH)")
ah:SetScript("OnClick", function()
	if _G.PintsAuctions and AuctionFrame and AuctionFrame:IsShown() then print("|cffd4a017Pint's Fishing:|r scan the auction house with Pint's Auctions' scan button.")
	else UIErrorsFrame:AddMessage("Open the auction house to scan prices with Pint's Auctions", 1, 0.8, 0.2) end
end)

---------------------------------------------------------------- cooking from the open Cooking window
-- the recipe in the open Cooking window that makes this item; and whether that window is Cooking at all
local COOKING = GetSpellName(2550) or "Cooking"
local function CookingOpen()
	if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
		local info = C_TradeSkillUI.GetBaseProfessionInfo()
		return info and info.professionName == COOKING
	end
	if GetTradeSkillLine then return GetTradeSkillLine() == COOKING end
end
local function FindRecipe(cookedID)
	local want = GII(cookedID)
	if not want then return end
	if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
		for _, rid in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
			local info = C_TradeSkillUI.GetRecipeInfo(rid)
			if info and info.learned and info.name == want then return rid end
		end
	elseif GetNumTradeSkills then
		for i = 1, GetNumTradeSkills() do
			local name, kind = GetTradeSkillInfo(i)
			if kind ~= "header" and name == want then return i end
		end
	end
end
local function Cook(cookedID, n)
	if not CookingOpen() then UIErrorsFrame:AddMessage("Open your Cooking window first (stand by a fire)", 1, 0.3, 0.3); return end
	local r = FindRecipe(cookedID)
	if not r then UIErrorsFrame:AddMessage("You don't know that recipe", 1, 0.3, 0.3); return end
	if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then C_TradeSkillUI.CraftRecipe(r, n)
	elseif DoTradeSkill then DoTradeSkill(r, n) end
end

---------------------------------------------------------------- what each fish is worth, and the best way
local function Ways(raw, cooked)
	local PA = _G.PintsAuctions
	local function AH(id) if PA and PA.Price then local ok, m = pcall(PA.Price, id); if ok and type(m) == "number" and m > 0 then return m end end end
	local function Vendor(id) local v = select(11, GII(id)); return (v and v > 0) and v or nil end
	return {
		{ "Sell raw at the AH", AH(raw) }, { "Sell raw to a vendor", Vendor(raw) },
		{ "Cook, sell at the AH", AH(cooked) }, { "Cook, sell to a vendor", Vendor(cooked) },
	}
end
function PF.DrawCook()
	if not w:IsShown() then return end
	local rank, max
	if GetProfessions and GetProfessionInfo then
		local _, _, _, _, cook = GetProfessions()
		if cook then local _, _, r, m = GetProfessionInfo(cook); rank, max = r, m end
	elseif GetNumSkillLines then
		for i = 1, GetNumSkillLines() do local n, h, _, r, _, _, m = GetSkillLineInfo(i); if not h and n == COOKING then rank, max = r, m end end
	end
	status:SetText(("Cooking: %s/%s.  %s"):format(rank or "?", max or "?", CookingOpen() and "|cff40ff40Cooking window open - Cook buttons work.|r"
		or "|cffffd100Cook buttons need your Cooking window open (by a fire): Campfire, then Open Cooking.|r"))
	local list = {}
	for raw, cooked in pairs(COOKS) do
		local n = Count(raw)
		if n and n > 0 then list[#list + 1] = { raw = raw, cooked = cooked, n = n } end
	end
	table.sort(list, function(a, b) return a.n > b.n end)
	for i, e in ipairs(list) do
		local r = Row(i)
		local rn, cn = GII(e.raw) or ("item " .. e.raw), GII(e.cooked) or ("item " .. e.cooked)
		r.icon:SetTexture((GIcon and GIcon(e.raw)) or 134400)
		r.top:SetText(("[%s] x%d  ->  [%s]"):format(rn, e.n, cn))
		local ways, best, bestV = Ways(e.raw, e.cooked), nil, 0
		local bits = {}
		for _, wv in ipairs(ways) do
			if wv[2] then
				bits[#bits + 1] = wv[1]:gsub("^Sell ", ""):gsub("^Cook, sell ", "cooked "):gsub(" at the AH", " AH"):gsub(" to a vendor", " vendor") .. " " .. PF.Money(wv[2])
				if wv[2] > bestV then best, bestV = wv[1], wv[2] end
			end
		end
		r.sub:SetText((best and ("|cff40ff40Best: " .. best .. " - " .. PF.Money(bestV * e.n) .. " for all|r\n") or "") .. "|cffaaaaaa" .. table.concat(bits, "   ") .. "|r")
		local cookBest = best and best:find("^Cook")
		r.btn:SetText("Cook " .. e.n)
		r.btn:SetEnabled(CookingOpen() and true or false)
		r.btn:SetScript("OnClick", function() Cook(e.cooked, e.n) end)
		r.btn:SetAlpha(cookBest and 1 or 0.6)
		r:Show()
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
	if #list == 0 then status:SetText(status:GetText() .. "\n\nNo fish in your bags that cook into anything.") end
	w:SetHeight(66 + math.max(#list, 1) * ROW + 60)
end
w:SetScript("OnShow", PF.DrawCook)
local ev = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "PLAYER_REGEN_DISABLED" }) do pcall(ev.RegisterEvent, ev, e) end
-- (it holds spell buttons, so it closes as a fight starts - the game wouldn't let it close during one)
ev:SetScript("OnEvent", function(_, e) if e == "PLAYER_REGEN_DISABLED" then w:Hide() elseif w:IsShown() then PF.DrawCook() end end)
function PF.ToggleCook() if InCombatLockdown() then return end; if w:IsShown() then w:Hide() else w:Show() end end
