#!/usr/bin/env nu

def cfg_get [cfg, key, fallback] {
  $cfg | get -o $key | default $fallback
}

def fail [msg] {
  error make { msg: $msg }
}

# 统一生成产物清单：默认二进制 + 用户附加 artifacts
def collect_artifacts [output_bin, cargo_bin, extra_artifacts] {
  let default_artifact = (
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

  [$default_artifact $extra_artifacts] | flatten
}

def run_build [clone_dir, cargo_bin, build_cmd] {
  let build_cmd_type = ($build_cmd | describe)
  let home_dir = ($env | get -o HOME | default "/root")
  let cargo_home = ($env | get -o CARGO_HOME | default ([$home_dir ".cargo"] | path join))
  let cargo_bin_dir = ([$cargo_home "bin"] | path join)
  let current_path = ($env | get -o PATH | default "")
  # 兼容 xtask 内部调用 `cargo install` 后立刻执行新安装的二进制（例如 forge）
  let path_with_cargo_bin = (
    if ($current_path | is-empty) {
      $cargo_bin_dir
    } else if (($current_path | split row ":" | any {|p| $p == $cargo_bin_dir })) {
      $current_path
    } else {
      $"($cargo_bin_dir):($current_path)"
    }
  )

  with-env { PATH: $path_with_cargo_bin } {
    do {
      # 强制在源码目录执行，避免 build_cmd 在错误目录运行
      cd $clone_dir

      # list 形式最稳，避免 shell 字符串解析歧义
      if (($build_cmd_type | str starts-with "list<")) {
        if (($build_cmd | length) == 0) {
          # 未覆盖时走默认 Rust release 构建
          ^cargo build --release --bin $cargo_bin
        } else {
          let cmd = (($build_cmd | first) | into string)
          if ($cmd | is-empty) {
            fail "rust-build: 'build_cmd' list cannot start with an empty command"
          }
          let args = ($build_cmd | skip 1 | each {|arg| $arg | into string })
          run-external $cmd ...$args
        }
      } else if ($build_cmd_type == "string") {
        if ($build_cmd | is-empty) {
          ^cargo build --release --bin $cargo_bin
        } else {
          # string 形式兼容旧配置，交给 bash 解释
          ^bash -lc $build_cmd
        }
      } else {
        fail "rust-build: 'build_cmd' must be a string or list"
      }
    }
  }
}

def install_artifacts [clone_dir, artifacts] {
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

    # 相对路径按 clone_dir 解析，绝对路径原样使用
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

def main [config] {
  let cfg = ($config | from json)

  let repository = (cfg_get $cfg "repository" "")
  if ($repository | is-empty) {
    fail "rust-build: 'repository' is required"
  }

  let cargo_bin = (cfg_get $cfg "cargo_bin" "")
  if ($cargo_bin | is-empty) {
    fail "rust-build: 'cargo_bin' is required"
  }

  let branch = (cfg_get $cfg "branch" "")
  let clone_dir = (cfg_get $cfg "clone_dir" "/tmp/rust-build")
  let build_cmd = (cfg_get $cfg "build_cmd" [])
  let output_bin = (cfg_get $cfg "output_bin" "")
  let extra_artifacts = (cfg_get $cfg "artifacts" [])

  let artifacts = (collect_artifacts $output_bin $cargo_bin $extra_artifacts)
  if (($artifacts | length) == 0) {
    fail "rust-build: no install targets; set 'output_bin' or 'artifacts'"
  }

  let dnf_deps = (
    [[cargo clang gcc git rustc] (cfg_get $cfg "dnf_deps" [])]
      | flatten
      | uniq
  )

  # 先安装工具链和系统依赖，再进行 clone/build/install
  ^dnf install -y ...($dnf_deps)

  ^rm -rf $clone_dir
  if ($branch | is-not-empty) {
    ^git clone --depth 1 --branch $branch $repository $clone_dir
  } else {
    ^git clone --depth 1 $repository $clone_dir
  }

  run_build $clone_dir $cargo_bin $build_cmd
  install_artifacts $clone_dir $artifacts
}
