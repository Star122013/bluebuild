#!/usr/bin/env nu

def cfg_get [cfg, key, fallback] {
  $cfg
    | get -o $key
    | default $fallback
}

def fail [msg] {
  error make { msg: $msg }
}

def normalize_features [value] {
  let kind = ($value | describe)

  if $kind == "nothing" {
    []
  } else if ($kind | str starts-with "list") {
    $value
      | each {|item| $item | into string | str trim}
      | where {|item| not ($item | is-empty)}
  } else {
    $value
      | into string
      | split row ","
      | each {|item| $item | str trim}
      | where {|item| not ($item | is-empty)}
  }
}

def main [config] {
  let cfg = ($config | from json)

  let repository_raw = (
    $cfg
      | get -o repository
      | default ($cfg | get -o repo | default "https://nest.pijul.com/pijul/pijul")
  )

  if ($repository_raw | is-empty) {
    fail "pijul-build: 'repository' is required"
  }

  let parsed_ref = if (
    ($repository_raw | str starts-with "https://")
      or ($repository_raw | str starts-with "http://")
  ) {
    $repository_raw
      | parse -r '^(?<remote>https?://.+):(?<ref_channel>[^/]+)/(?<ref_state>[^/]+)$'
  } else {
    []
  }

  let repository = if ($parsed_ref | is-empty) {
    $repository_raw
  } else {
    $parsed_ref.0.remote
  }
  let inferred_channel = if ($parsed_ref | is-empty) { "main" } else { $parsed_ref.0.ref_channel }
  let inferred_state = if ($parsed_ref | is-empty) { "" } else { $parsed_ref.0.ref_state }

  let channel = (
    $cfg
      | get -o channel
      | default (cfg_get $cfg "branch" $inferred_channel)
  )
  let state = (cfg_get $cfg "state" $inferred_state)
  let clone_dir = (cfg_get $cfg "clone_dir" "/tmp/pijul")
  let output_bin = (cfg_get $cfg "output_bin" "/out/pijul")
  let features = (normalize_features (cfg_get $cfg "features" "git"))
  let bootstrap_root = (cfg_get $cfg "bootstrap_root" "/tmp/pijul-bootstrap")
  let bootstrap_version = (cfg_get $cfg "bootstrap_version" "~1.0.0-beta")

  let dnf_deps = [
    cargo
    clang
    gcc
    git
    make
    pkgconf-pkg-config
    rustc
    dbus-devel
    libsodium-devel
    libzstd-devel
    openssl-devel
    xxhash-devel
  ]

  ^dnf install -y ...($dnf_deps)

  ^rm -rf $bootstrap_root
  ^cargo install --locked --root $bootstrap_root --version $bootstrap_version pijul

  let bootstrap_pijul = ([$bootstrap_root "bin" "pijul"] | path join)
  if not ($bootstrap_pijul | path exists) {
    fail $"pijul-build: bootstrap binary not found at '($bootstrap_pijul)' after cargo install"
  }

  ^rm -rf $clone_dir

  mut clone_args = [clone]
  if ($channel | is-not-empty) {
    $clone_args = ($clone_args | append "--channel" | append $channel)
  }
  if ($state | is-not-empty) {
    $clone_args = ($clone_args | append "--state" | append $state)
  }
  $clone_args = ($clone_args | append $repository | append $clone_dir)
  run-external $bootstrap_pijul ...$clone_args

  mut cargo_args = [
    build
    --manifest-path
    ([$clone_dir "Cargo.toml"] | path join)
    --release
    --package
    pijul
    --bin
    pijul
  ]

  if not ($features | is-empty) {
    $cargo_args = ($cargo_args | append "--features" | append ($features | str join ","))
  }

  ^cargo ...$cargo_args

  let release_bin = ([$clone_dir "target" "release" "pijul"] | path join)
  ^install -Dm755 $release_bin $output_bin
}
