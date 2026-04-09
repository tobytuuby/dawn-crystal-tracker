-- DawnCrystalTracker (Retail)
-- Read-only informational helper to indicate whether YOUR character currently has the Dawn Crystal.
-- It observes UI/action/aura state only and does not automate gameplay.

local ADDON_NAME = ...

-- ============================================================================
-- EDITABLE CONFIG
-- ============================================================================

local KNOWN_EXTRA_ACTION_SPELL_IDS = {
	-- [123456] = true,
}

-- Optional: some encounter buttons are items instead of spells.
local KNOWN_EXTRA_ACTION_ITEM_IDS = {
	-- [123456] = true,
}

local KNOWN_OVERRIDE_SPELL_IDS = {
	-- [123456] = true,
}

local KNOWN_OVERRIDE_ITEM_IDS = {
	-- [123456] = true,
}

local KNOWN_BUFF_IDS = {
	-- [123456] = true,
}

local KNOWN_DEBUFF_IDS = {
	-- [123456] = true,
}

local KNOWN_OVERRIDE_TEXTURES = {
	-- Texture fileIDs or paths as keys:
	-- [1234567] = true,
	-- ["Interface\\Icons\\INV_Misc_Gem_01"] = true,
}

local KNOWN_ICON_TEXTURES = {
	-- Texture fileIDs or paths as keys:
	-- [1234567] = true,
	-- ["Interface\\Icons\\INV_Misc_Gem_01"] = true,
}

local KNOWN_EXTRA_ACTION_KEYWORDS = {
	"Dawn Crystal",
	"Dawnlight",
	"Crystal",
}

local KNOWN_OVERRIDE_KEYWORDS = {
	"Dawn Crystal",
	"Crystal",
}

local KNOWN_AURA_KEYWORDS = {
	"Dawn Crystal",
	"Dawnlight Barrier",
	"Crystal",
}

-- Icon-only UI behavior
local HIDE_WHEN_INACTIVE = true
-- Minimap button icon (static). Use a built-in game icon texture path (no file extension).
local MINIMAP_ICON_TEXTURE = "Interface\\Icons\\spell_holy_purifyingpower"
-- If true, show a faint border (and optional placeholder) when inactive so you can move it any time,
-- including outside the raid and while using in-game Edit Mode.
local SHOW_ANCHOR_WHEN_INACTIVE = true
local SHOW_PLACEHOLDER_ICON_WHEN_INACTIVE = true
local INACTIVE_ANCHOR_ALPHA = 0.20

-- ============================================================================
-- INTERNALS
-- ============================================================================

local DEFAULT_DB = {
	enabled = true,
	debug = false,
	point = "TOP",
	relativePoint = "TOP",
	x = 0,
	y = -120,
	minimap = {
		hide = false,
		angle = 2.6, -- radians
	},
	lastKnownIcon = nil, -- texture fileID or path
	lastKnownSpellID = nil,
	lastKnownSpellName = nil,
	lastMeta = nil, -- optional: last known detection metadata
}

local DB -- assigned on ADDON_LOADED
local minimap_apply_position, minimap_apply_icon

local function dct_print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffFFD200DCT|r: " .. msg)
end

local function dct_debug(msg)
	if DB and DB.debug then
		dct_print("|cff888888" .. msg .. "|r")
	end
end

local function normalize_texture_key(tex)
	if tex == nil then
		return nil
	end
	if type(tex) == "number" then
		return tex
	end
	if type(tex) == "string" then
		return tex
	end
	return tostring(tex)
end

local function str_contains_any(haystack, keywords)
	if not haystack or not keywords then
		return false
	end
	local hs = string.lower(tostring(haystack))
	for _, kw in ipairs(keywords) do
		if kw and kw ~= "" then
			local needle = string.lower(tostring(kw))
			if needle ~= "" and string.find(hs, needle, 1, true) then
				return true
			end
		end
	end
	return false
end

local function is_known_texture(tex, known)
	local key = normalize_texture_key(tex)
	return key ~= nil and known and known[key] == true
end

local function safe_GetSpellInfo(spellID)
	if not spellID or type(spellID) ~= "number" then
		return nil
	end
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellID)
	end
	if GetSpellInfo then
		return GetSpellInfo(spellID)
	end
	return nil
end

local function safe_GetSpellTexture(spellID)
	if not spellID or type(spellID) ~= "number" then
		return nil
	end
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(spellID)
	end
	if GetSpellTexture then
		return GetSpellTexture(spellID)
	end
	return nil
end

local function safe_GetItemName(itemID)
	if not itemID or type(itemID) ~= "number" then
		return nil
	end
	if C_Item and C_Item.GetItemNameByID then
		return C_Item.GetItemNameByID(itemID)
	end
	if GetItemInfo then
		local name = GetItemInfo(itemID)
		return name
	end
	return nil
end

local function safe_GetItemIcon(itemID)
	if not itemID or type(itemID) ~= "number" then
		return nil
	end
	if C_Item and C_Item.GetItemIconByID then
		return C_Item.GetItemIconByID(itemID)
	end
	if GetItemIcon then
		return GetItemIcon(itemID)
	end
	return nil
end

local function pack_meta(tbl)
	-- Create a shallow copy that is safe to store
	if not tbl then
		return nil
	end
	local out = {}
	for k, v in pairs(tbl) do
		if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then
			out[k] = v
		else
			out[k] = tostring(v)
		end
	end
	return out
end

local function meta_to_string(meta)
	if not meta then
		return "nil"
	end
	local parts = {}
	local function add(k, v)
		if v ~= nil then
			parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
		end
	end
	add("source", meta.source)
	add("spellID", meta.spellID)
	add("itemID", meta.itemID)
	add("name", meta.name)
	add("itemName", meta.itemName)
	add("texture", meta.texture)
	add("actionSlot", meta.actionSlot)
	add("actionType", meta.actionType)
	add("actionID", meta.actionID)
	add("extraR1", meta.extraR1)
	add("extraR2", meta.extraR2)
	add("extraR3", meta.extraR3)
	add("extraR4", meta.extraR4)
	add("auraKind", meta.auraKind)
	add("auraIndex", meta.auraIndex)
	add("button", meta.button)
	return table.concat(parts, ", ")
end

local function get_button_icon_texture(btn)
	if not btn then
		return nil
	end
	local icon =
		btn.icon
		or btn.Icon
		or btn.IconTexture
		or btn.iconTexture
		or (btn.GetIconTexture and btn:GetIconTexture())
	if icon and icon.GetTexture then
		return icon:GetTexture()
	end
	if btn.GetNormalTexture then
		local t = btn:GetNormalTexture()
		if t and t.GetTexture then
			return t:GetTexture()
		end
	end
	return nil
end

local DEBUG_THROTTLE = {}
local function dct_debug_throttled(key, msg, intervalSeconds)
	if not (DB and DB.debug) then
		return
	end
	local now = type(GetTime) == "function" and GetTime() or 0
	local last = DEBUG_THROTTLE[key]
	if not last or (now - last) >= (intervalSeconds or 2) then
		DEBUG_THROTTLE[key] = now
		dct_debug(msg)
	end
end

-- ============================================================================
-- UI
-- ============================================================================

local Frame = CreateFrame("Frame", "DawnCrystalTrackerFrame", UIParent)
Frame:SetSize(40, 40)
Frame:SetFrameStrata("HIGH")
Frame:SetClampedToScreen(true)
Frame:SetMovable(true)
Frame:EnableMouse(true)
Frame:RegisterForDrag("LeftButton")

local Icon = Frame:CreateTexture(nil, "ARTWORK")
Icon:SetAllPoints(Frame)
Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local Border = Frame:CreateTexture(nil, "OVERLAY")
Border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
Border:SetBlendMode("ADD")
Border:SetAlpha(0.55)
Border:SetSize(70, 70)
Border:SetPoint("CENTER", Frame, "CENTER", 0, 0)
Border:Hide()

local ActiveGlow = Frame:CreateTexture(nil, "OVERLAY")
ActiveGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
ActiveGlow:SetBlendMode("ADD")
ActiveGlow:SetAlpha(0.90)
ActiveGlow:SetSize(70, 70)
ActiveGlow:SetPoint("CENTER", Frame, "CENTER", 0, 0)
ActiveGlow:Hide()

local DebugText = Frame:CreateFontString(nil, "OVERLAY")
DebugText:SetPoint("TOP", Frame, "BOTTOM", 0, -2)
DebugText:SetJustifyH("CENTER")
DebugText:SetTextColor(1, 1, 1, 1)
DebugText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
DebugText:Hide()

Frame:SetScript("OnDragStart", function(self)
	if InCombatLockdown and InCombatLockdown() then
		dct_debug("Cannot drag in combat.")
		return
	end
	self:StartMoving()
end)

Frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	if not DB then
		return
	end
	local point, _, relativePoint, x, y = self:GetPoint(1)
	DB.point = point
	DB.relativePoint = relativePoint
	DB.x = math.floor(x + 0.5)
	DB.y = math.floor(y + 0.5)
end)

local function apply_position()
	if not DB then
		return
	end
	Frame:ClearAllPoints()
	Frame:SetPoint(DB.point or "TOP", UIParent, DB.relativePoint or "TOP", DB.x or 0, DB.y or -120)
end

local function apply_visibility()
	if not DB then
		return
	end
	if not DB.enabled then
		Frame:Hide()
		return
	end
	-- Enabled: visibility will be driven by current state in set_indicator()
end

local function choose_icon_texture(hasCrystal, meta)
	if not hasCrystal then
		return nil
	end

	-- 1) Extra action button icon (most accurate to the mechanic)
	local tex = get_button_icon_texture(_G.ExtraActionButton1)
	if tex then
		return tex
	end

	-- 2) Spell icon from detected spellID
	if meta and meta.spellID then
		tex = safe_GetSpellTexture(meta.spellID)
		if tex then
			return tex
		end
	end

	-- 3) Aura icon / detected meta texture
	if meta and meta.texture then
		return meta.texture
	end

	-- 4) Override texture (already included in meta.texture when detected)
	return nil
end

local function set_indicator(hasCrystal, meta)
	if not DB or not DB.enabled then
		Frame:Hide()
		return
	end

	local tex = choose_icon_texture(hasCrystal, meta)
	if tex then
		DB.lastKnownIcon = tex
	end

	if hasCrystal then
		Frame:Show()
		Border:Show()
		Icon:SetTexture(tex or DB.lastKnownIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
		Icon:SetDesaturated(false)
		Icon:SetAlpha(1)
		ActiveGlow:Show()
	else
		ActiveGlow:Hide()
		local editModeShown = EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown()
		local showAnchor = SHOW_ANCHOR_WHEN_INACTIVE or editModeShown or DB.debug

		if HIDE_WHEN_INACTIVE and not showAnchor then
			Border:Hide()
			Frame:Hide()
		else
			Frame:Show()
			Border:SetAlpha(0.55)
			Border:Show()
			if SHOW_PLACEHOLDER_ICON_WHEN_INACTIVE then
				Icon:SetTexture(DB.lastKnownIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
				Icon:SetDesaturated(true)
				Icon:SetAlpha(INACTIVE_ANCHOR_ALPHA)
			else
				Icon:SetTexture(nil)
				Icon:SetAlpha(0)
			end
		end
	end

	if DB.debug then
		local line = hasCrystal and "YES" or "NO"
		if meta and (meta.spellID or meta.itemID) then
			line = line .. "  " .. (meta.spellID and ("spell:" .. tostring(meta.spellID)) or ("item:" .. tostring(meta.itemID)))
		elseif meta and meta.source then
			line = line .. "  " .. tostring(meta.source)
		end
		DebugText:SetText(line)
		DebugText:Show()
	else
		DebugText:Hide()
	end
end

-- ============================================================================
-- DETECTION
-- ============================================================================

local function try_detect_from_extra_action()
	-- PRIMARY AND AUTHORITATIVE:
	-- Confirmed in-game: Dawn Crystal ownership is represented by the presence of the Extra Action Button.
	-- If ExtraActionButton1 is active/visible => player HAS the crystal.
	-- If it is not active/visible => player does NOT have the crystal.
	local extraShown = false
	if type(HasExtraActionBar) == "function" and HasExtraActionBar() then
		extraShown = true
	end
	if ExtraActionBarFrame and ExtraActionBarFrame.IsShown and ExtraActionBarFrame:IsShown() then
		extraShown = true
	end
	if ExtraActionButton1 and ExtraActionButton1.IsShown and ExtraActionButton1:IsShown() then
		extraShown = true
	end
	if not extraShown then
		return false, nil
	end

	local spellID, texture, name
	local meta = { source = "extra" }

	if type(GetExtraActionInfo) == "function" then
		-- Historically returns (spellID, texture, ...)
		local a, b, c, d = GetExtraActionInfo()
		meta.extraR1, meta.extraR2, meta.extraR3, meta.extraR4 = a, b, c, d
		-- Many builds use (spellID, texture). Some use different ordering; store all and rely on other fallbacks.
		if type(a) == "number" then
			spellID = a
		end
		if type(b) == "number" and not spellID then
			spellID = b
		end
		if type(b) == "string" or type(b) == "number" then
			texture = b
		end
	end

	if ExtraActionButton1 then
		-- Try secure attributes first (some UIs don't expose .action)
		local attrType = ExtraActionButton1.GetAttribute and ExtraActionButton1:GetAttribute("type") or nil
		local attrSpell = ExtraActionButton1.GetAttribute and ExtraActionButton1:GetAttribute("spell") or nil
		local attrItem = ExtraActionButton1.GetAttribute and ExtraActionButton1:GetAttribute("item") or nil

		if not spellID and attrType == "spell" then
			spellID = tonumber(attrSpell) or spellID
		end
		if not meta.itemID and attrType == "item" then
			meta.itemID = tonumber(attrItem) or meta.itemID
		end

		local action = ExtraActionButton1.action
		if not action and ExtraActionButton1.GetAttribute then
			action = ExtraActionButton1:GetAttribute("action")
		end
		action = tonumber(action) or action
		-- Hard fallback: ExtraActionButton1 is very commonly action slot 169.
		if not action then
			action = 169
		end
		meta.actionSlot = action

		if action and type(GetActionInfo) == "function" then
			local actionType, actionID = GetActionInfo(action)
			if actionType and actionID then
				meta.actionType = actionType
				meta.actionID = actionID
				if actionType == "spell" and type(actionID) == "number" then
					spellID = spellID or actionID
				elseif actionType == "item" and type(actionID) == "number" then
					meta.itemID = actionID
				end
			end
			if type(GetActionTexture) == "function" then
				texture = texture or GetActionTexture(action)
			end
		end
		texture = texture or get_button_icon_texture(ExtraActionButton1)
	end

	if spellID then
		name = safe_GetSpellInfo(spellID)
		texture = texture or safe_GetSpellTexture(spellID)
	elseif meta.itemID then
		meta.itemName = safe_GetItemName(meta.itemID)
		texture = texture or safe_GetItemIcon(meta.itemID)
	end

	meta.spellID = spellID
	meta.name = name
	meta.texture = texture
	meta.button = "ExtraActionButton1"
	return true, meta
end

local function scan_action_buttons_for_match(buttonPrefix, count, knownIDs, keywords, knownTextures, sourceName)
	for i = 1, count do
		local btn = _G[buttonPrefix .. i]
		if btn and btn.IsShown and btn:IsShown() then
			local action = btn.action
			if not action and btn.GetAttribute then
				action = btn:GetAttribute("action")
			end

			local actionType, actionID
			if action and type(GetActionInfo) == "function" then
				actionType, actionID = GetActionInfo(action)
			end

			local spellID, itemID, name, itemName, texture
			if actionType == "spell" and type(actionID) == "number" then
				spellID = actionID
				name = safe_GetSpellInfo(spellID)
				texture = safe_GetSpellTexture(spellID)
			elseif actionType == "item" and type(actionID) == "number" then
				itemID = actionID
				itemName = safe_GetItemName(itemID)
				texture = safe_GetItemIcon(itemID)
			end
			if not texture and action and type(GetActionTexture) == "function" then
				texture = GetActionTexture(action)
			end
			if not texture and btn.icon and btn.icon.GetTexture then
				texture = btn.icon:GetTexture()
			end

			local meta = {
				source = sourceName,
				button = buttonPrefix .. i,
				actionType = actionType,
				actionID = actionID,
				spellID = spellID,
				itemID = itemID,
				name = name,
				itemName = itemName,
				texture = texture,
			}

			local matched = false
			if spellID and knownIDs and knownIDs[spellID] then
				matched = true
			end
			-- If caller wants item matching, it can pass an itemID table in knownIDs too.
			if not matched and itemID and knownIDs and knownIDs[itemID] then
				matched = true
			end
			if not matched and name and keywords and str_contains_any(name, keywords) then
				matched = true
			end
			if not matched and itemName and keywords and str_contains_any(itemName, keywords) then
				matched = true
			end
			if not matched and knownTextures and is_known_texture(texture, knownTextures) then
				matched = true
			end

			if matched then
				return true, meta
			end
		end
	end
	return false, nil
end

local function try_detect_from_override_or_zone()
	-- SECONDARY: override / vehicle / zone-action / temp encounter actions
	local hasOverride = false
	if type(HasOverrideActionBar) == "function" and HasOverrideActionBar() then
		hasOverride = true
	end
	if OverrideActionBar and OverrideActionBar.IsShown and OverrideActionBar:IsShown() then
		hasOverride = true
	end

	if hasOverride then
		-- Merge spell and item IDs into one lookup table for this scan.
		local known = KNOWN_OVERRIDE_SPELL_IDS
		if KNOWN_OVERRIDE_ITEM_IDS and next(KNOWN_OVERRIDE_ITEM_IDS) ~= nil then
			known = {}
			for k, v in pairs(KNOWN_OVERRIDE_SPELL_IDS) do
				known[k] = v
			end
			for k, v in pairs(KNOWN_OVERRIDE_ITEM_IDS) do
				known[k] = v
			end
		end
		local ok, meta = scan_action_buttons_for_match("OverrideActionBarButton", 6, known, KNOWN_OVERRIDE_KEYWORDS, KNOWN_OVERRIDE_TEXTURES, "override")
		if ok then
			return true, meta
		end
	end

	-- Zone ability button(s)
	if ZoneAbilityFrame and ZoneAbilityFrame.IsShown and ZoneAbilityFrame:IsShown() then
		local btn = ZoneAbilityFrame.SpellButton or (ZoneAbilityFrame.SpellButtonContainer and ZoneAbilityFrame.SpellButtonContainer.SpellButton)
		if btn and btn.IsShown and btn:IsShown() then
			local spellID = btn.spellID
			if not spellID and btn.GetSpellID then
				spellID = btn:GetSpellID()
			end
			local name = safe_GetSpellInfo(spellID)
			local texture = nil
			if spellID then
				texture = safe_GetSpellTexture(spellID)
			end
			if not texture and btn.Icon and btn.Icon.GetTexture then
				texture = btn.Icon:GetTexture()
			elseif not texture and btn.icon and btn.icon.GetTexture then
				texture = btn.icon:GetTexture()
			end

			local meta = { source = "zone", button = "ZoneAbility", spellID = spellID, name = name, texture = texture }
			local matched = false
			if spellID and KNOWN_OVERRIDE_SPELL_IDS[spellID] then
				matched = true
			end
			if not matched and name and str_contains_any(name, KNOWN_OVERRIDE_KEYWORDS) then
				matched = true
			end
			if not matched and is_known_texture(texture, KNOWN_OVERRIDE_TEXTURES) then
				matched = true
			end
			if matched then
				return true, meta
			end
			-- Do not spam chat: store for /dct dump instead.
			if DB then
				DB.lastUnmatchedZone = pack_meta(meta)
			end
			return false, meta
		end
	end

	-- Vehicle action bar is too broad; only used as a trigger to rescan.
	return false, nil
end

local function for_each_player_aura(callback)
	-- callback(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod, auraKind, auraIndex)
	if AuraUtil and AuraUtil.ForEachAura then
		local stop = false
		local function handle(auraData, kind, index)
			return callback(
				auraData.name,
				auraData.icon,
				auraData.applications,
				auraData.dispelName,
				auraData.duration,
				auraData.expirationTime,
				auraData.sourceUnit,
				auraData.isStealable,
				auraData.nameplateShowPersonal,
				auraData.spellId,
				auraData.canApplyAura,
				auraData.isBossAura,
				auraData.isFromPlayerOrPlayerPet,
				auraData.nameplateShowAll,
				auraData.timeMod,
				kind,
				index
			)
		end

		local function iterate(filter, kind)
			local function f(a1, a2)
				if stop then
					return true
				end
				local auraData = a1
				local auraInstanceID = nil
				if type(auraData) ~= "table" and type(a2) == "table" then
					auraInstanceID = a1
					auraData = a2
				end
				if type(auraData) ~= "table" then
					return false
				end
				local shouldStop = handle(auraData, kind, auraInstanceID or auraData.auraInstanceID or 0) == true
				if shouldStop then
					stop = true
					return true
				end
				return false
			end

			-- Prefer packed auraData if supported; fall back otherwise.
			local ok = pcall(AuraUtil.ForEachAura, "player", filter, nil, f, true)
			if not ok then
				AuraUtil.ForEachAura("player", filter, nil, f)
			end
		end

		iterate("HELPFUL", "HELPFUL")
		iterate("HARMFUL", "HARMFUL")
		return
	end

	-- Legacy fallback (slower)
	for i = 1, 40 do
		local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitBuff("player", i)
		if not name then
			break
		end
		if callback(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, nil, nil, nil, nil, nil, "HELPFUL", i) then
			return
		end
	end
	for i = 1, 40 do
		local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitDebuff("player", i)
		if not name then
			break
		end
		if callback(name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, nil, nil, nil, nil, nil, "HARMFUL", i) then
			return
		end
	end
end

local function try_detect_from_auras()
	-- TERTIARY: player aura scanning
	local foundMeta
	local found = false
	for_each_player_aura(function(name, icon, _, _, _, _, _, _, _, spellId, _, _, _, _, _, auraKind, auraIndex)
		if spellId and KNOWN_BUFF_IDS[spellId] then
			found = true
		elseif spellId and KNOWN_DEBUFF_IDS[spellId] then
			found = true
		elseif name and str_contains_any(name, KNOWN_AURA_KEYWORDS) then
			found = true
		end
		if found then
			foundMeta = {
				source = "aura",
				auraKind = auraKind,
				auraIndex = auraIndex,
				spellID = spellId,
				name = name,
				texture = icon,
			}
			return true
		end
		return false
	end)
	return found, foundMeta
end

local function detect_has_crystal()
	-- Source of truth: Extra Action Button presence.
	local ok, meta = try_detect_from_extra_action()
	if ok then
		return true, meta, "Detected via Extra Action Button"
	end

	-- Not active => player does not have Dawn Crystal.
	-- Keep existing fallback scans ONLY as metadata helpers (do not override the authoritative signal).
	local meta2, meta3
	local _, m2 = try_detect_from_override_or_zone()
	meta2 = m2
	local _, m3 = try_detect_from_auras()
	meta3 = m3
	if DB then
		DB.lastFallbackMeta = pack_meta(meta2 or meta3)
	end

	return false, meta2 or meta3, "Extra Action Button not active"
end

-- ============================================================================
-- STATE MACHINE
-- ============================================================================

local currentState = nil -- nil until first evaluation
local lastMeta = nil
local testMode = false
local testState = false

local function SetState(hasCrystal, reason, iconTexture, spellID, spellName, meta)
	if testMode then
		hasCrystal = testState
		meta = meta or { source = "test", name = "Test Mode", texture = nil }
	end

	if DB then
		if iconTexture then
			DB.lastKnownIcon = iconTexture
		end
		if spellID then
			DB.lastKnownSpellID = spellID
		end
		if spellName then
			DB.lastKnownSpellName = spellName
		end
		DB.lastMeta = pack_meta(meta)
	end

	if minimap_apply_icon then
		minimap_apply_icon()
	end

	set_indicator(hasCrystal, meta)

	if currentState == nil then
		currentState = hasCrystal
		lastMeta = meta
		dct_debug("Initial state=" .. tostring(hasCrystal) .. " (" .. (reason or "init") .. ") meta=" .. meta_to_string(meta))
		return
	end

	if hasCrystal ~= currentState then
		currentState = hasCrystal
		lastMeta = meta
		if hasCrystal then
			dct_print("You have Dawn Crystal")
		else
			dct_print("You lost Dawn Crystal")
		end
		dct_debug("State changed (" .. (reason or "update") .. "): " .. meta_to_string(meta))
	else
		lastMeta = meta or lastMeta
	end
end

local function update()
	if not DB then
		return
	end
	local hasCrystal, meta, reason = detect_has_crystal()

	local iconTexture = nil
	local spellID = meta and meta.spellID or nil
	local spellName = meta and meta.name or nil
	if hasCrystal then
		iconTexture = get_button_icon_texture(_G.ExtraActionButton1) or (meta and meta.texture) or nil
	end

	SetState(hasCrystal, reason, iconTexture, spellID, spellName, meta)
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

local function reset_position()
	if not DB then
		return
	end
	DB.point = DEFAULT_DB.point
	DB.relativePoint = DEFAULT_DB.relativePoint
	DB.x = DEFAULT_DB.x
	DB.y = DEFAULT_DB.y
	apply_position()
end

local function toggle_enabled()
	if not DB then
		return
	end
	DB.enabled = not DB.enabled
	apply_visibility()
end

local function toggle_debug()
	if not DB then
		return
	end
	DB.debug = not DB.debug
	dct_print(DB.debug and "Debug enabled" or "Debug disabled")
end

local function toggle_minimap()
	if not DB then
		return
	end
	DB.minimap = DB.minimap or {}
	DB.minimap.hide = not DB.minimap.hide
	if minimap_apply_position then
		minimap_apply_position()
	end
	dct_print(DB.minimap.hide and "Minimap icon hidden" or "Minimap icon shown")
end

local function cmd_dump()
	local meta = lastMeta or (DB and DB.lastMeta) or nil
	dct_print("Detected: state=" .. tostring(currentState) .. " meta={" .. meta_to_string(meta) .. "}")
	if DB and DB.lastFallbackMeta then
		dct_print("Last fallback meta={" .. meta_to_string(DB.lastFallbackMeta) .. "}")
	end
	if DB and (DB.lastKnownIcon or DB.lastKnownSpellID or DB.lastKnownSpellName) then
		dct_print(
			"LastKnown: icon="
				.. tostring(DB.lastKnownIcon)
				.. ", spellID="
				.. tostring(DB.lastKnownSpellID)
				.. ", spellName="
				.. tostring(DB.lastKnownSpellName)
		)
	end
end

local function cmd_test()
	testMode = true
	testState = not testState
	dct_print("Test mode: simulating " .. (testState and "GAIN" or "LOSS"))
	SetState(testState, "test", nil, nil, nil, { source = "test", name = "Test Mode", texture = nil })
end

local function cmd_test_off()
	testMode = false
	dct_print("Test mode off")
	update()
end

SLASH_DAWNCRYSTALTRACKER1 = "/dct"
SlashCmdList.DAWNCRYSTALTRACKER = function(msg)
	msg = msg and msg:match("^%s*(.-)%s*$") or ""
	msg = string.lower(msg)

	if msg == "" then
		toggle_enabled()
		return
	end

	if msg == "debug" then
		toggle_debug()
		return
	end

	if msg == "test" then
		cmd_test()
		return
	end

	if msg == "testoff" or msg == "test off" then
		cmd_test_off()
		return
	end

	if msg == "reset" then
		reset_position()
		dct_print("Position reset")
		return
	end

	if msg == "dump" then
		cmd_dump()
		return
	end

	dct_print("Commands: /dct, /dct debug, /dct test, /dct reset, /dct dump (optional: /dct testoff)")
end

-- ============================================================================
-- MINIMAP ICON (no libraries)
-- ============================================================================

do
	local MinimapButton = CreateFrame("Button", "DawnCrystalTrackerMinimapButton", Minimap)
	MinimapButton:SetSize(32, 32)
	MinimapButton:SetFrameStrata("MEDIUM")
	MinimapButton:SetClampedToScreen(true)
	MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	MinimapButton:RegisterForDrag("LeftButton")

	-- Minimap shapes: true means that quadrant is rounded (needs corner-clamping)
	-- Order: top-left, top-right, bottom-left, bottom-right
	local MINIMAP_SHAPES = {
		ROUND = { true, true, true, true },
		SQUARE = { false, false, false, false },
		["CORNER-TOPLEFT"] = { true, false, false, false },
		["CORNER-TOPRIGHT"] = { false, true, false, false },
		["CORNER-BOTTOMLEFT"] = { false, false, true, false },
		["CORNER-BOTTOMRIGHT"] = { false, false, false, true },
		["SIDE-LEFT"] = { true, false, true, false },
		["SIDE-RIGHT"] = { false, true, false, true },
		["SIDE-TOP"] = { true, true, false, false },
		["SIDE-BOTTOM"] = { false, false, true, true },
		["TRICORNER-TOPLEFT"] = { true, true, true, false },
		["TRICORNER-TOPRIGHT"] = { true, true, false, true },
		["TRICORNER-BOTTOMLEFT"] = { true, false, true, true },
		["TRICORNER-BOTTOMRIGHT"] = { false, true, true, true },
	}

	MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local hl = MinimapButton:GetHighlightTexture()
	hl:SetBlendMode("ADD")

	local border = MinimapButton:CreateTexture(nil, "OVERLAY")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT", 0, 0)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	local background = MinimapButton:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetPoint("CENTER", 0, 0)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = MinimapButton:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER", 0, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetTexture(MINIMAP_ICON_TEXTURE or "Interface\\Icons\\INV_Misc_QuestionMark")
	MinimapButton._dctIcon = icon

	local function dct_atan2(y, x)
		if type(math.atan2) == "function" then
			return math.atan2(y, x)
		end
		if type(math.atan) == "function" then
			local ok, r = pcall(math.atan, y, x)
			if ok and type(r) == "number" then
				return r
			end
		end
		if x == 0 then
			return (y >= 0) and (math.pi / 2) or (-math.pi / 2)
		end
		local a = math.atan(y / x)
		if x < 0 then
			a = a + math.pi
		end
		return a
	end

	local function is_mbb_active()
		if type(IsAddOnLoaded) ~= "function" then
			return false
		end
		-- Some users install MBB under different folder names (e.g. "MinimapButtonButton").
		return IsAddOnLoaded("MBB") == true
			or IsAddOnLoaded("MinimapButtonButton") == true
			or IsAddOnLoaded("MBB_Options") == true
	end

	minimap_apply_position = function()
		if not DB or not DB.minimap or DB.minimap.hide then
			MinimapButton:Hide()
			return
		end
		MinimapButton:Show()
		-- If MBB is managing minimap buttons, don't fight it by constantly repositioning.
		if is_mbb_active() then
			-- Ensure we have at least one anchor so the button is visible for MBB to pick up.
			if not MinimapButton:GetPoint(1) then
				MinimapButton:ClearAllPoints()
				MinimapButton:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -6, -6)
			end
			return
		end
		local angle = DB.minimap.angle or DEFAULT_DB.minimap.angle
		local radius = (Minimap:GetWidth() / 2) - 10
		if radius < 20 then
			radius = 70
		end
		local x = math.cos(angle) * radius
		local y = math.sin(angle) * radius

		local shape = (type(GetMinimapShape) == "function" and GetMinimapShape()) or "ROUND"
		local quad = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES.ROUND
		local isTop = y > 0
		local isLeft = x < 0
		local isRoundedCorner = (isTop and isLeft and quad[1]) or (isTop and (not isLeft) and quad[2]) or ((not isTop) and isLeft and quad[3]) or ((not isTop) and (not isLeft) and quad[4])

		if not isRoundedCorner then
			-- Flat edges: clamp to the edge box
			x = math.max(-radius, math.min(radius, x))
			y = math.max(-radius, math.min(radius, y))
		else
			-- Rounded corner: keep inside circle by clamping to the circle perimeter (already on circle via cos/sin)
			-- No extra work needed.
		end

		MinimapButton:ClearAllPoints()
		MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
	end

	minimap_apply_icon = function()
		-- Keep minimap icon static so it remains recognizable even when the tracker icon changes.
		icon:SetTexture(MINIMAP_ICON_TEXTURE or "Interface\\Icons\\INV_Misc_QuestionMark")
	end

	MinimapButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("DawnCrystalTracker")
		GameTooltip:AddLine("Left-click: Toggle tracker frame", 1, 1, 1)
		if is_mbb_active() then
			GameTooltip:AddLine("MBB: Position managed by your minimap button bag", 1, 1, 1)
		else
			GameTooltip:AddLine("Drag: Move minimap icon", 1, 1, 1)
		end
		GameTooltip:Show()
	end)

	MinimapButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	MinimapButton:SetScript("OnClick", function(_, button)
		if button == "LeftButton" then
			toggle_enabled()
		end
	end)

	local dragging = false
	MinimapButton:SetScript("OnDragStart", function()
		if not DB or not DB.minimap then
			return
		end
		if is_mbb_active() then
			return
		end
		dragging = true
	end)

	MinimapButton:SetScript("OnDragStop", function()
		dragging = false
	end)

	MinimapButton:SetScript("OnUpdate", function()
		if not dragging or not DB or not DB.minimap then
			return
		end
		if is_mbb_active() then
			return
		end
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		cx, cy = cx / scale, cy / scale
		DB.minimap.angle = dct_atan2(cy - my, cx - mx)
		minimap_apply_position()
	end)
end

-- ============================================================================
-- EVENTS
-- ============================================================================

local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("PLAYER_LOGIN")
EventFrame:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
EventFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
EventFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
EventFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
EventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
EventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
EventFrame:RegisterEvent("VEHICLE_UPDATE")
EventFrame:RegisterEvent("UNIT_AURA")
EventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
EventFrame:RegisterEvent("ENCOUNTER_START")
EventFrame:RegisterEvent("ENCOUNTER_END")

local pendingUpdate = false
local function request_update()
	if pendingUpdate then
		return
	end
	pendingUpdate = true
	C_Timer.After(0.05, function()
		pendingUpdate = false
		update()
	end)
end

local editModeHooksInstalled = false
local function ensure_edit_mode_hooks()
	if editModeHooksInstalled then
		return
	end
	if not EditModeManagerFrame or not EditModeManagerFrame.HookScript then
		return
	end
	editModeHooksInstalled = true

	EditModeManagerFrame:HookScript("OnShow", function()
		-- Force a refresh so the anchor/border appears while Edit Mode is open.
		request_update()
	end)

	EditModeManagerFrame:HookScript("OnHide", function()
		request_update()
	end)

	-- If Edit Mode is already open when we install hooks.
	if EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown() then
		request_update()
	end
end

EventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			-- Edit Mode UI can be load-on-demand depending on client state.
			if arg1 == "Blizzard_EditMode" then
				ensure_edit_mode_hooks()
			end
			return
		end

		if type(DawnCrystalTrackerDB) ~= "table" then
			DawnCrystalTrackerDB = {}
		end
		DB = DawnCrystalTrackerDB
		for k, v in pairs(DEFAULT_DB) do
			if DB[k] == nil then
				DB[k] = v
			end
		end
		if type(DB.minimap) ~= "table" then
			DB.minimap = {}
		end
		if DB.minimap.hide == nil then
			DB.minimap.hide = DEFAULT_DB.minimap.hide
		end
		if DB.minimap.angle == nil then
			DB.minimap.angle = DEFAULT_DB.minimap.angle
		end
		if DB.lastKnownIcon == nil then
			DB.lastKnownIcon = DEFAULT_DB.lastKnownIcon
		end
		if DB.lastKnownSpellID == nil then
			DB.lastKnownSpellID = DEFAULT_DB.lastKnownSpellID
		end
		if DB.lastKnownSpellName == nil then
			DB.lastKnownSpellName = DEFAULT_DB.lastKnownSpellName
		end

		apply_position()
		apply_visibility()
		if minimap_apply_position then
			minimap_apply_position()
		end
		if minimap_apply_icon then
			minimap_apply_icon()
		end
		ensure_edit_mode_hooks()

		-- default UI state before first scan
		Frame:Hide()

		dct_debug("Loaded. DB.debug=" .. tostring(DB.debug))
		return
	end

	if event == "UNIT_AURA" and arg1 ~= "player" then
		return
	end

	-- Keep it lightweight; do a single rescan per event.
	request_update()
end)
