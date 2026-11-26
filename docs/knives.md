`GSWeaponKnives` (API 27, `thrown/gs_weapon_knives.gd`) is the thrown-knife layer FC and Zombie Zone share. The code comments link here.

## The layer

Aiming with the knife in hand throws it. The server flies each knife on the tick, hurts the first body it reaches (rule `damage`), sticks it in a body it kills, bounces it off the world, and returns it to whoever walks over it. Clients mirror the events through `GSWeaponKnifeWire`.

A game owns one as a child node: fill its fields, call `input` before players simulate and `tick` after, and forward its `changed` signal.

## Charge and boomerang

Rule `charge` makes the throw a hold-and-release whose power fills over `charge_sec`. A knife whose fitted definition has `PARAM_BOOMERANG` glides a closed loop back to where it left the hand (or homes on the thrower) and sticks in any enemy it hits.

## The boomerang path

A boomerang reaches `boomerang_distance` metres from the throw point along the throw (its farthest point): it goes straight out, circles through a turn of radius `boomerang_radius`, and flies the tangent straight back to `Knife.origin`, where it was thrown from. A radius over the distance flies one full circle of that radius. The turn leaves the circle on the line through the origin, so the way back is as long as the way out.

The position is a function of the metres flown, so two servers agree bit for bit and the path ends on the origin exactly. The thrower's own velocity is not added: it would move the origin the path closes on.
