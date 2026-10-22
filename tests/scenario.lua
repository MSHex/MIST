--[[
	Deterministic MIST behaviour trace.

	Loads a MIST build into the DCS mock, drives a scripted mission
	(scheduler, flag functions, spawns, deaths, zone checks, DB queries)
	and prints a stable, sorted text trace. Running it against two MIST
	builds and diffing the output shows exactly which observable
	behaviours changed.

		lua5.1 tests/scenario.lua mist.lua > new.txt
		lua5.1 tests/scenario.lua old_mist.lua > old.txt
		diff old.txt new.txt
]]

local mistPath = arg[1] or 'mist.lua'
local here = (arg[0]:match('^(.*)[/\\]') or '.') .. '/'
local dcs = dofile(here .. 'dcs_mock.lua')

dcs.buildMission({groups = 6, unitsPerGroup = 3, planes = 2, statics = 2, zones = 3})
dofile(mistPath)

local out = {}
local function p(...)
	local t = {}
	for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end
	out[#out + 1] = table.concat(t, ' ')
end

-- stable serializer: sorted keys, functions/userdata collapsed, runtime objects by id_
local function ser(v, depth, seen)
	depth = depth or 0
	seen = seen or {}
	local tv = type(v)
	if tv == 'number' then
		if v == math.floor(v) then return string.format('%d', v) end
		return string.format('%.3f', v)
	elseif tv == 'string' then return string.format('%q', v)
	elseif tv ~= 'table' then return tv == 'boolean' and tostring(v) or ('<' .. tv .. '>')
	end
	if v.id_ and getmetatable(v) then return '<obj>' end
	if seen[v] then return '<cycle>' end
	if depth > 8 then return '<deep>' end
	seen[v] = true
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then return ta < tb end
		if ta == 'number' or ta == 'string' then return a < b end
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = '[' .. ser(k, depth + 1, seen) .. ']=' .. ser(v[k], depth + 1, seen)
	end
	seen[v] = nil
	return '{' .. table.concat(parts, ',') .. '}'
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function r2(x) return math.floor(x * 100 + 0.5) / 100 end

local function dbSummary(tag)
	local DB = mist.DBs
	p('[db ' .. tag .. ']',
		'unitsByName', count(DB.unitsByName), 'unitsById', count(DB.unitsById),
		'unitsByNum', #DB.unitsByNum, 'groupsByName', count(DB.groupsByName),
		'groupsById', count(DB.groupsById), 'dynGroupsAdded', #DB.dynGroupsAdded,
		'alive', count(DB.aliveUnits), 'removedAlive', count(DB.removedAliveUnits),
		'dead', count(DB.deadObjects))
	local cats = {}
	for c, l in pairs(DB.unitsByCat) do cats[#cats + 1] = c .. '=' .. #l end
	table.sort(cats)
	p('  byCat', table.concat(cats, ' '))
end

-- ---------------------------------------------------------------------------
p('version', mist.majorVersion, mist.minorVersion)
dbSummary('init')
p('MEunitsByName', count(mist.DBs.MEunitsByName), 'zones', count(mist.DBs.zonesByName), #mist.DBs.zonesByNum)
p('unit blue armor 1-1', ser(mist.DBs.unitsByName['blue armor 1-1']))
p('group blue cap 1', ser(mist.DBs.groupsByName['blue cap 1']))
p('humans', ser(mist.DBs.humansByName))
p('zone 1', ser(mist.DBs.zonesByName['zone 1']))
p('quad', ser(mist.DBs.zonesByName['quad']))
p('callsign NATO keys', ser((function() local k = {}; for n in pairs(mist.DBs.const.callsigns.NATO) do k[#k + 1] = n end; table.sort(k); return k end)()))
p('nextIds', mist.nextUnitId, mist.nextGroupId)

dcs.advance(3)
dbSummary('t3')
local a = mist.DBs.aliveUnits
local ids = {}
for id in pairs(a) do ids[#ids + 1] = id end
table.sort(ids)
local first = a[ids[1]]
p('alive first', first.unitName, ser(first.pos), first.unit ~= nil, first.groupName, first.dbNum)

-- ---------------------------------------------------------------------------
-- scheduler semantics
local trace = {}
local function rec(name) return function(...)
	local args = {...}
	trace[#trace + 1] = string.format('%.2f %s %s', r2(timer.getTime()), name, ser(args))
end end
local t0 = timer.getTime()
mist.scheduleFunction(rec('once-a'), {1, 2}, t0 + 0.5)
mist.scheduleFunction(rec('once-b'), {'x'}, t0 + 0.5)
mist.scheduleFunction(rec('once-c'), nil, t0 + 0.2)
local repId = mist.scheduleFunction(rec('rep-1s'), {}, t0 + 1, 1)
mist.scheduleFunction(rec('rep-0.5s-stop3'), {}, t0 + 0.3, 0.5, t0 + 3)
local killId = mist.scheduleFunction(rec('never'), {}, t0 + 2)
p('remove never', mist.removeFunction(killId))
p('remove bogus', mist.removeFunction(999999))
mist.scheduleFunction(function() error('boom') end, {}, t0 + 0.7)
mist.scheduleFunction(function() trace[#trace + 1] = 'nil-holes'; return end, {nil, 2}, t0 + 0.8)
-- a task scheduling another task while running
mist.scheduleFunction(function()
	trace[#trace + 1] = string.format('%.2f outer', r2(timer.getTime()))
	mist.scheduleFunction(rec('inner'), {}, timer.getTime())
end, {}, t0 + 1.5)
-- a repeating task removing itself
local selfId
selfId = mist.scheduleFunction(function()
	trace[#trace + 1] = string.format('%.2f self-remove', r2(timer.getTime()))
	mist.removeFunction(selfId)
end, {}, t0 + 0.4, 0.1)
dcs.advance(4)
p('remove rep', mist.removeFunction(repId))
dcs.advance(2)
for _, l in ipairs(trace) do
	-- times are relative to t0 so the trace is independent of init timing
	local tt, rest = l:match('^([%d%.]+) (.*)$')
	if tt then p('sched', string.format('%.2f', r2(tonumber(tt) - t0)), rest) else p('sched', l) end
end

-- ---------------------------------------------------------------------------
-- flag functions + spawn
mist.flagFunc.units_in_zones({units = {'[blue][vehicle]'}, zones = {'zone 1'}, flag = 100, toggle = true, interval = 1})
mist.flagFunc.units_in_polygon({units = {'[red][vehicle]'}, zone = mist.DBs.zonesByName['quad'].verticies, flag = 101, toggle = true, interval = 1})
mist.flagFunc.group_dead({groupName = 'red armor 2', flag = 102, interval = 1})
dcs.advance(2)
p('flags after 2s', trigger.misc.getUserFlag(100), trigger.misc.getUserFlag(101), trigger.misc.getUserFlag(102))

local newGroup = mist.dynAdd({
	country = 'USA', category = 'vehicle', name = 'reinforcements',
	units = {
		{type = 'M-1 Abrams', x = 1000, y = 5000, name = 'reinf-1', skill = 'Excellent'},
		{type = 'M-1 Abrams', x = 1010, y = 5010, name = 'reinf-2'},
	},
})
p('dynAdd ret', newGroup and newGroup.name, newGroup and newGroup.groupId, newGroup and #newGroup.units)
local plane = mist.dynAdd({
	country = 2, category = 'AIRPLANE',
	units = {{type = 'F-16C_50', x = 1, y = 2, alt = 3000, alt_type = 'RADIO'}},
})
p('dynAdd plane', plane.name, plane.units[1].name, plane.units[1].alt, plane.units[1].alt_type, plane.units[1].speed)
local st = mist.dynAddStatic({country = 'USA', category = 'Fortifications', type = 'Tech combine', x = 100, y = 200, name = 'my static'})
p('dynAddStatic', st and st.name, st and st.groupId ~= nil)
local bad = mist.dynAdd({country = 'NOWHERE', category = 'vehicle', units = {{type = 'x', x = 0, y = 0}}})
p('dynAdd bad country', bad)
local lastBefore = mist.getLastDBUpdateTime()
dcs.advance(5)
p('lastDBUpdate advanced', mist.getLastDBUpdateTime() > lastBefore)
dbSummary('after spawn')
p('reinf-1', ser(mist.DBs.unitsByName['reinf-1']))
p('reinforcements', ser(mist.DBs.groupsByName['reinforcements']))
p('static', ser(mist.DBs.unitsByName['my static']))
p('plane unit', ser(mist.DBs.unitsByName[plane.units[1].name]))
p('flags after spawn', trigger.misc.getUserFlag(100), trigger.misc.getUserFlag(101))
p('in zone count', #mist.getUnitsInZones(mist.makeUnitTable({'[blue][vehicle]'}), {'zone 1'}))

-- ---------------------------------------------------------------------------
-- deaths
for u = 1, 3 do dcs.killUnit('red armor 2-' .. u) end
dcs.killUnit('reinf-2')
dcs.advance(3)
dbSummary('after deaths')
p('flag group_dead', trigger.misc.getUserFlag(102))
local deadNames = {}
for k, v in pairs(mist.DBs.deadObjects) do deadNames[#deadNames + 1] = tostring(v.objectData and v.objectData.unitName) .. ':' .. tostring(v.objectType) end
table.sort(deadNames)
p('dead', table.concat(deadNames, ', '))

-- ---------------------------------------------------------------------------
-- utilities
p('pip in', mist.pointInPolygon({x = 0, y = 0, z = 0}, mist.DBs.zonesByName['quad'].verticies))
p('pip out', mist.pointInPolygon({x = 20000, y = 0, z = 0}, mist.DBs.zonesByName['quad'].verticies))
p('pip v2', mist.pointInPolygon({x = 5, y = 5}, {{x = 0, y = 0}, {x = 10, y = 0}, {x = 10, y = 10}, {x = 0, y = 10}}))
p('pip v3poly', mist.pointInPolygon({x = 5, y = 0, z = 5}, {{x = 0, y = 0, z = 0}, {x = 10, y = 0, z = 0}, {x = 10, y = 0, z = 10}, {x = 0, y = 0, z = 10}}))
p('pip maxalt', mist.pointInPolygon({x = 5, y = 500, z = 5}, {{x = 0, y = 0}, {x = 10, y = 0}, {x = 10, y = 10}}, 100))
local poly = {{x = 0, y = 0}, {x = 10, y = 0}, {x = 10, y = 10}}
mist.pointInPolygon({x = 1, y = 1}, poly)
p('pip poly untouched', ser(poly))
p('stringMatch', mist.stringMatch('Blue-Armor (1)', 'bluearmor1'), mist.stringMatch('a.b', 'A B', true), mist.stringMatch('x', 'y'))
p('stringCondense', mist.stringCondense('a-b(c)d_e[f]g.h#i j{k}l$m%n?o+p^q'))
p('nextUnitId', mist.getNextUnitId(), mist.getNextGroupId())
p('makeUnitTable blue all', #mist.makeUnitTable({'[blue][all]'}))
p('makeUnitTable red plane', ser(mist.makeUnitTable({'[red][plane]'})))
p('makeUnitTable g', ser(mist.makeUnitTable({'[g]blue cap 1', '[-u]blue cap 1-2'})))
p('getUnitsInPolygon', #mist.getUnitsInPolygon(mist.makeUnitTable({'[all]'}), mist.DBs.zonesByName['quad'].verticies))
p('groupData', ser(mist.getGroupData('blue armor 1')))
p('heading', r2(mist.getHeading(Unit.getByName('blue armor 1-1'))))

-- ---------------------------------------------------------------------------
-- respawn / clone
local rs = mist.respawnGroup('blue armor 3', true)
p('respawn', rs and rs.name or tostring(rs))
local cl = mist.cloneGroup('blue armor 4', true)
p('clone', cl and cl.name or tostring(cl))
dcs.advance(5)
dbSummary('after respawn/clone')
p('blue armor 3', ser(mist.DBs.groupsByName['blue armor 3']))

p('errors', #dcs.errors)
for _, e in ipairs(dcs.errors) do p("  err", (e:gsub("|%d+:", "|N:"))) end
local errLines = {}
for _, l in ipairs(dcs.log) do if l:find('^ERROR') or l:find('^WARNING') then errLines[#errLines + 1] = l end end
p('log warn/error lines', #errLines)
for _, l in ipairs(errLines) do p('  log', (l:gsub('|%d+:', '|N:'):gsub(':%d+:', ':N:'))) end

io.write(table.concat(out, '\n'), '\n')
