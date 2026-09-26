# dot-spectate

Who is watching whom, what the server lets them watch, and where the camera is.

**The distributable is `addons/dot_spectate/`.** It requires [dot-core](../dot-core), a
separate repository, and nothing else.

```bash
ln -s ../../dot-core/addons/dot_core addons/dot_core
```

## Why this exists

Every game in this family kills players and none of them had anywhere for a dead player to
look. dot-match has `spectating` as a flag on a `DotTeam` and `DotPlayerScore` — four
places that know somebody is not playing, and nothing that decides what they see.

**Spectating is a competitive-integrity system before it is a camera.** The camera is
about four lines of vector arithmetic. Everything else here exists because somebody used a
spectator view to cheat:

- A dead player calling out positions to the living.
- A streamer whose viewers read the map for them.
- A team-mate on a second machine, watching the other side.

The two features that matter are the **force-camera policy** and the **delay**, and both
have to live on the server, because a client that decides what it may look at is a client
that may look at anything.

## The one idea: it computes a transform and never touches a camera

`camera_of(key)` returns a `Transform3D`. `camera_2d_of(key)` returns a position and an
angle for a game on the XZ plane. A game assigns it to its own rig.

Same rule as dot-ui's "ships no art", and it is what lets one manager serve a 3D shooter's
`Camera3D`, a 2D arena's `Camera2D` and a headless suite with no camera at all — three
deployment shapes, no second code path.

## The pieces

| | |
| --- | --- |
| `DotSpectatorRules` | Every policy, layered like every `DotConfig` here. |
| `DotSpectatorView` | One viewer: a mode and a target, and the camera falls out. |
| `DotSpectatorHistory` | A bounded ring of where everybody was, for the delay. |
| `DotSpectatorManager` | The one node a game holds. |

## Decisions

### 1. Source's seven modes, and Source's numbering

`NONE`, `DEATH_CAM`, `FREEZE_CAM`, `FIXED`, `FIRST_PERSON`, `CHASE`, `ROAMING`. Kept
because twenty years of tooling, demo formats and server documentation says exactly this,
and an operator typing `mp_forcecamera 1` from memory should get what they expect.

### 2. "Own team only" also means first person

Source's rule and its reasoning: a chase camera behind a team-mate sees round corners that
team-mate cannot. `_permitted_mode()` downgrades a request rather than refusing it, and
says so in the log — a player who pressed a key and got a different camera with no
explanation reports it as a broken control.

### 3. The delay is why there is a history at all

A spectator watching live is a live intelligence feed. A broadcast relay's answer is ninety seconds
and a competitive server's is a few; either way the camera samples a tick in the past and
nothing else in the addon has to know that it did.

The ring is **bounded and the bound is validated** against the delay. A history that grows
with the round is a memory leak with a plausible name, and this family has already shipped
one — dot-timer's `max_replay_seconds` was a documented setting nothing read, which on a
server is a player idling in a run for hours.

### 4. The death-cam chain hands over, and that is the whole point of it

`on_death` → death cam → freeze cam → a real target. Three timers that have to hand over to
each other, and **every game that writes it itself gets the last hand-over wrong**: the
freeze camera ends, nothing takes over, and the player sits looking at their killer until
they respawn.

With nobody left to watch it falls back to a fixed camera rather than a first-person view
of nobody, which is the "sky in every direction" screenshot this family has already spent
three days on.

### 5. A sample with no history reports not-found

`DotSpectatorHistory.sample` returns `[Transform3D, found]`. Returning `Transform3D.IDENTITY`
alone would put a camera at the world origin looking down the X axis, which is
indistinguishable from a camera that is working and a world that has vanished.

### 6. Keyed by `String`, and `on_leave` is called after the roster drops them

The replacement target is chosen from `participants_fn`, so a game that reports the
departure *before* removing the player picks the player who just left. Documented at the
method, because it is the kind of ordering nobody guesses right twice.

### 7. A mirror is told, records its own history, and refuses to start the chain

A client's manager is a mirror (`authoritative = false`): the server sends each view with `to_wire` and the client `apply_wire`s it and computes the camera from the players it already draws. Three rules follow, each from a game that hit the opposite:

- **The wire carries the death position** (`"d"`). The death camera is the one mode whose place is not a player the mirror is drawing, and without it every client drew every death camera from the world origin. Two games carried it in their own events rather than wait (smash-copter's `SPECTATE`, buses' `adopt`); both keep their compact formats. A view from an older build with no `"d"` keeps the place the mirror had.
- **A mirror records the history when there is a delay.** With `delay_ticks > 0`, `camera_of` samples the ring and nothing else, and a mirror whose `advance` returned before recording drew every followed camera at identity the moment a server turned the delay on. The ring on a mirror is the delay's *display*. Its integrity is still the server's: a client sent live positions has them whatever its camera shows, so a server that means the delay withholds them from a spectator.
- **`on_death` on a mirror is refused with a `push_error`.** A mirror's `advance` runs no timers, so a chain started there is a death camera that never hands over — the failure decision 4 exists to prevent, one layer up. It is a wiring mistake, so it is the programmer's error rather than a log line. A game whose server sends no views at all (game-arena's client) runs its client manager *authoritative over its own camera* instead, from the kill events it already receives.

## The bug found by running it

**Auto-retargeting moved every player off their own killer on the tick after they died.**

The freeze camera shows your killer. Your killer is, by definition, on the other side —
which is exactly the target `force_camera 1` forbids. So the per-tick "is this target still
allowed" sweep fired on the freeze camera immediately, moved the view to a team-mate, and
wiped the timer while it was at it. On any server with the default policy, **nobody ever
saw who shot them.**

It is this family's usual shape wearing new clothes: a rule that is right in general and
wrong in the one case that matters, and invisible to every assertion about the camera's
*mode*, because the mode was right the whole time and only the target had moved. A timed
camera is the server's own choice and the retarget rule now leaves it alone.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/spectate_selftest.tscn   # 76 checks; one push_error on purpose (on_death on a mirror)
```

## Things deliberately not here

- **No camera node, no smoothing, no field-of-view.** A game's rig owns those, and a
  spectator camera that lerps is a spectator camera fighting the game's own lerp.
- **No free-camera controls.** `move_free()` takes a position and a basis; what the keys
  are is `DotFpsSampler`'s business, or the game's.
- **No demo recording.** dot-timer already has a replay format and a recorder; a second
  one here would be a second format.
- **No overview map or player list.** dot-ui, and the list comes from `targets_for()`.
- **No spectator chat channel.** dot-chat has scopes and a `membership_fn`; a "dead chat"
  channel is four lines there and would be a duplicate rule here.
