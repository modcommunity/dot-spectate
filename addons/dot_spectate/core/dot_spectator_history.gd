class_name DotSpectatorHistory
extends RefCounted

## A bounded ring of where everybody was, so a camera can look at the past.
##
## [b]This exists for one reason: a spectator watching live is an intelligence feed.[/b]
## A player on a second machine, a streamer's chat, a team-mate who died first — all of
## them see what the living cannot, and the answer every competitive game reached is the
## same one: delay the feed. A broadcast relay's default is ninety seconds; a competitive server's
## is a few. Either way the camera samples a tick in the past and nothing else in the
## addon has to know that it did.
##
## [b]Bounded, and the bound is checked.[/b] A history that grows with the round is a
## memory leak with a plausible name, and this family has already shipped a recorder
## with no ceiling — dot-timer's [code]max_replay_seconds[/code] was a documented
## setting that nothing read, which on a server is a player idling in a run for hours.

## tick -> {key: Transform3D}
var _frames: Dictionary = {}

var _ticks: PackedInt32Array = PackedInt32Array()

var _capacity: int = 128


func _init(p_capacity: int = 128) -> void:
	_capacity = maxi(p_capacity, 2)


func capacity() -> int:
	return _capacity


func set_capacity(n: int) -> void:
	_capacity = maxi(n, 2)
	_trim()


func size() -> int:
	return _ticks.size()


func clear() -> void:
	_frames.clear()
	_ticks = PackedInt32Array()


## Record where everybody is on one tick.
func record(tick: int, poses: Dictionary) -> void:
	if _frames.has(tick):
		_frames[tick] = poses.duplicate()
		return
	_frames[tick] = poses.duplicate()
	_ticks.append(tick)
	_trim()


## Where somebody was, [param delay] ticks before [param tick].
##
## Returns the newest frame at or before the wanted tick, and [code]false[/code] in the
## second slot when there is no history for them at all — which a caller must branch on
## rather than drawing a camera at the origin. A spectator camera at the world origin
## looking down the X axis is the "sky in every direction" screenshot this family has
## already spent three days on.
func sample(tick: int, delay: int, key: String) -> Array:
	if _ticks.is_empty():
		return [Transform3D.IDENTITY, false]

	var want := tick - maxi(delay, 0)
	var best := -1
	for t in _ticks:
		if t <= want and t > best:
			best = t
	if best < 0:
		# Everything we have is newer than the tick asked for, which happens for the
		# first `delay` ticks of a round. The oldest is the closest to the truth.
		best = _oldest()

	var frame: Dictionary = _frames.get(best, {})
	if not frame.has(key):
		return [Transform3D.IDENTITY, false]
	return [frame[key] as Transform3D, true]


func _oldest() -> int:
	var out := _ticks[0]
	for t in _ticks:
		if t < out:
			out = t
	return out


func _trim() -> void:
	while _ticks.size() > _capacity:
		var oldest := _oldest()
		_frames.erase(oldest)
		var kept := PackedInt32Array()
		for t in _ticks:
			if t != oldest:
				kept.append(t)
		_ticks = kept


func describe() -> Dictionary:
	return {"frames": _ticks.size(), "capacity": _capacity}
