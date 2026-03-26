#!/usr/bin/env nu

def cfg_get [cfg, key, fallback] {
  $cfg
    | get -o $key
    | default $fallback
}

def fail [msg] {
  error make { msg: $msg }
}

def run_default_build [cargo_manifest, cargo_bin] {
  ^cargo build --manifest-path $cargo_manifest --release --bin $cargo_bin
}

def main [config] {
  let cfg = ($config | from json)

  let repository = (cfg_get $cfg "repository" "")
  if ($repository | is-empty) {
    fail "rust-build: 'repository' is required"
  }

  let branch = (cfg_get $cfg "branch" "")
  let clone_dir = (cfg_get $cfg "clone_dir" "/tmp/rust-build")
  let cargo_bin = (cfg_get $cfg "cargo_bin" "")

  if ($cargo_bin | is-empty) {
    fail "rust-build: 'cargo_bin' is required"
  }

  let output_bin = (cfg_get $cfg "output_bin" "")
  let extra_artifacts = (cfg_get $cfg "artifacts" [])
  let build_cmd = (cfg_get $cfg "build_cmd" [])

  # output_bin is the common case: install the built cargo binary directly.
  # artifacts is optional and can add extra files (desktop entries, scripts, etc).
  let base_artifacts = (
    if ($output_bin | is-empty) {
      []
    } else {
      [{
        source: $"target/release/($cargo_bin)"
        dest: $output_bin
        mode: "755"
      }]
    }
  )
  let artifacts = ([$base_artifacts $extra_artifacts] | flatten)

  if (($artifacts | length) == 0) {
    fail "rust-build: no install targets; set 'output_bin' or 'artifacts'"
  }

  let base_dnf_deps = [
    cargo
    clang
    gcc
    git
    rustc
  ]
  let extra_dnf_deps = (cfg_get $cfg "dnf_deps" [])
  # Always install the Rust toolchain set, then append module-specific deps.
  let dnf_deps = (
    [$base_dnf_deps $extra_dnf_deps]
      | flatten
      | uniq
  )

  ^dnf install -y ...($dnf_deps)

  ^rm -rf $clone_dir
  if ($branch | is-not-empty) {
    ^git clone --depth 1 --branch $branch $repository $clone_dir
  } else {
    ^git clone --depth 1 $repository $clone_dir
  }

  let cargo_manifest = ([$clone_dir "Cargo.toml"] | path join)

  # build_cmd is optional and supports two forms:
  # 1) list: ["cargo", "build", ...] (recommended, avoids shell parsing issues)
  # 2) string: "cargo build ..." (executed via bash -lc)
  # If omitted or empty, use the default cargo build command.
  let build_cmd_type = ($build_cmd | describe)
  if (($build_cmd_type | str starts-with "list<")) {
    if (($build_cmd | length) == 0) {
      run_default_build $cargo_manifest $cargo_bin
    } else {
      let cmd = (($build_cmd | first) | into string)
      let args = ($build_cmd | skip 1 | each {|arg| $arg | into string })
      if ($cmd | is-empty) {
        fail "rust-build: 'build_cmd' list cannot start with an empty command"
      }
      do {
        cd $clone_dir
        run-external $cmd ...$args
      }
    }
  } else if ($build_cmd_type == "string") {
    if ($build_cmd | is-empty) {
      run_default_build $cargo_manifest $cargo_bin
    } else {
      do {
        cd $clone_dir
        ^bash -lc $build_cmd
      }
    }
  } else {
    fail "rust-build: 'build_cmd' must be a string or list"
  }

  for artifact in $artifacts {
    let source = ($artifact | get -o source | default "")
    let dest = ($artifact | get -o dest | default "")
    let mode = (($artifact | get -o mode | default "644") | into string)

    if ($source | is-empty) {
      fail "rust-build: each artifact requires 'source'"
    }
    if ($dest | is-empty) {
      fail "rust-build: each artifact requires 'dest'"
    }

    # Relative sources are resolved against the cloned repository root.
    let source_path = (
      if ($source | str starts-with "/") {
        $source
      } else {
        ([$clone_dir $source] | path join)
      }
    )

    ^install $"-Dm($mode)" $source_path $dest
  }
}
