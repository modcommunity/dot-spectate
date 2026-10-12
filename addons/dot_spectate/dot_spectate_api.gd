extends RefCounted

## dot-spectate's API level. The rule for bumping it is on dot-core's DotAddonApi.
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning.

# 1: everything before this file existed.
# 2: DotSpectatorManager.camera_world and camera_mask: chase and death cameras pulled out
#    of the level through dot-core's DotCameraProbe (needs dot-core API 5).
const LEVEL := 2
const OLDEST := 1
