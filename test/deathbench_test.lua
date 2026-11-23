-- campaign-style load: 960 ground units, 75% die over 10 minutes, then 30 min of play
local mistPath = arg[1]
local here = (arg[0]:match('^(.*)[/\\]') or '.') .. '/../tests/'
dcs = dofile(here .. 'dcs_mock.lua')
dcs.buildMission({groups = 80, unitsPerGroup = 6, planes = 20, statics = 40, zones = 20})
dofile(mistPath)
dcs.advance(2)
local names = {}
for n, u in pairs(mist.DBs.unitsByName) do if u.category == 'vehicle' then names[#names+1] = n end end
table.sort(names)
local calls, orig = 0, Unit.getByName
Unit.getByName = function(n) calls = calls + 1 return orig(n) end
local kill = math.floor(#names * 0.75)
for i = 1, kill do dcs.killUnit(names[i]); if i % 12 == 0 then dcs.advance(10) end end
collectgarbage(); collectgarbage()
local t0, c0 = os.clock(), calls
dcs.advance(1800)
local cpu = os.clock() - t0
collectgarbage(); collectgarbage()
local nd, nr = 0, 0
for _ in pairs(mist.DBs.deadObjects) do nd = nd + 1 end
for _ in pairs(mist.DBs.removedAliveUnits) do nr = nr + 1 end
print(string.format('%d units, %d killed | 30 min after: CPU %.0f ms, getByName/s %.0f, deadObjects %d, removedAlive %d, Lua mem %.1f MB',
  #names, kill, cpu*1000, (calls-c0)/1800, nd, nr, collectgarbage('count')/1024))
