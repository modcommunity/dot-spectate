# dot-spectate history

Kept because each could come back. The live rules are in [design.md](design.md).

## Nobody saw who shot them

Auto-retargeting moved every player off their own killer on the tick after they died. The freeze camera shows your killer, and your killer is on the other side, which is exactly the target `force_camera 1` forbids. So the per-tick "is this target still allowed" sweep fired on the freeze camera immediately, moved the view to a team-mate, and wiped the timer while it was at it. On any server with the default policy, nobody ever saw who shot them.

A rule that is right in general and wrong in the one case that matters, and invisible to every assertion about the camera's mode, because the mode was right the whole time and only the target had moved. Assert the target too.

## A bound nothing read

The history ring is validated against the delay because dot-timer once shipped `max_replay_seconds` as a documented setting nothing read, which on a server is a player idling in a run for hours. See [bugs-found](../../../docs/bugs-found.md).

## Mirrors drew from the origin

Before the wire carried `"d"`, every client drew every death camera from the world origin; before a mirror recorded history, turning on a delay put every followed camera at identity. Both are now rules in [design.md](design.md#a-mirror-is-told-records-its-own-history-and-refuses-to-start-the-chain).
