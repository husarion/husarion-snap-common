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
as a chained-agents follower (rosbot-snap, husarion-rplidar-snap,
husarion-camera-snap, …). Before this subtree existed each
consuming snap duplicated ~120 lines of launcher script, binary
fetch, and apply hooks.

### What lives here

| Path | Role |
|---|---|
| `husarion-agent/fetch-binary.sh` | curl + sha256-verify the husarion-agent release binary. Called from the consumer's `husarion-agent` part during `override-build`. Parameterised by `HA_VERSION` env. |
| `husarion-agent/launcher.sh` | Daemon launcher. Reads `HA_TIER` / `HA_PEER_BIND` from env. Stages shipped hooks into `${SNAP_COMMON}/husarion-agent/hooks.d/`, then exec's the daemon. |
| `husarion-agent/hooks.d/network_robot/10-snap-set.sh` | Generic apply hook for the `network_robot/ros_env` resource. Translates `HUSARION_AGENT_ROS_*` env vars → `snapctl set ros.*`. Same code on every snap. |
| `husarion-agent/hooks.d/drive/10-snap-set.sh` | Generic apply hook for the `drive/drive` resource. Translates `HUSARION_AGENT_MECANUM` / `CONFIGURATION` / `LED_STRIP` / `TF_NAMESPACE_BRIDGE` → `snapctl set driver.*`. Only fires on snaps whose schema understands those keys (rosbot today). Dead weight on leaf snaps but harmless. |

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
    # New v0.8.0 — husarion-agent shared substrate:
    'husarion-agent/fetch-binary.sh': usr/share/husarion-snap-common/husarion-agent/fetch-binary.sh
    'husarion-agent/launcher.sh':     usr/bin/husarion_agent_launcher.sh
    'husarion-agent/hooks.d/network_robot/10-snap-set.sh':
        usr/share/husarion-agent/hooks.d/network_robot/10-snap-set.sh
    'husarion-agent/hooks.d/drive/10-snap-set.sh':
        usr/share/husarion-agent/hooks.d/drive/10-snap-set.sh
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
    'capabilities.d/*.yaml': usr/share/husarion-agent/capabilities.d/
```

Add the two `apps:`:

```yaml
husarion-agent:
  command: usr/bin/husarion_agent_launcher.sh
  daemon: simple
  install-mode: enable
  restart-condition: always
  plugs: [network, network-bind]

peer-join:
  command: usr/bin/husarion-agent
  plugs: [network]
```

Set the per-snap env at the snap level so both apps see it:

```yaml
environment:
  HA_TIER: "robot"
  HA_PEER_BIND: "0.0.0.0:7444"   # rosbot only — cascading primary
```

Per-snap cap YAML lives in `snap/husarion-agent-extras/capabilities.d/`.
Each snap ships its own (~25 lines): different primary URL,
broadcast flag, cert paths.

### Operator-managed per-cap parent (`peer.parent.<cap>`)

The shipped cap YAMLs declare a hardcoded `follows:` block. The
operator can break or re-point it per cap, at runtime, without
editing YAML:

```bash
# Make the cockpit the parent for network_robot (default — matches
# what the shipped YAML hardcodes):
sudo snap set rosbot peer.parent.network-robot=https://cockpit.local:7443

# Standalone master for drive (robot owns its kinematics):
sudo snap unset rosbot peer.parent.drive
```

The consumer snap's `snap/hooks/configure` invokes the helper
shipped here, which materialises `$SNAP_COMMON/husarion-agent/peer-parents.yaml`
from `snapctl get peer.parent`:

```sh
# Inside snap/hooks/configure (consumer snap), after the
# usual driver/ros validation:
if [ -x "$SNAP/usr/share/husarion-snap-common/husarion-agent/configure-peer-parents.sh" ]; then
    sh "$SNAP/usr/share/husarion-snap-common/husarion-agent/configure-peer-parents.sh"
fi
```

The agent re-reads the file + restarts to pick up the new parent
on its next launch (the helper triggers a `snapctl restart`
automatically). Cap-name canonicalisation (kebab→snake) is
agent-side — `peer.parent.network-robot` resolves to the
`network_robot` cap without manual translation.

Requires husarion-agent v0.9.0+.
