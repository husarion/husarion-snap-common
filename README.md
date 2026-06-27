# husarion-snap-common

Common configs for husarion snaps

## Usage

Add the following lines to the following files in your snap project.

### `snapcraft.yaml`

Add this to `parts`:

```yaml
  husarion-snap-common:
    plugin: dump
    source: https://github.com/husarion/husarion-snap-common
    source-branch: "0.3.0"
    source-type: git
    build-environment:
      - YQ_VERSION: "v4.35.1"
    build-packages:
      - curl
    organize:
      'local-ros/*.sh': usr/bin/
      'local-ros/*.xml': usr/share/husarion-snap-common/config/
      'local-ros/ros.env': usr/share/husarion-snap-common/config/
    override-build: |
      craftctl default
      curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${CRAFT_ARCH_BUILD_FOR}" -o $CRAFT_PART_BUILD/yq
    override-prime: |
      craftctl default
      cp $CRAFT_PART_BUILD/yq $CRAFT_PRIME/usr/bin/yq
      chmod +x $CRAFT_PRIME/usr/bin/yq
      rm -rf $CRAFT_PRIME/local-ros
```

> [!TIP]
>
> Optionally you can also add these lines to `snapraft.yaml` to `apps` for running a main `daemon` app (as long as it is named `daemon`):
> 
> ```yaml
>  start:
>    command: usr/bin/start_launcher.sh
>
>  stop:
>    command: usr/bin/stop_launcher.sh
> ```

### `hooks/configure`

```bash
#!/bin/bash -e

# The configure hook is called every time one the following actions happen:
# - initial snap installation
# - snap refresh
# - whenever the user runs snap set|unset to change a configuration option

source $SNAP/usr/bin/utils.sh

# your own code

$SNAP/usr/bin/configure_hook_ros.sh

# restart services with new ROS 2 config
for service in daemon some-other-service-1 some-other-service-2; do
  if snapctl services ${SNAP_NAME}.${service} | grep -qw enabled; then
    snapctl restart ${SNAP_NAME}.${service}
    log "Restarted ${SNAP_NAME}.${service}"
  fi
done
```

### `hooks/install`

```bash
#!/bin/bash -e

source $SNAP/usr/bin/utils.sh
$SNAP/usr/bin/install_hook_ros.sh

# your own code
```

---

## `husarion-agent/` subtree (v0.8.0+)

Shared substrate for snaps that embed the husarion-agent daemon
as a chained-agents follower (rosbot, husarion-rplidar,
husarion-depthai, …). Before this subtree existed each
consuming snap duplicated ~120 lines of launcher script, binary
fetch, and apply hooks.

### What lives here

The agent here is **files-first** (the v2 `--capabilities-*` / `--tier`
substrate was removed): the launcher seeds a config-root from a
snap-shipped `config-seed/` and the daemon reads/execs from it. Same-host
chaining is over the **snap content interface**, not a per-snap parent URL.

| Path | Role |
|---|---|
| `husarion-agent/fetch-binary.sh` | curl + sha256-verify the husarion-agent release binary into `${CRAFT_PART_BUILD}/husarion-agent`. Called from the consumer's `husarion-agent` part during `override-build`. Parameterised by `HA_VERSION` env; pulls from the `husarion-cockpit-releases` GitHub release. |
| `husarion-agent/launcher.sh` | Daemon launcher. Seeds the files-first config-root (`agent.yaml` / `follow.yaml` / `config/` / `hooks/` / `manifests/`) from `${SNAP}/usr/share/husarion-agent/config-seed/` into the writable `${SNAP_COMMON}/husarion-agent/`, selects content-interface chaining role by directory presence, then exec's the agent with `--socket` / `--state-dir` / `--config-root` / `--panels-default` / `--panels-overrides`. Reads only `HA_PEER_BIND` from env (cascading-primary listener). |
| `husarion-agent/configure-snap-to-files.sh` | Reverse bridge run from the consumer's `configure` hook (after `configure_hook_ros.sh`). On a node that OWNS the `network` concern, PUTs the just-set `ros.*` scalars + any changed `${SNAP_COMMON}/rmw` profile files into the agent's HTTP API so they propagate to downstream followers. Self-gating + loop-safe. |
| `husarion-agent/content-publish-primary.sh` | Provider (rosbot) side. Ensures the `${SNAP_COMMON}/agent-chain` slot dir + `requests/`/`certs/` exist so snapd's content bind-mount has a source and followers can drop CSRs. Idempotent; called from the install hook + connect-slot-agent-chain. |
| `husarion-agent/content-join-follower.sh` | Follower (rplidar/depthai) side. Idempotent same-host content-interface join: drops a CSR into the mounted `agent-chain-upstream` dir and waits for the provider to sign it. Authorization IS the snap content connection (no bootstrap token). |
| `husarion-agent/content-revoke-self.sh` | Follower side. On content-interface disconnect, drops a revoke marker into the still-mounted upstream dir so the provider auto-revokes this follower's cert. |
| `husarion-agent/panels.d/{20-health,40-info}.yaml` | Snap-agnostic standalone Manage panels (`health`, `info`) shipped inside every snap and served by its own embedded agent under strict confinement. Staged as `--panels-default`. |

### How a consumer snap pulls it in

Add to `parts:` (organize block extends the existing one for
`local-ros/`):

```yaml
husarion-snap-common:
  plugin: dump
  source: https://github.com/husarion/husarion-snap-common
  source-branch: "0.8.0"
  source-type: git
  build-environment:
    - YQ_VERSION: "v4.35.1"
  build-packages: [curl]
  organize:
    # …existing local-ros/* organize rules…
    # husarion-agent shared substrate (v0.8.0+, files-first):
    'husarion-agent/fetch-binary.sh':         usr/share/husarion-snap-common/husarion-agent/fetch-binary.sh
    'husarion-agent/launcher.sh':             usr/bin/husarion_agent_launcher.sh
    'husarion-agent/configure-snap-to-files.sh': usr/bin/configure-snap-to-files.sh
    'husarion-agent/content-publish-primary.sh': usr/bin/content-publish-primary.sh
    'husarion-agent/content-join-follower.sh':   usr/bin/content-join-follower.sh
    'husarion-agent/content-revoke-self.sh':     usr/bin/content-revoke-self.sh
    'husarion-agent/panels.d/*.yaml':         usr/share/husarion-agent/panels.d/
```

Add an `husarion-agent` part that runs `fetch-binary.sh`:

```yaml
husarion-agent:
  plugin: nil
  after: [husarion-snap-common]
  build-environment:
    - HA_VERSION: "0.8.0"
  build-packages: [curl]
  source: snap/husarion-agent-extras/
  source-type: local
  override-build: |
    set -euo pipefail
    craftctl default
    bash "${CRAFT_STAGE}/usr/share/husarion-snap-common/husarion-agent/fetch-binary.sh"
    install -Dm755 "${CRAFT_PART_BUILD}/husarion-agent" \
        "${CRAFT_PART_INSTALL}/usr/bin/husarion-agent"
  organize:
    # Per-snap files-first seed (identity + topology + initial config +
    # hooks + manifests). The launcher copies this into $SNAP_COMMON on boot.
    'config-seed/**': usr/share/husarion-agent/config-seed/
```

Add the `husarion-agent` daemon `app:`:

```yaml
husarion-agent:
  command: usr/bin/husarion_agent_launcher.sh
  daemon: simple
  install-mode: enable
  restart-condition: always
  plugs: [network, network-bind]
```

Only the cascading-primary (rosbot) sets `HA_PEER_BIND` at the snap level
so its agent opens an in-snap mTLS listener:

```yaml
environment:
  HA_PEER_BIND: "0.0.0.0:7444"   # rosbot only — cascading primary
```

Leaf followers omit `HA_PEER_BIND` entirely. There is no `HA_TIER`, no
`peer-join` app, and no `capabilities.d/` — the v2 capabilities substrate
was removed. Per-snap identity + topology live in the `config-seed/`
(`agent.yaml` / `follow.yaml` / `config/`), not in cap YAML.

### Same-host chaining over the snap content interface

Chaining is selected by **directory presence**, with no per-snap launcher
logic (see `launcher.sh`):

- **Provider (rosbot)** — its install hook calls `content-publish-primary.sh`
  to mint `${SNAP_COMMON}/agent-chain` (the content slot's `write:` source).
  Its presence makes the launcher add `--content-join-dir` so the agent
  advertises `ca.pem` + `primary.url` there and signs CSRs followers drop
  into `requests/`.
- **Follower (rplidar/depthai)** — snapd creates the plug target
  `${SNAP_COMMON}/agent-chain-upstream` only while the interface is
  connected. The launcher best-effort runs `content-join-follower.sh`
  (which execs `husarion-agent content-join`) in the background; the
  follow loop adopts the signed cert as soon as it lands. The follower's
  `disconnect-plug-agent-chain` hook calls `content-revoke-self.sh`.

Authorization IS the snap content connection — snapd only auto-connects
same-publisher snaps, so there's no bootstrap token. The connect/disconnect
plug+slot hooks in the consumer snap invoke these helpers (the launcher
also self-heals the follower join at boot).

Operators re-point or break the chain by editing the files-first config
(`follow.yaml` / the `network` concern) — not via a `peer.parent.<cap>`
snap option (that mechanism is gone). A node that owns the `network`
concern propagates its `ros.*` downstream via `configure-snap-to-files.sh`.

Requires husarion-agent v0.9.0+ (content-interface chaining).
