class_name DotSpectatorFreeCam
extends RefCounted

## The controls of a roaming camera: yaw, pitch and a position, moved by a game's own input.
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

var position: Vector3 = Vector3.ZERO

## Radians. Yaw turns left for positive, as [method Basis.from_euler] does.
var yaw: float = 0.0
var pitch: float = 0.0

## Short of 90 degrees: at exactly straight up the forward vector and the up vector are
## parallel and a basis built from them is garbage, which draws as the world vanishing.
const MAX_PITCH := deg_to_rad(89.0)


## Start from an existing camera, so a roam begins where the spectator already was.
func seed_from(t: Transform3D) -> void:
	position = t.origin
	var euler := t.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
	yaw = euler.y
	pitch = clampf(euler.x, -MAX_PITCH, MAX_PITCH)


## Turn by [param delta_angles] radians: x is yaw, y is pitch (up positive).
func look(delta_angles: Vector2) -> void:
	yaw = wrapf(yaw + delta_angles.x, -PI, PI)
	pitch = clampf(pitch + delta_angles.y, -MAX_PITCH, MAX_PITCH)


func basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)


func transform() -> Transform3D:
	return Transform3D(basis(), position)


## Fly for [param delta] seconds. [param move] is x right, y up (world up, so looking down
## and pressing up does not dive), z forward along the view; each in -1..1.
func step(move: Vector3, fast: bool, slow: bool, delta: float) -> Transform3D:
	var r := rules if rules != null else DotSpectatorRules.new()
	var speed := r.roam_speed
	if fast:
		speed *= r.roam_fast_scale
	elif slow:
		speed *= r.roam_slow_scale
	var b := basis()
	# Forward is -Z in Godot.
	var wish := b.x * move.x + Vector3.UP * move.y + (-b.z) * move.z
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	position += wish * speed * delta
	return transform()
