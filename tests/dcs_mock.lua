--[[
	Minimal DCS World Simulator Scripting Engine (SSE) mock.

	Just enough of the DCS API for MIST to load, build its databases,
	spawn/kill groups, and run its scheduler outside the game, so the
	library can be regression-tested and benchmarked with a plain
	Lua 5.1 interpreter (the same Lua version DCS embeds).

	Usage (from the repository root):
		lua5.1 tests/run_tests.lua
		lua5.1 tests/bench.lua
]]

local M = {}

-- ---------------------------------------------------------------------------
-- time / scheduler
-- ---------------------------------------------------------------------------
local now = 0
local START_ABS = 43200 -- mission starts at 12:00:00
local timerQueue = {}   -- { {f, arg, t, id} }
local timerId = 0

timer = {}
function timer.getTime() return now end
function timer.getAbsTime() return now + START_ABS end
function timer.getTime0() return START_ABS end
function timer.scheduleFunction(f, arg, t)
	timerId = timerId + 1
	timerQueue[#timerQueue + 1] = {f = f, arg = arg, t = t, id = timerId}
	return timerId
end
function timer.removeFunction(id)
	for i = #timerQueue, 1, -1 do
		if timerQueue[i].id == id then table.remove(timerQueue, i) end
	end
end
function timer.setFunctionTime(id, t)
	for i = 1, #timerQueue do
		if timerQueue[i].id == id then timerQueue[i].t = t end
	end
end

--- Advance simulated time by dt seconds, in steps of `step` (default 0.01),
-- running every DCS-timer function that comes due.
function M.advance(dt, step)
	step = step or 0.01
	local target = now + dt
	while now < target - 1e-9 do
		now = now + step
		-- run everything due, earliest first; functions may schedule more
		while true do
			local bi, bt
			for i = 1, #timerQueue do
				local e = timerQueue[i]
				if e.t <= now + 1e-9 and (not bt or e.t < bt) then bi, bt = i, e.t end
			end
			if not bi then break end
			local e = table.remove(timerQueue, bi)
			local ok, ret = pcall(e.f, e.arg, now)
			if not ok then
				M.errors[#M.errors + 1] = 'timer: ' .. tostring(ret)
			elseif type(ret) == 'number' then
				timerQueue[#timerQueue + 1] = {f = e.f, arg = e.arg, t = ret, id = e.id}
			end
		end
	end
	now = target
end

function M.getTime() return now end

-- ---------------------------------------------------------------------------
-- env / logging
-- ---------------------------------------------------------------------------
M.log = {}
M.errors = {}
M.quiet = true
local function logLine(level, s)
	M.log[#M.log + 1] = level .. ': ' .. tostring(s)
	if not M.quiet then print(level .. ': ' .. tostring(s)) end
end

env = {}
function env.info(s) logLine('INFO', s) end
function env.warning(s) logLine('WARNING', s) end
function env.error(s) logLine('ERROR', s) M.errors[#M.errors + 1] = tostring(s) end
function env.getValueDictByKey(k) return k end
env.warehouses = {}

-- ---------------------------------------------------------------------------
-- enums
-- ---------------------------------------------------------------------------
coalition = {side = {NEUTRAL = 0, RED = 1, BLUE = 2}}

country = {
	id = {RUSSIA = 0, UKRAINE = 1, USA = 2, TURKEY = 3, UK = 4, FRANCE = 5, GERMANY = 6, CANADA = 8,
		SPAIN = 9, THE_NETHERLANDS = 10, BELGIUM = 11, NORWAY = 12, DENMARK = 13, ISRAEL = 15,
		GEORGIA = 16, INSURGENTS = 17, ABKHAZIA = 18, SOUTH_OSETIA = 19, ITALY = 20,
		AUSTRALIA = 21, SWITZERLAND = 22, AUSTRIA = 23, BELARUS = 24, BULGARIA = 25,
		CHEZH_REPUBLIC = 26, CHINA = 27, CROATIA = 28, EGYPT = 29, FINLAND = 30, GREECE = 31,
		HUNGARY = 32, INDIA = 33, IRAN = 34, IRAQ = 35, JAPAN = 36, KAZAKHSTAN = 37,
		NORTH_KOREA = 38, PAKISTAN = 39, POLAND = 40, ROMANIA = 41, SAUDI_ARABIA = 42,
		SERBIA = 43, SLOVAKIA = 44, SOUTH_KOREA = 45, SWEDEN = 46, SYRIA = 47, YEMEN = 48,
		VIETNAM = 49, VENEZUELA = 50, TUNISIA = 51, THAILAND = 52, SUDAN = 53, PHILIPPINES = 54,
		MOROCCO = 55, MEXICO = 56, MALAYSIA = 57, LIBYA = 58, JORDAN = 59, INDONESIA = 60,
		HONDURAS = 61, ETHIOPIA = 62, CHILE = 63, BRAZIL = 64, BAHRAIN = 65, THIRDREICH = 66,
		YUGOSLAVIA = 67, USSR = 68, ITALIAN_SOCIAL_REPUBLIC = 69, ALGERIA = 70, KUWAIT = 71,
		QATAR = 72, OMAN = 73, UNITED_ARAB_EMIRATES = 74, SOUTH_AFRICA = 75, CUBA = 76,
		PORTUGAL = 77, GDR = 78, LEBANON = 79, CJTF_BLUE = 80, CJTF_RED = 81,
		UN_PEACEKEEPERS = 82, ARGENTINA = 83, CYPRUS = 84, SLOVENIA = 85, BOLIVIA = 86,
		GHANA = 87, NIGERIA = 88, PERU = 89, ECUADOR = 90},
	name = {}, names = {},
}
for n, i in pairs(country.id) do country.name[i] = n; country.names[i] = n end
country.by_idx = {}
country.by_country = {}

local countryCoalition = {}
function coalition.getCountryCoalition(cid) return countryCoalition[cid] or 0 end

Object = {Category = {UNIT = 1, WEAPON = 2, STATIC = 3, BASE = 4, SCENERY = 5, CARGO = 6}}
Unit = {Category = {AIRPLANE = 0, HELICOPTER = 1, GROUND_UNIT = 2, SHIP = 3, STRUCTURE = 4}}
Group = {Category = {AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3, TRAIN = 4}}
StaticObject = {}
Airbase = {Category = {AIRDROME = 0, HELIPAD = 1, SHIP = 2}}
Controller = {}
AI = {Task = {}, Option = {Air = {id = {}, val = {}}, Ground = {id = {}, val = {}}, Naval = {id = {}, val = {}}}}
setmetatable(Unit, {__index = Object})
setmetatable(StaticObject, {__index = Object})

world = {eventHandlers = {}, event = {
	S_EVENT_INVALID = 0, S_EVENT_SHOT = 1, S_EVENT_HIT = 2, S_EVENT_TAKEOFF = 3, S_EVENT_LAND = 4,
	S_EVENT_CRASH = 5, S_EVENT_EJECTION = 6, S_EVENT_REFUELING = 7, S_EVENT_DEAD = 8,
	S_EVENT_PILOT_DEAD = 9, S_EVENT_BASE_CAPTURED = 10, S_EVENT_MISSION_START = 11,
	S_EVENT_MISSION_END = 12, S_EVENT_TOOK_CONTROL = 13, S_EVENT_REFUELING_STOP = 14,
	S_EVENT_BIRTH = 15, S_EVENT_HUMAN_FAILURE = 16, S_EVENT_ENGINE_STARTUP = 18,
	S_EVENT_ENGINE_SHUTDOWN = 19, S_EVENT_PLAYER_ENTER_UNIT = 20, S_EVENT_PLAYER_LEAVE_UNIT = 21,
	S_EVENT_UNIT_LOST = 30, S_EVENT_MARK_ADDED = 25, S_EVENT_MARK_CHANGE = 26, S_EVENT_MARK_REMOVED = 27,
}}
local handlerSeq = 0
function world.addEventHandler(h)
	handlerSeq = handlerSeq + 1
	world.eventHandlers[handlerSeq] = h
end
function world.removeEventHandler(h)
	for k, v in pairs(world.eventHandlers) do if v == h then world.eventHandlers[k] = nil end end
end
function world.getAirbases() return {} end
function world.searchObjects() return {} end
function world.getMarkPanels() return {} end

local function fire(event)
	event.time = now
	-- deterministic order
	local keys = {}
	for k in pairs(world.eventHandlers) do keys[#keys + 1] = k end
	table.sort(keys)
	for i = 1, #keys do
		local h = world.eventHandlers[keys[i]]
		if h then
			local ok, err = pcall(h.onEvent, h, event)
			if not ok then M.errors[#M.errors + 1] = 'event: ' .. tostring(err) end
		end
	end
end
M.fire = fire

-- ---------------------------------------------------------------------------
-- trigger / land / coord / atmosphere / misc
-- ---------------------------------------------------------------------------
local flags = {}
M.flags = flags
trigger = {misc = {}, action = {}, smokeColor = {}, flareColor = {}}
function trigger.misc.getUserFlag(f) local v = flags[tostring(f)]; if v == nil then return 0 end; return v end
function trigger.action.setUserFlag(f, v)
	if v == true then v = 1 elseif v == false then v = 0 end
	flags[tostring(f)] = v
end
function trigger.misc.getZone(name) return nil end
M.messages = {}
setmetatable(trigger.action, {__index = function(t, k)
	return function(...) M.messages[#M.messages + 1] = k end
end})

land = {SurfaceType = {LAND = 1, SHALLOW_WATER = 2, WATER = 3, ROAD = 4, RUNWAY = 5}}
M.GROUND_HEIGHT = 100 -- flat terrain 100 m above sea level
function land.getHeight(p) return M.GROUND_HEIGHT end
function land.getSurfaceType() return 1 end
function land.isVisible() return true end
function land.getClosestPointOnRoads(t, x, y) return x, y end
function land.findPathOnRoads() return {} end

coord = {}
function coord.LOtoLL(p) return p.x / 111000, p.z / 111000, p.y end
function coord.LLtoLO(lat, lon, alt) return {x = lat * 111000, y = alt or 0, z = lon * 111000} end
function coord.LLtoMGRS(lat, lon) return {UTMZone = '37T', MGRSDigraph = 'GG', Easting = 12345, Northing = 67890} end

atmosphere = {}
function atmosphere.getWind() return {x = 0, y = 0, z = 0} end
function atmosphere.getWindWithTurbulence() return {x = 0, y = 0, z = 0} end
function atmosphere.getTemperatureAndPressure() return 288, 101325 end

missionCommands = setmetatable({}, {__index = function() return function() return {} end end})
coalition.getPlayers = function() return {} end
coalition.getAirbases = function() return {} end

-- ---------------------------------------------------------------------------
-- object world
-- ---------------------------------------------------------------------------
local objects = {}      -- runtime id -> state
local unitsByName = {}  -- name -> state
local groupsByName = {}
local staticsByName = {}
local nextRuntimeId = 16777000
M.objects = objects

local unitMT = {__index = Unit}
local groupMT = {__index = Group}
local staticMT = {__index = StaticObject}

local function S(obj) return obj and objects[obj.id_] end

-- Object
function Object.isExist(o) local s = S(o); return s ~= nil and s.alive == true end
function Object.getName(o) return S(o).name end
function Object.getTypeName(o) return S(o).type end
function Object.getCategory(o) return S(o).objCat end
function Object.getPoint(o) local p = S(o).p; return {x = p.x, y = p.y, z = p.z} end
function Object.getPosition(o)
	local s = S(o)
	if not s then return nil end
	local p = s.p
	return {p = {x = p.x, y = p.y, z = p.z}, x = {x = 1, y = 0, z = 0}, y = {x = 0, y = 1, z = 0}, z = {x = 0, y = 0, z = 1}}
end
function Object.getVelocity(o) local v = S(o).v; return {x = v.x, y = v.y, z = v.z} end
function Object.getDesc(o) return {category = S(o).unitCat, life = 1, typeName = S(o).type} end
function Object.inAir() return false end

-- Unit
function Unit.getByName(n) local s = unitsByName[n]; if s and s.alive then return s.obj end end
function Unit.getID(o) return S(o).dcsId end
function Unit.getGroup(o) local s = S(o); return s and s.group and s.group.obj end
function Unit.getCountry(o) return S(o).countryId end
function Unit.getCoalition(o) return S(o).coa end
function Unit.getPlayerName(o) return S(o).player end
function Unit.isActive(o) return true end
function Unit.getLife(o) return 1 end
function Unit.getLife0(o) return 1 end
function Unit.getFuel() return 1 end
function Unit.getNumber(o) return S(o).index end
function Unit.getCallsign(o) return S(o).name end
function Unit.getController() return {setTask = function() end, setOption = function() end, setCommand = function() end} end

-- Group
function Group.getByName(n) local s = groupsByName[n]; if s and s.alive then return s.obj end end
function Group.isExist(o) local s = S(o); return s ~= nil and s.alive == true end
function Group.getName(o) return S(o).name end
function Group.getID(o) return S(o).dcsId end
function Group.getCategory(o) return S(o).unitCat end
function Group.getCoalition(o) return S(o).coa end
function Group.getUnits(o)
	local r = {}
	for _, u in ipairs(S(o).units) do if u.alive then r[#r + 1] = u.obj end end
	return r
end
function Group.getUnit(o, i) local u = S(o).units[i]; if u and u.alive then return u.obj end end
function Group.getSize(o) local n = 0; for _, u in ipairs(S(o).units) do if u.alive then n = n + 1 end end; return n end
function Group.getInitialSize(o) return #S(o).units end
function Group.getController() return Unit.getController() end
function Group.activate() end
function Group.destroy(o) for _, u in ipairs(S(o).units) do u.alive = false end; S(o).alive = false end

-- StaticObject
function StaticObject.getByName(n) local s = staticsByName[n]; if s and s.alive then return s.obj end end
function StaticObject.getID(o) return S(o).dcsId end
function StaticObject.getCountry(o) return S(o).countryId end
function StaticObject.getCoalition(o) return S(o).coa end
function StaticObject.getCargoDisplayName() return nil end
function StaticObject.getCategory(o) return S(o).unitCat end
function StaticObject.destroy(o) S(o).alive = false end

local catMap = {plane = 0, helicopter = 1, vehicle = 2, ship = 3}

local function newState(mt, st)
	nextRuntimeId = nextRuntimeId + 1
	st.obj = setmetatable({id_ = nextRuntimeId}, mt)
	st.alive = true
	objects[nextRuntimeId] = st
	return st
end

--- Create a live group in the simulated world (not via MIST).
local function createGroup(countryId, cat, g, emitBirth)
	local coa = countryCoalition[countryId] or 0
	local gs = newState(groupMT, {name = g.name, dcsId = g.groupId, unitCat = cat, coa = coa, units = {}})
	gs.group = gs
	groupsByName[g.name] = gs
	for i, ud in ipairs(g.units) do
		local us = newState(unitMT, {
			name = ud.name, dcsId = ud.unitId, type = ud.type, objCat = 1, unitCat = cat,
			countryId = countryId, coa = coa, group = gs, index = i,
			-- RADIO (AGL) altitudes are placed above the mock's 100 m terrain
			p = {x = ud.x, y = (ud.alt or 0) + ((ud.alt_type == 'RADIO') and M.GROUND_HEIGHT or 0), z = ud.y},
			v = {x = 0, y = 0, z = 0},
		})
		gs.units[i] = us
		unitsByName[ud.name] = us
	end
	if emitBirth then
		for _, us in ipairs(gs.units) do
			fire({id = world.event.S_EVENT_BIRTH, initiator = us.obj})
		end
	end
	return gs
end

local function createStatic(countryId, s, emitBirth)
	local coa = countryCoalition[countryId] or 0
	local st = newState(staticMT, {name = s.name, dcsId = s.unitId, type = s.type, objCat = 3,
		unitCat = 4, countryId = countryId, coa = coa, p = {x = s.x, y = 0, z = s.y}, v = {x = 0, y = 0, z = 0}})
	staticsByName[s.name] = st
	if emitBirth then fire({id = world.event.S_EVENT_BIRTH, initiator = st.obj}) end
	return st
end

local dcsIdSeq = 1000000
function coalition.addGroup(countryId, cat, g)
	-- DCS assigns its own ids when missing
	if not g.groupId then dcsIdSeq = dcsIdSeq + 1; g.groupId = dcsIdSeq end
	for _, u in ipairs(g.units) do
		if not u.unitId then dcsIdSeq = dcsIdSeq + 1; u.unitId = dcsIdSeq end
	end
	local gs = createGroup(countryId, cat, g, true)
	M.spawned = (M.spawned or 0) + 1
	return gs.obj
end
coalition.add = coalition.addGroup

function coalition.addStaticObject(countryId, s)
	if not s.unitId then dcsIdSeq = dcsIdSeq + 1; s.unitId = dcsIdSeq end
	return createStatic(countryId, s, true).obj
end

function coalition.getGroups(coa, cat)
	local r = {}
	local names = {}
	for n, gs in pairs(groupsByName) do
		if gs.alive and gs.coa == coa and (cat == nil or cat == gs.unitCat) then names[#names + 1] = n end
	end
	table.sort(names)
	for i = 1, #names do r[i] = groupsByName[names[i]].obj end
	return r
end

function coalition.getStaticObjects(coa)
	local r, names = {}, {}
	for n, st in pairs(staticsByName) do if st.alive and st.coa == coa then names[#names + 1] = n end end
	table.sort(names)
	for i = 1, #names do r[i] = staticsByName[names[i]].obj end
	return r
end

--- Kill a unit by name and fire DEAD (and group-empty bookkeeping).
function M.killUnit(name)
	local us = unitsByName[name]
	if not us or not us.alive then return false end
	us.alive = false
	fire({id = world.event.S_EVENT_DEAD, initiator = us.obj})
	local any = false
	for _, u in ipairs(us.group.units) do if u.alive then any = true end end
	if not any then us.group.alive = false end
	return true
end

--- Move a unit (so position tracking can be observed).
function M.moveUnit(name, dx, dz)
	local us = unitsByName[name]
	us.p.x = us.p.x + dx
	us.p.z = us.p.z + dz
end

-- ---------------------------------------------------------------------------
-- mission builder
-- ---------------------------------------------------------------------------
--- Builds env.mission and the matching live world.
-- opts.groups: number of ground groups per coalition (default 10)
-- opts.unitsPerGroup: units per group (default 4)
-- opts.planes: number of plane groups per coalition (default 2)
-- opts.statics: statics per coalition (default 3)
-- opts.zones: number of trigger zones (default 4)
function M.buildMission(opts)
	opts = opts or {}
	local nG = opts.groups or 10
	local nU = opts.unitsPerGroup or 4
	local nP = opts.planes or 2
	local nS = opts.statics or 3
	local nZ = opts.zones or 4
	local gid, uid = 0, 0
	local mission = {
		start_time = 28800, theatre = 'Caucasus', version = 21, resourceCounter = {},
		coalition = {}, triggers = {zones = {}}, drawings = {layers = {}},
	}
	local defs = {
		{coa = 'blue', cid = country.id.USA, side = 2},
		{coa = 'red', cid = country.id.RUSSIA, side = 1},
	}
	countryCoalition[country.id.USA] = 2
	countryCoalition[country.id.RUSSIA] = 1
	countryCoalition[country.id.UKRAINE] = 2
	countryCoalition[country.id.GEORGIA] = 2
	countryCoalition[country.id.INSURGENTS] = 1
	for _, d in ipairs(defs) do
		local cdata = {id = d.cid, name = country.name[d.cid], vehicle = {group = {}}, plane = {group = {}}, static = {group = {}}}
		for g = 1, nG do
			gid = gid + 1
			local grp = {name = d.coa .. ' armor ' .. g, groupId = gid, start_time = 0, task = 'Ground Nothing', hidden = false, units = {},
				route = {points = {{x = g * 1000, y = 0}}}}
			for u = 1, nU do
				uid = uid + 1
				grp.units[u] = {name = d.coa .. ' armor ' .. g .. '-' .. u, unitId = uid, type = 'T-72B',
					skill = 'Average', x = g * 1000 + u * 10, y = (d.side == 2 and 1 or -1) * 5000 + u * 10, heading = 0, playerCanDrive = true}
			end
			cdata.vehicle.group[g] = grp
		end
		for g = 1, nP do
			gid = gid + 1
			local grp = {name = d.coa .. ' cap ' .. g, groupId = gid, start_time = 0, task = 'CAP', hidden = false, units = {},
				route = {points = {{x = 0, y = 0, alt = 5000}}}}
			for u = 1, 2 do
				uid = uid + 1
				grp.units[u] = {name = d.coa .. ' cap ' .. g .. '-' .. u, unitId = uid, type = 'F-15C',
					skill = (g == 1 and u == 1) and 'Client' or 'High', x = g * 2000, y = u * 100, alt = 5000, alt_type = 'BARO',
					speed = 200, heading = 1, callsign = {1, 1, u, name = 'Enfield1' .. u}, payload = {pylons = {}, fuel = 6000}}
			end
			cdata.plane.group[g] = grp
		end
		for s = 1, nS do
			gid = gid + 1
			uid = uid + 1
			cdata.static.group[s] = {name = d.coa .. ' static ' .. s, groupId = gid, units = {
				{name = d.coa .. ' static ' .. s, unitId = uid, type = 'Tech combine', category = 'Fortifications',
					x = s * 300, y = (d.side == 2 and 1 or -1) * 9000, heading = 0}}}
		end
		mission.coalition[d.coa] = {bullseye = {x = 0, y = 0}, nav_points = {}, country = {cdata}}
	end
	mission.coalition.neutrals = {bullseye = {x = 0, y = 0}, nav_points = {}, country = {}}
	for z = 1, nZ do
		mission.triggers.zones[z] = {name = 'zone ' .. z, x = z * 1000, y = 5000, radius = 3000, zoneId = z, hidden = false, properties = {}}
	end
	-- one quad zone
	mission.triggers.zones[nZ + 1] = {name = 'quad', x = 0, y = 0, radius = 0, zoneId = nZ + 1, type = 2,
		verticies = {{x = -10000, y = -10000}, {x = 10000, y = -10000}, {x = 10000, y = 10000}, {x = -10000, y = 10000}}, properties = {}}
	env.mission = mission

	-- live world mirrors the mission
	for coaName, cd in pairs(mission.coalition) do
		for _, c in ipairs(cd.country) do
			for catName, cat in pairs({vehicle = 2, plane = 0}) do
				for _, g in ipairs(c[catName].group) do createGroup(c.id, cat, g, false) end
			end
			for _, sg in ipairs(c.static.group) do createStatic(c.id, sg.units[1], false) end
		end
	end
	return mission
end

return M
