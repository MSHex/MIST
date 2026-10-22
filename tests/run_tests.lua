--[[
	MIST regression tests (assertion based).

		lua5.1 tests/run_tests.lua [path/to/mist.lua]

	Each test loads a fresh MIST into a fresh DCS mock.
]]

local mistPath = arg[1] or 'mist.lua'
local here = (arg[0]:match('^(.*)[/\\]') or '.') .. '/'

local passed, failed = 0, 0
local dcs

local function fresh(opts)
	-- wipe globals the mock/MIST create, then rebuild
	for _, g in ipairs({'mist', 'timer', 'env', 'coalition', 'country', 'Object', 'Unit', 'Group', 'StaticObject',
		'Airbase', 'world', 'trigger', 'land', 'coord', 'atmosphere', 'missionCommands', 'Controller', 'AI'}) do
		_G[g] = nil
	end
	dcs = dofile(here .. 'dcs_mock.lua')
	dcs.buildMission(opts or {groups = 4, unitsPerGroup = 2, planes = 1, statics = 1, zones = 3})
	dofile(mistPath)
	dcs.advance(1.5)
end

local function test(name, f)
	fresh()
	local ok, err = pcall(f)
	if ok and #dcs.errors > 0 then
		ok, err = false, 'MIST logged errors: ' .. table.concat(dcs.errors, ' / ')
	end
	if ok then
		passed = passed + 1
		print('ok   ' .. name)
	else
		failed = failed + 1
		print('FAIL ' .. name .. '\n     ' .. tostring(err))
	end
end

local function eq(a, b, msg)
	if a ~= b then error((msg or 'values differ') .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or 'expected truthy', 2) end end

-- ---------------------------------------------------------------------------
-- reference implementations from MIST 4.5.126, for equivalence checks
local function old_makeVec3(vec, y)
	if not vec.z then
		if vec.alt and not y then y = vec.alt elseif not y then y = 0 end
		return {x = vec.x, y = y, z = vec.y}
	else
		return {x = vec.x, y = vec.y, z = vec.z}
	end
end
local function old_pointInPolygon(point, poly, maxalt)
	point = old_makeVec3(point)
	local px, pz, cn = point.x, point.z, 0
	local newpoly = {}
	for i = 1, #poly do newpoly[i] = poly[i] end
	if not maxalt or (point.y <= maxalt) then
		local polysize = #newpoly
		newpoly[#newpoly + 1] = newpoly[1]
		newpoly[1] = old_makeVec3(newpoly[1])
		for k = 1, polysize do
			newpoly[k + 1] = old_makeVec3(newpoly[k + 1])
			if ((newpoly[k].z <= pz) and (newpoly[k + 1].z > pz)) or ((newpoly[k].z > pz) and (newpoly[k + 1].z <= pz)) then
				local vt = (pz - newpoly[k].z) / (newpoly[k + 1].z - newpoly[k].z)
				if (px < newpoly[k].x + vt * (newpoly[k + 1].x - newpoly[k].x)) then cn = cn + 1 end
			end
		end
		return cn % 2 == 1
	end
	return false
end
local function old_stringCondense(s)
	local exclude = {'%-', '%(', '%)', '%_', '%[', '%]', '%.', '%#', '% ', '%{', '%}', '%$', '%%', '%?', '%+', '%^'}
	for _, str in pairs(exclude) do s = string.gsub(s, str, '') end
	return s
end

local seed = 12345
local function rnd(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % n
end

-- ---------------------------------------------------------------------------
-- scheduler
test('one-shot tasks run once, at their time, with their arguments', function()
	local got = {}
	mist.scheduleFunction(function(a, b, c) got[#got + 1] = {a, b, c, timer.getTime()} end, {1, nil, 3}, timer.getTime() + 0.5)
	dcs.advance(0.45)
	eq(#got, 0)
	dcs.advance(0.1)
	eq(#got, 1)
	eq(got[1][1], 1); eq(got[1][2], nil); eq(got[1][3], 3)
	dcs.advance(2)
	eq(#got, 1, 'ran twice')
end)

test('repeating tasks honour rep and stop time', function()
	local n = 0
	local t0 = timer.getTime()
	mist.scheduleFunction(function() n = n + 1 end, {}, t0 + 0.1, 0.5, t0 + 2.05)
	dcs.advance(5)
	-- runs at ~0.1, 0.6, 1.1, 1.6 (next would be 2.1 > stop)
	eq(n, 4)
end)

test('a repeating task removing itself does not delay the next task', function()
	local log, selfAt, nextAt = {}, nil, nil
	local selfId
	local t = timer.getTime() + 0.3
	selfId = mist.scheduleFunction(function()
		log[#log + 1] = 'self'
		selfAt = timer.getTime()
		mist.removeFunction(selfId)
	end, {}, t, 1)
	mist.scheduleFunction(function() log[#log + 1] = 'next'; nextAt = timer.getTime() end, {}, t)
	-- 4.5.126 shifted the list while iterating, skipping the task after a self-removal
	-- (it ran one tick late); both must now run in the same tick
	mist.scheduleFunction(function() end, {}, t)
	dcs.advance(0.5)
	truthy(selfAt and nextAt, 'a task did not run')
	eq(nextAt, selfAt, 'next task was delayed')
	dcs.advance(3)
	eq(#log, 2, 'self-removed task ran again')
end)

test('removeFunction return values and pending count', function()
	local base = mist.getScheduledFunctionCount()
	local id = mist.scheduleFunction(function() end, {}, timer.getTime() + 100)
	eq(mist.getScheduledFunctionCount(), base + 1)
	eq(mist.removeFunction(id), true)
	eq(mist.removeFunction(id), false)
	eq(mist.removeFunction(-5), false)
	eq(mist.getScheduledFunctionCount(), base)
end)

test('mass schedule/remove compacts the queue', function()
	local base = mist.getScheduledFunctionCount()
	local ids = {}
	for i = 1, 5000 do ids[i] = mist.scheduleFunction(function() error('should not run') end, {}, timer.getTime() + 1000 + i) end
	for i = 1, 5000 do truthy(mist.removeFunction(ids[i])) end
	eq(mist.getScheduledFunctionCount(), base)
	dcs.advance(1)
	-- schedule still works afterwards
	local ran = false
	mist.scheduleFunction(function() ran = true end, {}, timer.getTime() + 0.1)
	dcs.advance(0.2)
	truthy(ran)
end)

test('errors in tasks are logged and do not stop other tasks', function()
	local ran = false
	mist.scheduleFunction(function() error('boom') end, {}, timer.getTime() + 0.1)
	mist.scheduleFunction(function() ran = true end, {}, timer.getTime() + 0.1)
	dcs.advance(0.2)
	truthy(ran)
	eq(#dcs.errors, 1)
	truthy(dcs.errors[1]:find('Error in scheduled function'))
	dcs.errors = {}
end)

test('tasks scheduled for now from inside a task run in the same tick', function()
	local order = {}
	mist.scheduleFunction(function()
		order[#order + 1] = 'outer'
		mist.scheduleFunction(function() order[#order + 1] = 'inner' end, {}, timer.getTime())
	end, {}, timer.getTime() + 0.2)
	dcs.advance(0.21)
	eq(table.concat(order, ','), 'outer,inner')
end)

-- ---------------------------------------------------------------------------
-- databases
test('DB indexes share one entry per unit; ME snapshot is independent', function()
	local u = mist.DBs.unitsByName['blue armor 1-1']
	truthy(u)
	eq(mist.DBs.unitsById[u.unitId], u)
	eq(mist.DBs.unitsByNum[u.dbNum], u)
	eq(mist.DBs.groupsById[mist.DBs.groupsByName['blue armor 1'].groupId], mist.DBs.groupsByName['blue armor 1'])
	truthy(mist.DBs.MEunitsByName['blue armor 1-1'] ~= u, 'ME snapshot shares live entry')
	u.type = 'changed'
	eq(mist.DBs.MEunitsByName['blue armor 1-1'].type, 'T-72B')
	-- the ME snapshot shares among its own indexes like the live DBs do
	eq(mist.DBs.MEunitsById[u.unitId], mist.DBs.MEunitsByName['blue armor 1-1'])
end)

test('getGroupData still returns copies', function()
	local g = mist.getGroupData('blue armor 1')
	g.units[1].type = 'x'
	eq(mist.DBs.groupsByName['blue armor 1'].units[1].type, 'T-72B')
end)

test('lastDBUpdate advances and flag functions see new spawns', function()
	-- a zone nobody is in yet
	mist.DBs.zonesByName['empty'] = {name = 'empty', radius = 500, point = {x = 90000, y = 0, z = 90000}, x = 90000, y = 90000}
	mist.flagFunc.units_in_zones({units = {'[blue][vehicle]'}, zones = {'empty'}, flag = 77, interval = 1})
	dcs.advance(2)
	eq(trigger.misc.getUserFlag(77), 0)
	local before = mist.getLastDBUpdateTime()
	mist.dynAdd({country = 'USA', category = 'vehicle', name = 'late arrival',
		units = {{type = 'M-1 Abrams', x = 90000, y = 90000, name = 'late-1'}}})
	dcs.advance(4)
	truthy(mist.getLastDBUpdateTime() > before, 'lastDBUpdate did not advance')
	eq(trigger.misc.getUserFlag(77), 1, 'flag function never noticed the new unit')
end)

test('a burst of spawns is fully ingested across coroutine yields', function()
	for i = 1, 60 do
		mist.dynAdd({country = 'USA', category = 'vehicle', name = 'burst ' .. i,
			units = {{type = 'M-1 Abrams', x = i, y = i, name = 'burst ' .. i .. '-1'}}})
		if i % 7 == 0 then dcs.advance(0.05) end	-- spawn while the DB writer is mid-batch
	end
	dcs.advance(6)
	for i = 1, 60 do
		truthy(mist.DBs.groupsByName['burst ' .. i], 'missing group burst ' .. i)
		truthy(mist.DBs.unitsByName['burst ' .. i .. '-1'], 'missing unit burst ' .. i)
	end
	-- dbNum stays consistent with unitsByNum
	for i, e in ipairs(mist.DBs.unitsByNum) do eq(e.dbNum, i, 'dbNum mismatch at ' .. i) end
end)

test('dynAdd data (skill, task) reaches the DB; RADIO altitude stored once', function()
	mist.dynAdd({country = 'USA', category = 'vehicle', name = 'skilled', task = 'Ground Nothing',
		units = {{type = 'M-1 Abrams', x = 0, y = 0, name = 'skilled-1', skill = 'Excellent'}}})
	mist.dynAdd({country = 'USA', category = 'plane', name = 'flyer',
		units = {{type = 'F-16C_50', x = 0, y = 0, alt = 2500, alt_type = 'RADIO', name = 'flyer-1', payload = {}}}})
	dcs.advance(4)
	eq(mist.DBs.unitsByName['skilled-1'].skill, 'Excellent')
	eq(mist.DBs.groupsByName['skilled'].task, 'Ground Nothing')
	eq(mist.DBs.unitsByName['flyer-1'].alt, 2500)
	eq(mist.DBs.unitsByName['flyer-1'].alt_type, 'RADIO')
end)

test('groups spawned outside MIST get default skill/alt_type', function()
	coalition.addGroup(country.id.USA, Group.Category.AIRPLANE, {name = 'foreign',
		units = {{name = 'foreign-1', type = 'F-15C', x = 1, y = 1, alt = 4000}}})
	dcs.advance(4)
	local u = mist.DBs.unitsByName['foreign-1']
	truthy(u, 'not ingested')
	eq(u.skill, 'High')
	eq(u.alt_type, 'BARO')
	eq(u.category, 'plane')
	eq(u.coalition, 'blue')
	eq(u.country, 'usa')
end)

test('mist.forceAddToDB accepts a group name', function()
	coalition.addGroup(country.id.RUSSIA, Group.Category.GROUND, {name = 'forced',
		units = {{name = 'forced-1', type = 'BMP-2', x = 1, y = 1}}})
	-- ingest immediately, without waiting for the spawn handler
	mist.forceAddToDB('forced')
	truthy(mist.DBs.groupsByName['forced'], 'not added')
	eq(mist.DBs.unitsByName['forced-1'].category, 'vehicle')
	eq(mist.DBs.unitsByName['forced-1'].coalition, 'red')
	dcs.advance(4)	-- the birth event path must not error on the existing entry
end)

test('dynAdd country/category resolution', function()
	truthy(mist.dynAdd({country = 'the netherlands', category = 'GROUND', units = {{type = 'x', x = 0, y = 0}}}))
	truthy(mist.dynAdd({country = 2, category = 2, units = {{type = 'x', x = 0, y = 0}}}))
	truthy(mist.dynAdd({countryId = 0, category = 'helicopter', units = {{type = 'Mi-8MT', x = 0, y = 0}}}))
	eq(mist.dynAdd({country = 'atlantis', category = 'vehicle', units = {{type = 'x', x = 0, y = 0}}}), false)
	dcs.errors = {}	-- the bad country is logged as an error by design
	dcs.advance(4)
	truthy(mist.DBs.groupsByName['THE_NETHERLANDS gnd 1'], 'netherlands group missing')
end)

test('alive units are refreshed in place and deaths move to removedAliveUnits', function()
	dcs.advance(2)
	local e
	for id, entry in pairs(mist.DBs.aliveUnits) do
		if entry.unitName == 'red armor 1-1' then e = entry end
	end
	truthy(e, 'unit not tracked')
	local x0 = e.pos.x
	dcs.moveUnit('red armor 1-1', 500, 0)
	dcs.advance(1.5)
	local e2
	for id, entry in pairs(mist.DBs.aliveUnits) do
		if entry.unitName == 'red armor 1-1' then e2 = entry end
	end
	eq(e2, e, 'entry was rebuilt instead of refreshed')
	eq(e2.pos.x, x0 + 500)
	truthy(e2 ~= mist.DBs.unitsByName['red armor 1-1'], 'alive entry must not alias the DB entry')
	dcs.killUnit('red armor 1-1')
	dcs.advance(1.5)
	local found = false
	for id, entry in pairs(mist.DBs.removedAliveUnits) do
		if entry.unitName == 'red armor 1-1' then found = true end
	end
	truthy(found, 'dead unit not in removedAliveUnits')
end)

-- ---------------------------------------------------------------------------
-- zones and geometry
test('pointInPolygon matches the 4.5.126 implementation', function()
	for i = 1, 3000 do
		local poly = {}
		local n = 3 + rnd(6)
		local useV3 = rnd(2) == 0
		for k = 1, n do
			local x, y = rnd(2000) - 1000, rnd(2000) - 1000
			poly[k] = useV3 and {x = x, y = rnd(100), z = y} or {x = x, y = y}
		end
		local pt
		local r = rnd(3)
		if r == 0 then pt = {x = rnd(2400) - 1200, y = rnd(2400) - 1200}
		elseif r == 1 then pt = {x = rnd(2400) - 1200, y = rnd(300), z = rnd(2400) - 1200}
		else pt = {x = rnd(2400) - 1200, y = rnd(2400) - 1200, alt = rnd(300)} end
		local maxalt = (rnd(3) == 0) and rnd(300) or nil
		eq(mist.pointInPolygon(pt, poly, maxalt), old_pointInPolygon(pt, poly, maxalt), 'mismatch on case ' .. i)
	end
end)

test('stringCondense matches the 4.5.126 implementation', function()
	local chars = 'aB1-()_[].# {}$%?+^*/\\,;:@!~`\'"zZ'
	for i = 1, 3000 do
		local t = {}
		for k = 1, rnd(30) do
			local c = rnd(#chars) + 1
			t[#t + 1] = chars:sub(c, c)
		end
		local s = table.concat(t)
		eq(mist.stringCondense(s), old_stringCondense(s), 'mismatch on ' .. s)
	end
end)

test('getUnitsInZones: cylinder, sphere, polygon, and no double counting', function()
	local Z = mist.DBs.zonesByName
	Z['a'] = {name = 'a', radius = 2000, point = {x = 0, y = 0, z = 0}}
	Z['b'] = {name = 'b', radius = 2000, point = {x = 100, y = 0, z = 0}}
	Z['p1'] = {name = 'p1', radius = 0, point = {x = 0, y = 0, z = 0},
		verticies = {{x = -3000, y = -3000}, {x = 3000, y = -3000}, {x = 3000, y = 3000}, {x = -3000, y = 3000}}}
	Z['p2'] = Z['p1']
	coalition.addGroup(country.id.USA, Group.Category.GROUND, {name = 'zt',
		units = {{name = 'zt-1', type = 'x', x = 10, y = 10}, {name = 'zt-2', type = 'x', x = 50000, y = 0}}})
	coalition.addGroup(country.id.USA, Group.Category.AIRPLANE, {name = 'zh',
		units = {{name = 'zh-1', type = 'x', x = 10, y = 10, alt = 5000}}})
	local names = {'zt-1', 'zt-2', 'zh-1', 'nonexistent'}
	eq(#mist.getUnitsInZones(names, {'a', 'b'}), 2, 'cylinder (overlapping zones)')
	eq(#mist.getUnitsInZones(names, {'a'}, 's'), 1, 'sphere excludes the high aircraft')
	eq(#mist.getUnitsInZones(names, 'a'), 2, 'zone name as string')
	eq(#mist.getUnitsInZones(names, {'p1', 'p2'}), 2, 'overlapping polygons count each unit once')
	eq(#mist.getUnitsInPolygon(names, Z['p1'].verticies), 2)
	eq(#mist.getUnitsInPolygon(names, Z['p1'].verticies, 1000), 1, 'maxalt')
	dcs.advance(4)
end)

test('stringMatch semantics', function()
	truthy(mist.stringMatch('Blue-Armor (1)', 'bluearmor1'))
	truthy(not mist.stringMatch('Blue', 'blue', true))
	truthy(mist.stringMatch('Blue', 'Blue', true))
	truthy(not mist.stringMatch('a', 'b'))
	truthy(not mist.stringMatch('a', nil))
	dcs.errors = {}	-- the nil case logs an error by design
end)

test('misc: ID getters return numbers, callsign table layout', function()
	eq(type(mist.getNextUnitId()), 'number')
	eq(type(mist.getNextGroupId()), 'number')
	local nato = mist.DBs.const.callsigns.NATO
	eq(nato.JTAC.Axeman, 1)
	eq(nato.unique.A10.Hawg, 9)
	eq(nato.TRANSPORT.Heavy, 9)
	eq(nato.TRANSPORT.JTAC, nato.JTAC, 'old path alias')
end)

print(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
