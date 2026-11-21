# SWS Pilatus PC-12 (MSFS 2024): issues found while mapping variables

Notes kept while building a checklist for the SWS PC-12 in Microsoft Flight Simulator 2024. Started 2026-11-20. Aircraft package: `sws-aircraft-pc12`. Variables were read through the FlightSim Aide companion (read-only), so each issue lists the value that was seen.

## 1. Cargo door does not open

- With the control wheel lock removed (which also removes the sunshade, chocks and covers) the cargo door still does not open. The passenger door does (unlock the handle, then open).
- `A:INTERACTIVE POINT OPEN:2, percent` (the cargo door) stayed 0. The passenger door, `A:INTERACTIVE POINT OPEN:1, percent`, went from 0 to 100.
- The cargo handle's model variable, `Z:SWS_EXIT_CargoDoor_Handle, bool`, read 1 on every look and was not seen moving.
- Not yet checked: whether the door needs another state (power, ground services, the lock stowed rather than removed).

## 2. CAWS passenger door light does not come on when the door is open

- Door open (`A:INTERACTIVE POINT OPEN:1` = 100), batteries on, then external power on: the light on the CAWS panel stays off.
- `L:SAFETY_CAWS_Light_PASS_DOOR` and `L:SAFETY_CAWS_Light_CAR_DOOR` read 0 throughout. The lamp test lights the panel, but those variables stayed 0 during it (the test changed only `B:INSTRUMENT_PUSH_TESTLAMP` and `L:SAFETY_Push_TestLamp`), so they are not the lights the panel uses.
- Not yet checked: with the engine running.
