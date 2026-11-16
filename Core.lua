local ADDON, ns = ...

AWay = {}

local defaults = {
	arrow = true,
	arrive = true,
	single = false,
	mapPins = true,
	miniPins = true,
	arrowDb = { scale = 1, locked = false, default = { "CENTER", "CENTER", 0, 190 } },
}

local charDefaults = {
	list = {},
}

ACore.New(ADDON, ns, { db = "AWayDB", defaults = defaults, profile = true, char = "AWayCharDB", charDefaults = charDefaults })

function ns.Num(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "number" then return nil end
	return v
end

function ns.Coord(v)
	return string.format("%.1f", (v or 0) * 100)
end

function ns.MapName(map)
	local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	local name = info and info.name
	if type(name) ~= "string" or ns.IsSecret(name) then return "" end
	return name
end

function ns.Canvas()
	if not WorldMapFrame then return nil end
	if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
	return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

function ns.MapID()
	if not WorldMapFrame or not WorldMapFrame.GetMapID then return nil end
	local ok, map = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
	return ok and ns.Num(map) or nil
end

function ns.MapShown()
	return WorldMapFrame and WorldMapFrame:IsShown() and true or false
end

function ns.PlayerMap()
	if not C_Map or not C_Map.GetBestMapForUnit then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	return ok and ns.Num(map) or nil
end

function ns.Place(frame, x, y)
	local c = ns.Canvas()
	if not c then return end
	local eff = ns.Num(c:GetEffectiveScale()) or 1
	if eff <= 0 then eff = 1 end
	local scale = (ns.Num(UIParent:GetEffectiveScale()) or 1) / eff
	frame:SetScale(scale)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", c, "TOPLEFT", x * (c:GetWidth() or 0) / scale, -y * (c:GetHeight() or 0) / scale)
end

local RADIUS = {
	[0] = { 150, 120, 90, 60, 40, 25 },
	[1] = { 233.33, 200, 166.67, 133.33, 100, 66.67 },
}

function ns.ViewRadius()
	if C_Minimap and C_Minimap.GetViewRadius then
		local ok, r = pcall(C_Minimap.GetViewRadius)
		r = ok and ns.Num(r)
		if r and r > 0 then return r end
	end
	local zoom = ns.Num(Minimap:GetZoom()) or 0
	local outdoors = 1
	if IsIndoors and IsIndoors() then outdoors = 0 end
	return RADIUS[outdoors][zoom + 1] or 150
end

function ns.WorldPos(map, x, y)
	if not C_Map or not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return nil end
	local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not ok or not pos then return nil end
	local north, west = pos.x, pos.y
	if pos.GetXY then north, west = pos:GetXY() end
	north, west = ns.Num(north), ns.Num(west)
	if not north or not west then return nil end
	return north, west, ns.Num(continent)
end

function ns.PlayerWorld()
	if not UnitPosition then return nil end
	local ok, north, west, _, instance = pcall(UnitPosition, "player")
	if not ok then return nil end
	north, west = ns.Num(north), ns.Num(west)
	if not north or not west then return nil end
	return north, west, ns.Num(instance)
end

local zoneIndex
local function scan(from, to)
	for map = from, to do
		local name = ns.MapName(map)
		if name ~= "" then
			local key = name:lower()
			if not zoneIndex[key] then zoneIndex[key] = map end
		end
	end
end

function ns.FindZone(text)
	if not C_Map or not C_Map.GetMapInfo then return nil end
	text = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	if not zoneIndex then
		zoneIndex = {}
		scan(1400, 1500)
		scan(900, 1399)
	end
	if zoneIndex[text] then return zoneIndex[text] end
	local best
	for name, map in pairs(zoneIndex) do
		if name:find(text, 1, true) and (not best or map < best) then best = map end
	end
	return best
end

function ns.Options()
	local db = ns.db
	local UI = ns.UI
	local function changed() ns:Fire("OPTIONS") end
	local entries = {
		{ text = "Waypoints", title = true },
		UI.Check(db, "arrow", "Direction arrow", changed),
		UI.Check(db.arrowDb, "locked", "Lock the arrow", changed),
		UI.Check(db, "arrive", "Clear on arrival", changed),
		UI.Check(db, "single", "One waypoint only", changed),
		UI.Check(db, "mapPins", "Pins on the world map", changed),
		UI.Check(db, "miniPins", "Pins on the minimap", changed),
		{ text = "Next waypoint", func = function() AWay.Next() end },
		{ text = "Clear all waypoints", func = function() AWay.Clear() end },
		{ text = "Reset arrow position", func = function()
			db.arrowDb.pos = nil
			ns:Fire("LAYOUT_RESET")
		end },
	}
	local list = AWay.List()
	if #list > 0 then
		entries[#entries + 1] = { text = "Go to", title = true }
		for i, w in ipairs(list) do
			if i > 12 then break end
			entries[#entries + 1] = { text = w.title, checked = w.active, func = function() AWay.Select(i) end }
		end
	end
	return entries
end

function ns.OpenOptions(anchor)
	ns.UI.Menu(anchor or UIParent, ns.Options())
end

ACore.Register({
	name = "AWay",
	options = function() return ns.Options() end,
	title = "AWay",
	slash = "/way",
	desc = "waypoints and arrow",
	toggle = function()
		if ACoreMinimapButton and ACoreMinimapButton:IsShown() then
			ns.OpenOptions(ACoreMinimapButton)
		else
			ns.OpenOptions(Minimap)
		end
	end,
})

SLASH_AWAYOPT1 = "/away"
SlashCmdList["AWAYOPT"] = function(msg)
	local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if cmd == "unlock" then
		ns.db.arrowDb.locked = false
		ns:Fire("OPTIONS")
		ns.Print("arrow unlocked, drag to move")
	elseif cmd == "lock" then
		ns.db.arrowDb.locked = true
		ns:Fire("OPTIONS")
	elseif cmd == "reset" then
		ns.db.arrowDb.pos = nil
		ns:Fire("LAYOUT_RESET")
	elseif cmd == "clear" then
		AWay.Clear()
	else
		ns.OpenOptions(Minimap)
	end
end

BINDING_HEADER_AWAY = "AWay"
BINDING_NAME_AWAY_CLEAR = "Clear waypoints"
BINDING_NAME_AWAY_NEXT = "Next waypoint"
