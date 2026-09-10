@tool
class_name DotSpectatorRules
extends DotConfig

## Every policy about watching, in one layered configuration.
##
## [b]Spectating is a competitive-integrity system before it is a camera.[/b] Almost
## everything here exists because somebody used a spectator camera to cheat: a dead
## player calling out positions, a streamer's viewers reading the map, a teammate on a
## second monitor. The camera part is four lines; the rest is who may see what.

@export_group("Who may watch whom")

## 0 anybody, 1 own team only, 2 nobody.
##
## Source's [code]mp_forcecamera[/code], and the numbering is deliberately Source's
## because server operators type it from memory. "Own team only" also forces first
## person, because a chase camera behind a team-mate sees round corners they cannot.
@export_enum("all", "team", "none") var force_camera: int = 1

## Whether a dead player may watch at all before the round ends.
@export var allow_while_dead: bool = true

## Whether a player who has not joined a side may watch.
@export var allow_unassigned: bool = true

## Whether a live player may spectate. Off, obviously, and the setting exists because a
## replay viewer and a demo playback are both live processes with nobody playing.
@export var allow_while_alive: bool = false

## Whether free-roaming is offered.
##
## Off with [member force_camera] anything but "all": a roaming camera goes anywhere,
## which is the whole problem.
@export var allow_roaming: bool = false

@export_group("Cameras")

## Ticks the death camera holds on the body before anything else happens.
@export_range(0, 100000, 1) var death_cam_ticks: int = 128

## Ticks the freeze camera holds on the killer afterwards. Zero skips it.
@export_range(0, 100000, 1) var freeze_cam_ticks: int = 192

## How far behind a target the chase camera sits.
@export_range(0.1, 100.0, 0.1, "or_greater") var chase_distance: float = 3.5

## How far above them.
@export_range(-10.0, 100.0, 0.1, "or_greater") var chase_height: float = 0.8

## What the camera does when its target dies or leaves.
##
## On, and it is not a nicety: a spectator whose target disconnects is looking at
## nothing, with no input that obviously fixes it, and reports it as the game freezing.
@export var auto_retarget: bool = true

## Whether the cycle order includes dead players.
@export var cycle_includes_dead: bool = false

@export_group("Delay")

## Ticks of delay between what happens and what a spectator sees.
##
## [b]This is the anti-stream-sniping setting and it is the reason this addon keeps a
## history at all.[/b] A spectator watching live is a live intelligence feed: a player
## on a second machine, a streamer's chat, a teammate who died first. SourceTV's answer
## is ninety seconds and a competitive server's is a few; either way the camera samples
## a tick in the past and the whole rest of the addon does not have to know.
##
## Zero is live, which is what a suite and a single-player replay want.
@export_range(0, 100000, 1) var delay_ticks: int = 0

## How many ticks of pose history to keep. Clamped up to [member delay_ticks] + 1.
##
## Bounded on purpose: a history that grows with the round is a memory leak with a
## plausible name, and this family has shipped one of those in a recorder already —
## dot-timer's [code]max_replay_seconds[/code] was a setting nothing read.
@export_range(2, 100000, 1) var history_ticks: int = 128


func env_prefix() -> String:
	return "DOT_SPECTATE_"


func cli_prefix() -> String:
	return "spectate-"


func validate() -> DotResult:
	if allow_roaming and force_camera != 0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"Roaming is allowed and the camera is restricted to %s. A roaming "
				+ "camera goes anywhere, which is the whole thing the restriction is "
				+ "for — one of the two settings is not the one that was meant."
			) % ("own team" if force_camera == 1 else "nobody")
		)

	if delay_ticks > 0 and history_ticks <= delay_ticks:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"A delay of %d ticks needs more than %d ticks of history, or the "
				+ "camera asks for a tick that has already been thrown away and "
				+ "silently shows the oldest one it still has."
			) % [delay_ticks, history_ticks]
		)

	return DotResult.success(null)


## Whether the policy forces first person regardless of what a viewer asked for.
func forces_first_person() -> bool:
	return force_camera == 1


func forbids_everything() -> bool:
	return force_camera == 2
