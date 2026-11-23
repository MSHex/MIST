# MIST test builds

In-progress builds. **4.5.128 (`mist_4_5_128.lua` in the repo root) is the stable fallback.**
Load a test build *instead of* 4.5.128, not as well: the load-once guard keeps whichever copy loads first.

## mist_4_5_129_test.lua
- Alive-unit sweep skips units DCS reported dead/crashed/lost/removed (cleared again on BIRTH, so respawns are tracked).
- `mist.DBs.deadObjects` and `mist.DBs.removedAliveUnits` are pruned after `mist.deadObjectsMaxAge` seconds
  (default 1800; set 0 to keep everything as 4.5.128 does). Dead map objects are never pruned.
- Each death is processed once instead of twice.
- Logs `Mist version 4.5.129-test loaded.`

## Running the checks (Lua 5.1)
    lua5.1 test/run_tests_test.lua test/mist_4_5_129_test.lua   # 26 tests (23 existing + 3 new)
    lua5.1 test/deathbench_test.lua test/mist_4_5_129_test.lua  # 960 units, 720 killed, 30 min
