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
> ```bash
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
