class_name DotSpectatorFreeCam
extends RefCounted

## The controls of a roaming camera, forwarding to GameSpice Camera's [DotCameraFreeLook].
##
## The arithmetic moved there so a spectator's roam, a flythrough and a debug camera share it; this class keeps the spectator names and takes its speeds from [DotSpectatorRules].
##
## [b]Here and not in the manager because the manager computes a transform and reads no
## input[/b] ([code]docs/design.md[/code]). Every game has a different input sampler and
## different bindings, so what is shared is the arithmetic that is easy to get wrong — pitch
## clamped short of straight up so the basis never degenerates, movement along the way the
## camera faces so "forward" climbs when looking up, speed from the server's rules — and
## the game feeds it numbers.
##
## Presentation only. A client drives it each frame while its view is
## [constant DotSpectatorView.Mode.ROAMING] and puts [method transform] on its camera;
## the server does not need the pose, and the view's wire form carries the entry point.
##
## [codeblock]
## var free := DotSpectatorFreeCam.new()
## free.rules = manager.rules
## # on entering the roam
## free.seed_from(manager.camera_of(id))
## # every frame while roaming
## free.look(mouse_relative * sensitivity)
## camera.global_transform = free.step(Vector3(right, up, forward), fast, slow, delta)
## [/codeblock]

## Where the speeds come from. Optional: without it the defaults of a fresh rules object.
var rules: DotSpectatorRules = null

## Short of 90 degrees; see [constant DotCameraFreeLook.MAX_PITCH].
const MAX_PITCH := DotCameraFreeLook.MAX_PITCH

var _look := DotCameraFreeLook.new()
var _cfg := DotCameraConfig.new()

var position: Vector3:
	get: return _look.position
	set(v): _look.position = v

## Radians. Yaw turns left for positive, as [method Basis.from_euler] does.
var yaw: float:
	get: return _look.yaw
	set(v): _look.yaw = v

var pitch: float:
	get: return _look.pitch
	set(v): _look.pitch = v


## Start from an existing camera, so a roam begins where the spectator already was.
func seed_from(t: Transform3D) -> void:
	_look.seed_from(t)


## Turn by [param delta_angles] radians: x is yaw, y is pitch (up positive).
func look(delta_angles: Vector2) -> void:
	_look.look(delta_angles)


func basis() -> Basis:
	return _look.get_basis()


func transform() -> Transform3D:
	return _look.get_transform()


## Fly for [param delta] seconds. [param move] is x right, y up (world up), z forward along the view; each in -1..1.
func step(move: Vector3, fast: bool, slow: bool, delta: float) -> Transform3D:
	var r := rules if rules != null else DotSpectatorRules.new()
	_cfg.free_speed = r.roam_speed
	_cfg.free_fast_scale = r.roam_fast_scale
	_cfg.free_slow_scale = r.roam_slow_scale
	return _look.step(_cfg, move, fast, slow, delta)
