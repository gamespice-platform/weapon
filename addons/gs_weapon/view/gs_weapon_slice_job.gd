extends RefCounted

## A piece of work that can stop part way and go on in a later frame: a subclass writes [method _work] with a
## `await _yield_if_spent()` every [constant CHECK_EVERY] turns of its loops, [method step] works for a time budget and returns,
## [method run] goes through at once. The answer is the same either way, the code is one. No `class_name`: preloaded by path.

## Work between looks at the clock, in loop turns: a turn is some microseconds, so a budget is overrun by about a millisecond at most.
const CHECK_EVERY := 128
const NO_LIMIT := 1 << 62

signal _resume

var _deadline := NO_LIMIT
var _begun := false
var _finished := false


## The whole job now.
func run() -> void:
	_deadline = NO_LIMIT
	_begun = true
	await _work()
	_finished = true


## Works for [param budget_usec] more microseconds (a little over at most); true once the job is done.
func step(budget_usec: int) -> bool:
	_deadline = Time.get_ticks_usec() + budget_usec
	if _finished:
		return true
	if not _begun:
		_begun = true
		_start()
	else:
		_resume.emit()
	return _finished


func _start() -> void:
	await _work()
	_finished = true


## Waits for the next [method step] when the budget is spent. Asked every [constant CHECK_EVERY] turns of a loop.
func _yield_if_spent() -> void:
	if _deadline != NO_LIMIT and Time.get_ticks_usec() >= _deadline:
		await _resume


## The job itself, a coroutine.
func _work() -> void:
	pass
