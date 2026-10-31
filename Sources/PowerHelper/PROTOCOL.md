# Power helper protocol

The app invokes the bundled executable as `install <uid>` through macOS administrator authorization. The helper copies itself to `/Library/PrivilegedHelperTools/com.yeonza.LidKeeper.helper`, writes `/Library/LaunchDaemons/com.yeonza.LidKeeper.helper.plist`, and enrolls that user. An existing session prevents installation/update. The daemon is started with `RunAtLoad` and `KeepAlive`; its loop runs once per second.

After installation, wait for a fresh `status.json` before submitting requests. Requests and heartbeats must be atomically replaced, owned by the enrolled UID, mode 0600, regular, singly linked files in `/var/run/LidKeeper/<uid>/` (same directory as `/private/var/run/LidKeeper/<uid>/`). No shell commands are accepted.

`request.json`:

```json
{"id":"UUID","command":"start","sessionID":"UUID","pid":1234,"durationSeconds":3600,"acOnly":true}
```

`command` accepts `start` or `stop`. Every request has a new ID; a stop carries the original session ID and the same complete schema. Duration must be 60–86400 seconds. A stop from another UID or session is rejected. The daemon ignores requests older than 30 seconds and those predating daemon startup, preventing restart replay.

Helper 1.1.0 removes the battery-percentage cutoff. Neither requests nor persisted sessions contain `batteryFloor`. Its decoder accepts both the new schema and older JSON containing that extra field; the old field is ignored and cannot reinstate a cutoff. Existing ownership records remain recoverable on daemon restart. New-schema requests require helper 1.1.0; this compatibility does not change the behavior of an older installed helper.

Helper 1.1.1 fixes a pipe file-descriptor leak during repeated `pmset` reads, which could exhaust daemon resources after extended uptime and cause IPC requests to time out. The request, status and persisted-session schemas and power-control rules are unchanged. STILL 1.9.5 (build 23) requires this helper update; upgrading the installed service uses macOS administrator authorization once. End any active session before updating.

`heartbeat.json` contains `{"sessionID":"UUID"}`. Replace it every three seconds. Stale, unchanged, wrong-session or unsafe files do not renew the 15-second monotonic watchdog. The app PID must remain alive and belong to the enrolled UID. Deadline uses `mach_continuous_time` and cannot be extended by wall-clock changes.

`/Library/Application Support/LidKeeper/status.json` is root-owned mode 0644 and updated every healthy daemon tick. Fields: `version` (1), `helperVersion` ("1.1.1"), `enabled`, optional `sessionID`, `ownerUID`, `expiresAt` (Unix seconds), `lastRequestID`, `reason`, `message` (Chinese user-facing text), `updatedAt` (Unix seconds). `enabled` describes a healthy owned session; it is false during failed recovery. UI must treat `restore_failed` as an error and independently inspect actual sleep state.

The root-owned, mode 0600 `session.json` ownership intent is fsynced before enabling sleep prevention. The helper refuses to claim a pre-existing external SleepDisabled setting. It changes only the fixed `pmset -a disablesleep 1|0` command, then checks both preference and IORegistry state. On normal stop, app exit, lost heartbeat, timeout, AC disconnect in AC-only mode, unknown battery reading while on battery, or serious/critical thermal state, it restores 0. Health read failures restore conservatively. Battery percentage alone never blocks starting or ends a session, including readings of 15%, 14%, 1%, or 0%; the unknown-reading, AC-only and thermal checks still apply. Failed restoration retains ownership and retries. Every daemon restart first restores its persisted session, before reading user-controlled IPC paths.

`helper check` is an unprivileged, read-only hardware/state probe. `helper status` prints the public JSON. `helper uninstall` requires administrator authorization, restores any root-owned session record and verifies success before unloading/removing the service. With no ownership record it leaves external sleep overrides unchanged. It never recursively deletes user IPC directories.

The setting is system-wide and persistent, not limited to lid sleep. Apple's current `pmset(1)` manual does not document it. Apple source implements it in [`pmset.m`](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m). Stock macOS without a customized setting can omit the key; the helper treats successful IORegistry dictionary retrieval with an absent key as the default false, while writes require an explicit confirmed value.

Tests compile `SessionCore.swift`, `SecureFiles.swift`, `SystemPower.swift`, and `Tests/HelperTests/HelperTests.swift` (excluding the production main). They use mocks and temporary files only: no sudo, helper installation, or system power changes.
