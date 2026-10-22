--[[
	Scheduler differential fuzz.

	Drives mist.scheduleFunction / mist.removeFunction with a seeded random
	workload (one-shots, repeats, stop times, removals from outside and from
	inside running tasks, tasks scheduling tasks) and prints which task ran in
	which tick. Lines within one tick are sorted, so two builds can be diffed
	on *when* things run, independent of their order inside a single tick.

		lua5.1 tests/sched_fuzz.lua mist.lua [seed] [ops]
]]

local mistPath = arg[1] or 'mist.lua'
local seed = tonumber(arg[2]) or 1
local ops = tonumber(arg[3]) or 400
local here = (arg[0]:match('^(.*)[/\\]') or '.') .. '/'
local dcs = dofile(here .. 'dcs_mock.lua')
dcs.buildMission({groups = 1, unitsPerGroup = 1, planes = 0, statics = 0, zones = 1})
dofile(mistPath)
dcs.advance(1)

-- deterministic LCG (math.random differs between builds of Lua)
local state = seed
local function rnd(n)
	state = (state * 1103515245 + 12345) % 2147483648
	return state % n
end

local ticks = {}
local function mark(label)
	local tick = math.floor(timer.getTime() * 100 + 0.5)
	ticks[tick] = ticks[tick] or {}
	table.insert(ticks[tick], label)
end

local ids = {}
local labelOf = {}
for op = 1, ops do
	local kind = rnd(10)
	local now = timer.getTime()
	if kind < 4 then
		local label = 'once' .. op
		ids[#ids + 1] = mist.scheduleFunction(function(a) mark(label .. ':' .. a) end, {op}, now + rnd(300) / 100)
		labelOf[ids[#ids]] = label
	elseif kind < 6 then
		local label = 'rep' .. op
		local st
		if rnd(2) == 0 then st = now + rnd(500) / 100 end
		ids[#ids + 1] = mist.scheduleFunction(function() mark(label) end, nil, now + rnd(200) / 100, (rnd(150) + 5) / 100, st)
		labelOf[ids[#ids]] = label
	elseif kind < 7 and #ids > 0 then
		local id = ids[rnd(#ids) + 1]
		mark('remove ' .. tostring(labelOf[id]) .. ' ' .. tostring(mist.removeFunction(id)))
	elseif kind < 8 then
		-- repeating task that cancels itself after a few runs
		local label = 'selfstop' .. op
		local runs, myId = 0, nil
		myId = mist.scheduleFunction(function()
			runs = runs + 1
			mark(label .. ' run' .. runs)
			if runs >= 3 then mark(label .. ' removed ' .. tostring(mist.removeFunction(myId))) end
		end, {}, now + rnd(100) / 100, 0.25)
	elseif kind < 9 then
		-- task that schedules a child, sometimes for "now"
		local label = 'parent' .. op
		local childDelay = rnd(3) / 100	-- drawn now so execution order can't shift the RNG
		mist.scheduleFunction(function()
			mark(label)
			mist.scheduleFunction(function() mark(label .. ' child') end, {}, timer.getTime() + childDelay)
		end, {}, now + rnd(200) / 100)
	else
		-- erroring task
		mist.scheduleFunction(function() mark('err' .. op); error('x') end, {}, now + rnd(100) / 100)
	end
	if rnd(4) == 0 then
		dcs.advance(rnd(50) / 100)
	end
end
dcs.advance(15)

local keys = {}
for k in pairs(ticks) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do
	local l = ticks[k]
	table.sort(l)
	print(k, table.concat(l, ' | '))
end
