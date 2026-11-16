local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Way = {}
ns.Way = Way

local ARROW = "Interface\\Minimap\\MinimapArrow"
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local DOT = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2"
local ARRIVE = 8
local points = {}
local active
local mapPins, miniPins = {}, {}
local arrow
local lastDist, lastTime, speed

local function current()
	return active and points[active] or nil
end

local function save()
	if not ns.chardb then return end
	local list = {}
	for i, p in ipairs(points) do list[i] = { p.map, p.x, p.y, p.title } end
	ns.chardb.list = list
	ns.chardb.active = active
end

local function resetEta()
	lastDist, lastTime, speed = nil, nil, nil
end

function Way.VectorTo(p)
	if not p or not p.north then return nil end
	local north, west, instance = ns.PlayerWorld()
	if not north then return nil end
	if p.continent and instance and p.continent ~= instance then return nil end
	local dn, dw = p.north - north, p.west - west
	local dist = math.sqrt(dn * dn + dw * dw)
	local bearing = math.atan2(dw, dn)
	return dist, bearing, dn, dw
end

function Way.Vector()
	return Way.VectorTo(current())
end

function Way.Angle()
	local dist, bearing = Way.Vector()
	if not dist then return nil end
	local facing = GetPlayerFacing and ns.Num(GetPlayerFacing())
	if not facing then return nil, dist end
	local angle = bearing - facing
	while angle > math.pi do angle = angle - 2 * math.pi end
	while angle < -math.pi do angle = angle + 2 * math.pi end
	return angle, dist
end

function Way.Eta(dist)
	local now = GetTime and GetTime() or 0
	if lastDist and lastTime and now > lastTime then
		local dt = now - lastTime
		if dt >= 0.5 then
			local v = (lastDist - dist) / dt
			speed = speed and (speed * 0.6 + v * 0.4) or v
			lastDist, lastTime = dist, now
		end
	else
		lastDist, lastTime = dist, now
	end
	if not speed or speed < 0.5 then return nil end
	return dist / speed
end

local function timeText(seconds)
	if not seconds then return "" end
	if seconds >= 3600 then return "" end
	return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function indexOf(p)
	for i, q in ipairs(points) do
		if q == p then return i end
	end
end

local function pinTooltip(self)
	local p = self.point
	if not p then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(p.title, 1, 0.82, 0)
	GameTooltip:AddLine(ns.MapName(p.map) .. "  " .. ns.Coord(p.x) .. ", " .. ns.Coord(p.y), 0.9, 0.9, 0.92)
	local dist = Way.VectorTo(p)
	if dist then GameTooltip:AddLine(math.floor(dist + 0.5) .. " yards", 0.58, 0.6, 0.65) end
	GameTooltip:AddLine("Click: go here   Right-click: remove", 0.58, 0.6, 0.65)
	GameTooltip:Show()
end

local function makePin(parent, size)
	local f = CreateFrame("Button", nil, parent)
	f:SetSize(size, size)
	f:SetFrameStrata("HIGH")
	f.tex = f:CreateTexture(nil, "OVERLAY")
	f.tex:SetAllPoints(f)
	f:SetScript("OnEnter", pinTooltip)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:SetScript("OnClick", function(self, button)
		local i = indexOf(self.point)
		if not i then return end
		if button == "RightButton" then
			AWay.Remove(i)
		else
			AWay.Select(i)
		end
	end)
	f:Hide()
	return f
end

local function menu(anchor)
	local p = current()
	UI.Menu(anchor, {
		{ text = p and p.title or "Waypoint", title = true },
		{ text = "Clear this", func = function()
			if active then AWay.Remove(active) end
		end },
		{ text = "Clear all", func = function() AWay.Clear() end },
		{ text = "Next waypoint", func = function() AWay.Next() end },
		{ text = "Show on map", func = function()
			local c = current()
			if not c then return end
			if C_Map and C_Map.OpenWorldMap then
				pcall(C_Map.OpenWorldMap, c.map)
			elseif WorldMapFrame and WorldMapFrame.SetMapID then
				if ShowUIPanel then pcall(ShowUIPanel, WorldMapFrame) end
				pcall(WorldMapFrame.SetMapID, WorldMapFrame, c.map)
			end
		end },
		UI.Check(ns.db.arrowDb, "locked", "Lock the arrow"),
		UI.Check(ns.db, "arrive", "Clear on arrival"),
	})
end

local function buildArrow()
	arrow = CreateFrame("Button", "AWayArrow", UIParent)
	arrow:SetSize(150, 74)
	arrow:SetFrameStrata("MEDIUM")
	UI.Movable(arrow, ns.db.arrowDb)
	arrow:RegisterForDrag("LeftButton")
	arrow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	arrow:SetScript("OnDragStart", function(self) self:StartDrag() end)
	arrow:SetScript("OnDragStop", function(self) self:StopDrag() end)
	arrow:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			menu(self)
		elseif IsShiftKeyDown and IsShiftKeyDown() then
			AWay.Next()
		end
	end)
	arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
	arrow.tex:SetSize(44, 44)
	arrow.tex:SetPoint("TOP", 0, 0)
	arrow.tex:SetTexture(ARROW)
	arrow.title = UI.Text(arrow, "GameFontNormalSmall", "CENTER", C.accent)
	arrow.title:SetPoint("TOP", arrow.tex, "BOTTOM", 0, 0)
	arrow.title:SetWidth(150)
	arrow.dist = UI.Text(arrow, "GameFontHighlightSmall", "CENTER")
	arrow.dist:SetPoint("TOP", arrow.title, "BOTTOM", 0, -2)
	arrow:Hide()
end

local function hideFrom(pool, n)
	for i = n, #pool do
		pool[i]:Hide()
		pool[i].point = nil
	end
end

function Way.UpdateMapPins()
	local c = ns.Canvas()
	local n = 0
	if c and ns.db.mapPins and ns.MapShown() then
		local map = ns.MapID()
		for i, p in ipairs(points) do
			if p.map == map then
				n = n + 1
				local f = mapPins[n]
				if not f then
					f = makePin(c, 20)
					mapPins[n] = f
				end
				f.point = p
				f.tex:SetTexture(i == active and STAR or DOT)
				f:SetSize(i == active and 20 or 15, i == active and 20 or 15)
				ns.Place(f, p.x, p.y)
				f:Show()
			end
		end
	end
	hideFrom(mapPins, n + 1)
end

local function nearest()
	local best, bestDist
	for i, p in ipairs(points) do
		local dist = Way.VectorTo(p)
		if dist and (not bestDist or dist < bestDist) then best, bestDist = i, dist end
	end
	return best or (#points > 0 and #points or nil)
end

local function updateMini(facing)
	local n = 0
	if ns.db.miniPins and Minimap and Minimap:IsShown() then
		local radius = ns.ViewRadius()
		local half = (Minimap:GetWidth() or 140) / 2
		local sin, cos
		if facing and GetCVar and GetCVar("rotateMinimap") == "1" then
			sin, cos = math.sin(facing), math.cos(facing)
		end
		for i, p in ipairs(points) do
			local dist, _, dn, dw = Way.VectorTo(p)
			if dist then
				local dx, dy = -dw, -dn
				if sin then dx, dy = dx * cos - dy * sin, dx * sin + dy * cos end
				local len = dist / radius
				local show, alpha = true, 1
				if len > 0.92 then
					if i == active then
						local k = 0.92 / len
						dx, dy = dx * k, dy * k
						alpha = 0.65
					else
						show = false
					end
				end
				if show then
					n = n + 1
					local f = miniPins[n]
					if not f then
						f = makePin(Minimap, 14)
						miniPins[n] = f
					end
					f.point = p
					f.tex:SetTexture(i == active and STAR or DOT)
					f:SetSize(i == active and 14 or 10, i == active and 14 or 10)
					f:SetAlpha(alpha)
					f:ClearAllPoints()
					f:SetPoint("CENTER", Minimap, "CENTER", dx / radius * half, -dy / radius * half)
					f:Show()
				end
			end
		end
	end
	hideFrom(miniPins, n + 1)
end

function Way.Update()
	Way.UpdateMapPins()
	local p = current()
	if not p then
		hideFrom(miniPins, 1)
		if arrow then arrow:Hide() end
		return
	end
	local dist, bearing = Way.Vector()
	if dist and ns.db.arrive and dist <= ARRIVE then
		ns.Print("arrived at " .. p.title)
		if PlaySound and SOUNDKIT and SOUNDKIT.MAP_PING then pcall(PlaySound, SOUNDKIT.MAP_PING) end
		Way.Drop(active, true)
		return
	end
	local facing = GetPlayerFacing and ns.Num(GetPlayerFacing())
	updateMini(facing)
	if not dist or not ns.db.arrow or not facing then
		if arrow then arrow:Hide() end
		return
	end
	if not arrow then buildArrow() end
	local angle = bearing - facing
	if arrow.tex.SetRotation then arrow.tex:SetRotation(angle) end
	local off = math.abs(math.atan2(math.sin(angle), math.cos(angle))) / math.pi
	arrow.tex:SetVertexColor(math.min(1, off * 2), math.min(1, (1 - off) * 2), 0.1)
	arrow.title:SetText(p.title .. (#points > 1 and ("  (" .. active .. "/" .. #points .. ")") or ""))
	local eta = timeText(Way.Eta(dist))
	arrow.dist:SetText(math.floor(dist + 0.5) .. " yd" .. (eta ~= "" and ("   " .. eta) or ""))
	arrow:Show()
end

function Way.Drop(index, auto)
	if not points[index] then return false end
	table.remove(points, index)
	if #points == 0 then
		active = nil
	elseif auto or active == index then
		active = nearest()
	elseif active and active > index then
		active = active - 1
	end
	resetEta()
	save()
	Way.Update()
	ns:Fire("WAYPOINT", current())
	return true
end

local function make(map, x, y, title)
	map, x, y = tonumber(map), tonumber(x), tonumber(y)
	if not map or not x or not y then return nil end
	if x > 1 or y > 1 then x, y = x / 100, y / 100 end
	if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	if type(title) ~= "string" or title == "" then
		local name = ns.MapName(map)
		title = (name ~= "" and (name .. " ") or "") .. ns.Coord(x) .. ", " .. ns.Coord(y)
	end
	local p = { map = map, x = x, y = y, title = title }
	p.north, p.west, p.continent = ns.WorldPos(map, x, y)
	return p
end

function AWay.Add(map, x, y, title)
	local p = make(map, x, y, title)
	if not p then return false end
	if ns.db and ns.db.single then
		for i = #points, 1, -1 do points[i] = nil end
	end
	for i, q in ipairs(points) do
		if q.map == p.map and math.abs(q.x - p.x) < 0.0005 and math.abs(q.y - p.y) < 0.0005 then
			q.title = p.title
			active = i
			resetEta()
			save()
			Way.Update()
			ns:Fire("WAYPOINT", q)
			return i
		end
	end
	points[#points + 1] = p
	active = #points
	resetEta()
	save()
	Way.Update()
	ns:Fire("WAYPOINT", p)
	return active
end

function AWay.Remove(index)
	index = tonumber(index)
	if not index then return false end
	return Way.Drop(index, false)
end

function AWay.Clear()
	for i = #points, 1, -1 do points[i] = nil end
	active = nil
	resetEta()
	save()
	hideFrom(mapPins, 1)
	hideFrom(miniPins, 1)
	if arrow then arrow:Hide() end
	ns:Fire("WAYPOINT", nil)
end

function AWay.Select(index)
	index = tonumber(index)
	if not index or not points[index] then return false end
	active = index
	resetEta()
	save()
	Way.Update()
	ns:Fire("WAYPOINT", current())
	return true
end

function AWay.Next()
	if #points == 0 then return false end
	return AWay.Select((active or 0) % #points + 1)
end

function AWay.Get()
	local p = current()
	if not p then return nil end
	return p.map, p.x, p.y, p.title
end

function AWay.List()
	local out = {}
	for i, p in ipairs(points) do
		out[i] = { map = p.map, x = p.x, y = p.y, title = p.title, active = i == active }
	end
	return out
end

function AWay.Count()
	return #points
end

function Way.Parse(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" then return nil end
	local lower = msg:lower()
	if lower == "clear" or lower == "reset" then return "clear" end
	if lower == "list" then return "list" end
	if lower == "next" then return "next" end
	local n = lower:match("^remove%s+(%d+)$") or lower:match("^del%s+(%d+)$")
	if n then return "remove", tonumber(n) end
	local zone, xs, ys, rest = msg:match("^(.-)%s*(%d+%.?%d*)[%s,]+(%d+%.?%d*)%s*(.*)$")
	if not xs then return nil end
	local x, y = tonumber(xs), tonumber(ys)
	if not x or not y or x > 100 or y > 100 then return nil end
	local map
	if zone and zone ~= "" then
		map = ns.FindZone(zone)
		if not map then return nil, "unknown zone: " .. zone end
	else
		map = ns.MapID()
		if not map or not ns.MapShown() then map = ns.PlayerMap() or map end
	end
	if not map then return nil, "no map to place it on" end
	return map, x / 100, y / 100, rest ~= "" and rest or nil
end

SLASH_AWAY1 = "/way"
SLASH_AWAY2 = "/waypoint"
SlashCmdList["AWAY"] = function(msg)
	local map, x, y, title = Way.Parse(msg)
	if map == "clear" then
		AWay.Clear()
		ns.Print("waypoints cleared")
	elseif map == "list" then
		if #points == 0 then ns.Print("no waypoints") end
		for i, p in ipairs(points) do
			ns.Print(i .. (i == active and " > " or "   ") .. p.title .. "  (" .. ns.MapName(p.map) .. " " .. ns.Coord(p.x) .. ", " .. ns.Coord(p.y) .. ")")
		end
	elseif map == "next" then
		AWay.Next()
	elseif map == "remove" then
		if not AWay.Remove(x) then ns.Print("no waypoint " .. tostring(x)) end
	elseif map then
		local i = AWay.Add(map, x, y, title)
		if i then ns.Print("waypoint: " .. points[i].title) end
	else
		ns.Print(x or "usage: /way [zone] x y [name], /way list, /way remove N, /way next, /way clear")
	end
end

function Way.MapClick(button)
	if AMap then return false end
	if button ~= "LeftButton" or not IsControlKeyDown or not IsControlKeyDown() then return false end
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if not sc or not sc.GetNormalizedCursorPosition then return false end
	local ok, x, y = pcall(sc.GetNormalizedCursorPosition, sc)
	x, y = ok and ns.Num(x), ok and ns.Num(y)
	local map = ns.MapID()
	if not x or not y or not map or x < 0 or x > 1 or y < 0 or y > 1 then return false end
	return AWay.Add(map, x, y) and true or false
end

ns:Listen("LOGIN", function()
	for _, s in ipairs(ns.chardb.list or {}) do
		local p = make(s[1], s[2], s[3], s[4])
		if p then points[#points + 1] = p end
	end
	active = tonumber(ns.chardb.active)
	if not points[active or 0] then active = #points > 0 and #points or nil end
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if sc and sc.HookScript and not AMap then
		pcall(sc.HookScript, sc, "OnMouseUp", function(_, button) Way.MapClick(button) end)
	end
	local ticker = CreateFrame("Frame")
	local elapsed = 0
	ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 0.04 then return end
		elapsed = 0
		if #points > 0 then Way.Update() end
	end)
	Way.Update()
end)

ns:Listen("OPTIONS", function()
	if ns.db.single and #points > 1 then
		local keep = current() or points[#points]
		for i = #points, 1, -1 do points[i] = nil end
		points[1] = keep
		active = 1
		save()
	end
	Way.Update()
end)

ns:Listen("LAYOUT_RESET", function()
	if arrow then arrow:Restore() end
end)
