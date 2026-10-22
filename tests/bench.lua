--[[
	MIST micro/macro benchmarks against the DCS mock.

		lua5.1 tests/bench.lua [path/to/mist.lua] [scale]

	Every number is CPU time (os.clock) or Lua heap allocated (KB),
	so results are comparable between two MIST builds on the same machine.
]]

local mistPath = arg[1] or 'mist.lua'
local scale = tonumber(arg[2]) or 1
local here = (arg[0]:match('^(.*)[/\\]') or '.') .. '/'
local dcs = dofile(here .. 'dcs_mock.lua')

-- ~2,000 units: 2 coalitions x 160 groups x 6 units + planes/statics
dcs.buildMission({groups = math.floor(160 * scale), unitsPerGroup = 6, planes = 20, statics = 40, zones = 20})

local results = {}
local function report(name, value, unit)
	results[#results + 1] = string.format('%-44s %12.3f %s', name, value, unit)
end

-- allocation accounting: total KB allocated during f (GC stopped so nothing is freed)
local function measure(f)
	collectgarbage('collect')
	collectgarbage('stop')
	local m0 = collectgarbage('count')
	local c0 = os.clock()
	f()
	local c1 = os.clock()
	local m1 = collectgarbage('count')
	collectgarbage('restart')
	collectgarbage('collect')
	return c1 - c0, m1 - m0
end

local t, kb = measure(function() dofile(mistPath) end)
report('load + initDBs', t * 1000, 'ms')
report('load + initDBs alloc', kb / 1024, 'MB')
collectgarbage('collect')
report('heap after init', collectgarbage('count') / 1024, 'MB')

-- warm up: let the alive-units coroutine populate
dcs.advance(2)

-- 1) idle mist.main for 60 s of sim time (100 Hz) with only the alive-unit tracker
t, kb = measure(function() dcs.advance(60) end)
report('60s sim, idle (alive tracking only)', t * 1000, 'ms')
report('60s sim, idle alloc', kb / 1024, 'MB')

-- 2) scheduler load: 1,000 repeating tasks at 1-5 s, plus 2,000 one-shots
local calls = 0
local function work() calls = calls + 1 end
for i = 1, 1000 do
	mist.scheduleFunction(work, {i}, timer.getTime() + (i % 50) / 10, 1 + (i % 5))
end
for i = 1, 2000 do
	mist.scheduleFunction(work, {i}, timer.getTime() + (i % 600) / 10)
end
t, kb = measure(function() dcs.advance(60) end)
report('60s sim, 1000 repeat + 2000 one-shot tasks', t * 1000, 'ms')
report('  task calls', calls, '')

-- removeFunction cost with a big queue
local ids = {}
for i = 1, 3000 do ids[i] = mist.scheduleFunction(work, {}, timer.getTime() + 1000 + i) end
t = measure(function() for i = 3000, 1, -1 do mist.removeFunction(ids[i]) end end)
report('removeFunction x3000', t * 1000, 'ms')

-- 3) flag functions: 50 units_in_zones watchers on shortcut tables
for i = 1, 50 do
	mist.flagFunc.units_in_zones({units = {'[blue][vehicle]'}, zones = {'zone ' .. ((i % 20) + 1)}, flag = 1000 + i, interval = 1, toggle = true, stopflag = 999})
end
t, kb = measure(function() dcs.advance(30) end)
report('30s sim, 50 units_in_zones watchers', t * 1000, 'ms')
report('30s sim, 50 watchers alloc', kb / 1024, 'MB')
trigger.action.setUserFlag(999, true)	-- stop the watchers
dcs.advance(2)

-- 4) spawning: 200 dynAdd groups, then let the DB ingest them
t, kb = measure(function()
	for i = 1, 200 do
		mist.dynAdd({country = 'USA', category = 'vehicle', name = 'spawn ' .. i,
			units = {{type = 'M-1 Abrams', x = i, y = i}, {type = 'M-1 Abrams', x = i + 5, y = i}}})
	end
end)
report('dynAdd x200', t * 1000, 'ms')
t, kb = measure(function() dcs.advance(10) end)
report('10s sim ingesting 200 spawns', t * 1000, 'ms')
t = measure(function()
	for i = 1, 200 do
		mist.dynAddStatic({country = 'USA', category = 'Fortifications', type = 'Tech combine', x = i, y = i, name = 'st ' .. i})
	end
end)
report('dynAddStatic x200', t * 1000, 'ms')

-- 5) hot utilities
local quad = mist.DBs.zonesByName['quad'].verticies
local pt = {x = 1, y = 0, z = 1}
t, kb = measure(function() for i = 1, 100000 do mist.pointInPolygon(pt, quad) end end)
report('pointInPolygon x100k', t * 1000, 'ms')
report('pointInPolygon x100k alloc', kb / 1024, 'MB')
t = measure(function() for i = 1, 100000 do mist.stringMatch('Blue-Armor (1)', 'bluearmor1') end end)
report('stringMatch x100k', t * 1000, 'ms')
local names = mist.makeUnitTable({'[blue][vehicle]'})
t = measure(function() for i = 1, 100 do mist.getUnitsInZones(names, {'zone 1', 'zone 2'}) end end)
report('getUnitsInZones x100 (' .. #names .. ' units)', t * 1000, 'ms')
t = measure(function() for i = 1, 20 do mist.getUnitsInPolygon(names, quad) end end)
report('getUnitsInPolygon x20', t * 1000, 'ms')
t = measure(function() for i = 1, 20 do mist.makeUnitTable({'[blue][vehicle]', '[red][all]'}) end end)
report('makeUnitTable x20', t * 1000, 'ms')
t = measure(function() for i = 1, 100000 do mist.getNextUnitId() end end)
report('getNextUnitId x100k', t * 1000, 'ms')

print('MIST ' .. mist.majorVersion .. '.' .. mist.minorVersion .. '.' .. mist.build .. '  (' .. mistPath .. ')')
print('units in DB: ' .. #mist.DBs.unitsByNum .. ', errors: ' .. #dcs.errors)
for _, l in ipairs(results) do print(l) end
