#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# Packages are not installed and no file manager opens here; vulkaninfo reports
# whatever device the case asks for, or fails the way it does when no device
# enumerates.
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/omarchy-pkg-add"
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/nautilus"
cat >"$tmp/bin/vulkaninfo" <<'SH'
#!/bin/bash
[[ -n ${VULKAN_DEVICE_TYPE:-} ]] || exit 1
echo "GPU0:"
echo "	deviceType         = PHYSICAL_DEVICE_TYPE_$VULKAN_DEVICE_TYPE"
SH
chmod +x "$tmp/bin/"*

video_driver_for() {
  local home="$tmp/home-$1"

  mkdir -p "$home"
  HOME="$home" VULKAN_DEVICE_TYPE=$1 PATH="$tmp/bin:$PATH" \
    "$ROOT/bin/omarchy-install-gaming-retroarch" >/dev/null
  sed -n 's/^video_driver = "\(.*\)"$/\1/p' "$home/.config/retroarch/retroarch.cfg"
}

for type in INTEGRATED_GPU DISCRETE_GPU; do
  [[ $(video_driver_for "$type") == "vulkan" ]] || fail "RetroArch uses Vulkan on a $type"
done
pass "RetroArch uses Vulkan when a GPU provides a Vulkan device"

# Lavapipe enumerates as a CPU device: RetroArch would start, but software
# Vulkan is far slower than the GPU's OpenGL.
[[ $(video_driver_for CPU) == "glcore" ]] || fail "RetroArch skips a CPU-only Vulkan device"
pass "RetroArch skips a CPU-only Vulkan device"

[[ $(video_driver_for "") == "glcore" ]] || fail "RetroArch falls back to glcore without a Vulkan device"
pass "RetroArch falls back to glcore without a Vulkan device"
