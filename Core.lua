local ADDON, ns = ...

AWay = {}

local defaults = {
	arrow = true,
	arrive = true,
	single = false,
	corpse = true,
	links = true,
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

function ns.MapInfo(map)
	if type(map) ~= "number" or not C_Map or not C_Map.GetMapInfo then return nil end
	local ok, info = pcall(C_Map.GetMapInfo, map)
	if not ok or type(info) ~= "table" then return nil end
	return info
end

function ns.MapName(map)
	local info = ns.MapInfo(map)
	local name = info and info.name
	if ns.IsSecret(name) or type(name) ~= "string" then return "" end
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

function ns.PlayerPos()
	local map = ns.PlayerMap()
	if not map or not C_Map.GetPlayerMapPosition then return nil end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not ok or type(pos) ~= "table" then return nil end
	local x, y = pos.x, pos.y
	if pos.GetXY then x, y = pos:GetXY() end
	x, y = ns.Num(x), ns.Num(y)
	if not x or not y or (x == 0 and y == 0) then return nil end
	return map, x, y
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

local T = Enum and Enum.UIMapType or {}
local RANK = { [T.Zone or 3] = 1, [T.Continent or 2] = 2, [T.Dungeon or 4] = 3, [T.Orphan or 6] = 4, [T.Micro or 5] = 5 }
local zoneIndex, zoneRank

local function remember(map, name, kind)
	if ns.IsSecret(name) or type(name) ~= "string" or name == "" or type(map) ~= "number" then return end
	local key = name:lower()
	local rank = RANK[kind or -1] or 6
	local old = zoneIndex[key]
	if not old or rank < zoneRank[key] or (rank == zoneRank[key] and map < old) then
		zoneIndex[key], zoneRank[key] = map, rank
	end
end

local function root()
	local map = ns.PlayerMap() or ns.MapID()
	for _ = 1, 12 do
		local info = ns.MapInfo(map)
		local parent = info and ns.Num(info.parentMapID)
		if not parent or parent <= 0 then break end
		map = parent
	end
	return map
end

local function scan(from, to)
	for map = from, to do
		local info = ns.MapInfo(map)
		if info then remember(map, info.name, info.mapType) end
	end
end

function ns.BuildZones()
	zoneIndex, zoneRank = {}, {}
	local n = 0
	if C_Map and C_Map.GetMapChildrenInfo then
		local seen = {}
		for _, top in ipairs({ root() or false, 946, 947 }) do
			if top and not seen[top] then
				seen[top] = true
				local info = ns.MapInfo(top)
				if info then remember(top, info.name, info.mapType) end
				local ok, list = pcall(C_Map.GetMapChildrenInfo, top, nil, true)
				if ok and type(list) == "table" then
					for _, child in ipairs(list) do
						if type(child) == "table" then
							remember(child.mapID, child.name, child.mapType)
							n = n + 1
						end
					end
				end
			end
		end
	end
	if n == 0 then scan(900, 1500) end
	return n
end

function ns.FindZone(text)
	if not C_Map or not C_Map.GetMapInfo then return nil end
	text = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	if not zoneIndex then ns.BuildZones() end
	if zoneIndex[text] then return zoneIndex[text] end
	local best, bestScore
	for name, map in pairs(zoneIndex) do
		local at = name:find(text, 1, true)
		if at then
			local score = (at == 1 and 0 or 100) + zoneRank[name] * 10 + map / 100000
			if not bestScore or score < bestScore then best, bestScore = map, score end
		end
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
		UI.Check(db, "corpse", "Waypoint to my corpse", changed),
		UI.Check(db, "links", "Clickable /way lines in chat", changed),
		{ text = "Next waypoint", func = function() AWay.Next() end },
		{ text = "Closest waypoint", func = function() AWay.Closest() end },
		{ text = "Share with the group", func = function() ns.Way.ShareCommand() end },
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

function ns.Command(cmd)
	if cmd == "unlock" then
		ns.db.arrowDb.locked = false
		ns:Fire("OPTIONS")
		ns.Print("arrow unlocked, drag to move")
	elseif cmd == "lock" then
		ns.db.arrowDb.locked = true
		ns:Fire("OPTIONS")
	elseif cmd == "resetarrow" then
		ns.db.arrowDb.pos = nil
		ns:Fire("LAYOUT_RESET")
	else
		ns.OpenOptions(Minimap)
	end
end

SLASH_AWAYOPT1 = "/wayopt"
SlashCmdList["AWAYOPT"] = function(msg)
	local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if cmd == "reset" then cmd = "resetarrow" end
	if cmd == "clear" then
		AWay.Clear()
	else
		ns.Command(cmd)
	end
end

BINDING_HEADER_AWAY = "AWay"
BINDING_NAME_AWAY_CLEAR = "Clear waypoints"
BINDING_NAME_AWAY_NEXT = "Next waypoint"
BINDING_NAME_AWAY_CLOSEST = "Closest waypoint"
