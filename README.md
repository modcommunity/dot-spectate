This is the **spectate** asset for TMC's **Dot** collection. It adds the part of a multiplayer game that decides who may watch whom, what they are allowed to see, and where the camera goes.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Spectating is a competitive-integrity system before it is a camera

The camera is four lines of vector arithmetic. Everything else exists because somebody used a spectator view to cheat: a dead player calling out positions, a streamer whose viewers read the map, a team-mate on a second machine watching the other side.

Two features answer that, and both live on the server:

- **A force-camera policy.** `all`, `own team only`, or `nobody`, spelled `mp_forcecamera`, with the numbering operators already type from memory. "Own team only" also forces first person, because a chase camera behind a team-mate sees round corners that team-mate cannot.
- **A delay.** The camera samples a tick in the past, so a spectator is not a live intelligence feed. Ninety seconds is the usual broadcast default; a competitive server's is a few.

## It computes a transform and touches no camera

```gdscript
spectate.advance(tick)                              # once a tick
camera.global_transform = spectate.camera_of(me)    # once a frame
```

which is what lets one manager serve a 3D shooter's `Camera3D`, a 2D arena's `Camera2D` (`camera_2d_of` gives a position and an angle) and a headless suite with no camera at all.

## The death-camera chain

```gdscript
spectate.on_death("ada", where_they_fell, "bob", tick)
```

Death cam on the body, freeze cam on the killer, then a real target. Three timers that hand over to each other, and the last hand-over is the one every game that writes it itself gets wrong, leaving the player looking at their killer until they respawn.

## Using it

```gdscript
var spectate := DotSpectatorManager.new()
spectate.participants_fn = roster.keys
spectate.team_fn = match_node.team_of
spectate.alive_fn = world.is_alive
spectate.pose_fn = world.eye_transform_of     # eyes, not the body's origin
spectate.setup()
add_child(spectate)

spectate.next_target(me)      # cycle
spectate.set_mode(me, DotSpectatorView.Mode.CHASE)
```

A client draws its cycle list from `targets_for(me)` and greys entries out with `may_watch(me, them)`, so it never shows a name the server would refuse.

## Installing

Copy `addons/dot_spectate/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-spectate in **Project → Project Settings → Plugins**.

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core). Nothing else.

## Licence

MIT. See [LICENSE](LICENSE).
