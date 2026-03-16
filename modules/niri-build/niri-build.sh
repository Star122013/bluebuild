#!/usr/bin/env bash

set -euo pipefail

CONFIG_JSON="${1:-{}}"

jq_str() {
  local query="$1"
  jq -r "${query} // empty" <<<"${CONFIG_JSON}"
}

repository="$(jq_str '.repository')"
branch="$(jq_str '.branch')"
clone_dir="$(jq_str '.clone_dir')"
output_bin="$(jq_str '.output_bin')"
output_runtime="$(jq_str '.output_runtime')"

repository="${repository:-https://github.com/niri-wm/niri.git}"
branch="${branch:-wip/branch}"
clone_dir="${clone_dir:-/tmp/niri}"
output_bin="${output_bin:-/out/niri}"
output_runtime="${output_runtime:-/out/runtime}"

dnf install -y \
  cargo \
  clang \
  gcc \
  git \
  rustc \
  cairo-gobject-devel \
  dbus-devel \
  fontconfig-devel \
  libXcursor-devel \
  libadwaita-devel \
  libdisplay-info-devel \
  libinput-devel \
  libseat-devel \
  libudev-devel \
  libxkbcommon-devel \
  mesa-libEGL-devel \
  mesa-libgbm-devel \
  pango-devel \
  pipewire-devel \
  systemd-devel \
  wayland-devel

rm -rf "${clone_dir}"
git clone --depth 1 --branch "${branch}" "${repository}" "${clone_dir}"
cargo build --manifest-path "${clone_dir}/Cargo.toml" --release --bin niri

install -Dm755 "${clone_dir}/target/release/niri" "${output_bin}"
install -Dm755 "${clone_dir}/resources/niri-session" "${output_runtime}/usr/bin/niri-session"
install -Dm644 "${clone_dir}/resources/niri.desktop" "${output_runtime}/usr/share/wayland-sessions/niri.desktop"
install -Dm644 "${clone_dir}/resources/niri-portals.conf" "${output_runtime}/usr/share/xdg-desktop-portal/niri-portals.conf"
install -Dm644 "${clone_dir}/resources/niri.service" "${output_runtime}/usr/lib/systemd/user/niri.service"
install -Dm644 "${clone_dir}/resources/niri-shutdown.target" "${output_runtime}/usr/lib/systemd/user/niri-shutdown.target"
