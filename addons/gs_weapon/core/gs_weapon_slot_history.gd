class_name GSWeaponSlotHistory
extends RefCounted

## The slots a survivor has had out, newest last: what the previous-slot key (Q) returns to.
##
## [b]A pure list, no node:[/b] the client feeds it the slot in hand every frame and asks it where
## Q goes. Knife, pistol, Q is the knife; Q again is the pistol. A slot that cannot be drawn now
## (a weapon dropped, a kit that ran out) is skipped, and stays in the list for later.

## Slots 1 to 5 are the weapon pack's; these two are the kit slots.
## The most slots remembered, which is every slot there is.
const DEPTH := 8

var _seen: Array[int] = []


## The slot in hand is [param slot]; a repeat of the one already last changes nothing.
func note(slot: int) -> void:
	if slot <= 0:
		return

	if not _seen.is_empty() and _seen[_seen.size() - 1] == slot:
		return

	_seen.erase(slot)
	_seen.append(slot)

	while _seen.size() > DEPTH:
		_seen.remove_at(0)


## The slot Q goes to from [param current]: the most recent other slot [param usable] accepts, or 0
## when there is none. The jump counts as a change, so the next Q comes back.
func back(current: int, usable: Callable = Callable()) -> int:
	note(current)

	for i in range(_seen.size() - 2, -1, -1):
		var slot := _seen[i]

		if slot != current and (not usable.is_valid() or bool(usable.call(slot))):
			note(slot)
			return slot

	return 0


func last() -> int:
	return _seen[_seen.size() - 1] if not _seen.is_empty() else 0


func forget() -> void:
	_seen.clear()
