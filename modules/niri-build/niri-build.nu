#!/usr/bin/env nu

def cfg_get [cfg: record, key: string, fallback: any]: any {
  $cfg
    | get -i $key
    | default $fallback
}

def main [config: string]: nothing -> nothing {
  let cfg = $config | from json

  let repository = (cfg_get $cfg "repository" "https://github.com/niri-wm/niri.git")
  let branch = (cfg_get $cfg "branch" "wip/branch")
  let clone_dir = (cfg_get $cfg "clone_dir" "/tmp/niri")
  let output_bin = (cfg_get $cfg "output_bin" "/out/niri")
  let output_runtime = (cfg_get $cfg "output_runtime" "/out/runtime")

  let dnf_deps = [
    cargo
    clang
    gcc
    git
    rustc
    cairo-gobject-devel
    dbus-devel
    fontconfig-devel
    libXcursor-devel
    libadwaita-devel
    libdisplay-info-devel
    libinput-devel
    libseat-devel
    libudev-devel
    libxkbcommon-devel
    mesa-libEGL-devel
    mesa-libgbm-devel
    pango-devel
    pipewire-devel
    systemd-devel
    wayland-devel
  ]

  ^dnf install -y ...($dnf_deps)

  ^rm -rf $clone_dir
  ^git clone --depth 1 --branch $branch $repository $clone_dir
  ^cargo build --manifest-path ([$clone_dir "Cargo.toml"] | path join) --release --bin niri

  let release_niri = ([$clone_dir "target" "release" "niri"] | path join)
  let resources = ([$clone_dir "resources"] | path join)

  ^install -Dm755 $release_niri $output_bin
  ^install -Dm755 ([$resources "niri-session"] | path join) ([$output_runtime "usr" "bin" "niri-session"] | path join)
  ^install -Dm644 ([$resources "niri.desktop"] | path join) ([$output_runtime "usr" "share" "wayland-sessions" "niri.desktop"] | path join)
  ^install -Dm644 ([$resources "niri-portals.conf"] | path join) ([$output_runtime "usr" "share" "xdg-desktop-portal" "niri-portals.conf"] | path join)
  ^install -Dm644 ([$resources "niri.service"] | path join) ([$output_runtime "usr" "lib" "systemd" "user" "niri.service"] | path join)
  ^install -Dm644 ([$resources "niri-shutdown.target"] | path join) ([$output_runtime "usr" "lib" "systemd" "user" "niri-shutdown.target"] | path join)
}
