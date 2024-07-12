# husarion-snap-common

Common configs for husarion snaps

## Usage

Add this part to `parts` in `snapcraft.yaml`:

```yaml
  husarion-snap-common:
    plugin: dump
    source: https://github.com/husarion/husarion-snap-common
    source-branch: "0.1.0"
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