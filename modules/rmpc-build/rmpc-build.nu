#!/usr/bin/env nu

def cfg_get [cfg, key, fallback] {
  $cfg
    | get -o $key
    | default $fallback
}

def main [config] {
  let cfg = ($config | from json)

  let repository = (cfg_get $cfg "repository" "https://github.com/rmpc/rmpc.git")
  let branch = (cfg_get $cfg "branch" "master")
  let clone_dir = (cfg_get $cfg "clone_dir" "/tmp/rmpc")
  let output_bin = (cfg_get $cfg "output_bin" "/out/rmpc")
  
  let dnf_deps = [
    cargo
    clang
    gcc
    rustc
    git
  ]

  ^dnf install -y ...($dnf_deps)

  ^rm -rf $clone_dir
  ^git clone --depth 1 --branch $branch $repository $clone_dir
  ^cargo build --manifest-path ([$clone_dir "Cargo.toml"] | path join) --release --bin rmpc

  let release_rmpc = ([$clone_dir "target" "release" "rmpc"] | path join)

  ^install -Dm755 $release_rmpc $output_bin
}
