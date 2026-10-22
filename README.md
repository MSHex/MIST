Mission Scripting Tools
=====================

Mission Scripting Tools for Digital Combat Simulator

Authors: Grimes (mrSkortch), Speed

Forum Thread: http://forums.eagle.ru/showthread.php?t=98616

Documentation
====
The MIST Wiki page can be found at this address: http://wiki.hoggit.us/view/Mission_Scripting_Tools_Documentation

The attached pdf "mist gude.pdf" is attached in the download however is no longer being updated. 

Description
====
MIssion Scripting Tools (Mist) is a collection of Lua functions and databases that is intended to be a supplement to the standard Lua functions included in the simulator scripting engine. Mist functions and databases provide ready-made solutions to many common scripting tasks and challenges, enabling easier scripting and saving mission scripters time. The table mist.flagFuncs contains a set of Lua functions (that are similar to Slmod functions) that do not require detailed Lua knowledge to use. However, the majority of Mist does require knowledge of the Lua language, and, if you are going to utilize these components of Mist, it is necessary that you read the Simulator Scripting Engine guide on the official ED wiki

====
Donate. If you want to. Likely will go into the "Better than a X52 HOTAS Fund". Or also Beer money. 

[![](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=X8CHU2343FRKA&currency_code=USD&source=url)


Fork notes (MSHex)
====
This fork continues MIST from 4.5.126 with performance work and bug fixes; see `rev changelog.txt` (v4.5.127) for the full list. It is a drop-in replacement: load `mist.lua` exactly as before.

Tests and benchmarks run outside DCS against a mock of the scripting engine, using a Lua 5.1 interpreter (the version DCS embeds), from the repository root:

    lua5.1 tests/run_tests.lua                 # assertion tests
    lua5.1 tests/bench.lua [mist file]         # CPU/memory benchmark
    lua5.1 tests/scenario.lua old.lua > a.txt  # behaviour trace; diff two builds
    lua5.1 tests/sched_fuzz.lua mist.lua 7     # scheduler trace for seed 7; diff two builds

Contribution Guide
====
Contributions can be made with a standard github pull request model.  Code developed for the next release should be requested to be pulled into the "develop" branch.
Pull requests not targetted for "develop" will be denied.  For hotfixes please open a ticket describing the problem and ideally a fix and your changes will be attributed in the relevant commit message.  It's done like this because unfortunately github provides no tools to target to a new hotfix branch, and github tools are exclusively used in the administration of this repository and we wish to minimize the amount of unvetted code into master.
