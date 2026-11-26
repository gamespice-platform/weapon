Details of `GSWeaponHitscan`'s native tick (API 42 and later): the rows it trades with GameSpice Sim's `GSSimWeaponSpread` and when it may skip work. The code comments link here; the API levels are in the addon's [CLAUDE.md](../CLAUDE.md).

## The tuning row

`behaviour/gs_weapon_hitscan_native_rows.gd` writes the row `GSSimWeaponSpread.set_tuning` reads: the ballistics numbers the tick reads, its per-tick and tick-count terms at the running tick rate, and each accuracy term already resolved (the field when it is 0 or more, else the accuracy class preset). The row is 16 long and is one of the two rows the behaviour keeps, so a re-send allocates nothing.

## When the rows are re-sent

`_native_ready` brings both rows up to date before a native tick runs. The tuning row is re-sent when the ballistics (the object or any of its fields), the definition's tick fields, the accuracy class or the running rate changed. The frame row is re-sent when the spread rules (the object or a field), the crosshair setting or the rate changed. The native tick runs only when GameSpice Sim is loaded and both rows were accepted.

## An equal row is kept

A caller that scales the ballistics for a tick and puts it back (aim down sights does, every aimed tick) writes the same numbers again and again. When only a field write happened, the twin already holds a row that compares equal, so it keeps it and the native call and its row parse are skipped. Equal under `==` means at most the sign of a zero term differs, which no sum of spread terms can show.

## The rest tick

`GSWeaponHitscan.rest_tick` skips the tick when there is nothing to recover (no bloom shedding, no motion settling, no spread factor moving) and the carrier is settled: a `tick` with the settled posture would change only the ticks since the last use, which `rest_tick` counts itself. A cone kept for a crosshair skips too when the steady skip holds its fixed point for the settled posture, since that tick would only show the kept cone. Anything else takes the normal tick.
