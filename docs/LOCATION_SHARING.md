# Architecture notes — Medicine Compass location sharing
#
# Current behavior (battery-first):
# - GPS + POST /location/update run ONLY while the compass view for a person is open.
# - GET /location/:id also runs only then.
# - So if A opens compass toward B, A sees B's LAST known position on the server.
# - If B is not currently sharing (compass closed / app closed), A's arrow uses stale data.
#
# Recommended roadmap:
# 1) Foreground share (app open, any screen): slow upload every ~30–60s while app is resumed.
# 2) Opt-in "Share my location" with Android foreground service + persistent notification.
# 3) True background (Doze / killed app) only if needed — battery + Play policy heavy.
#
# Pairing is independent of live GPS: QR request/accept only creates the peer link.
