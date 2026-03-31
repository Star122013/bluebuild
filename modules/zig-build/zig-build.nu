#!/usr/bin/env nu

def cfg_get [cfg, key, fallback] {
  $cfg | get -o $key | default $fallback
}

def fail [msg] {
  error make { msg: $msg }
}

# 统一生成产物清单：默认 zig-out/bin/<zig_bin> + 附加 artifacts
def collect_artifacts [output_bin, zig_bin, extra_artifacts] {
  let default_artifact = (
    if ($output_bin | is-empty) {
      []
    } else {
      [{
        source: $"zig-out/bin/($zig_bin)"
        dest: $output_bin
        mode: "755"
      }]
    }
  )

  [$default_artifact $extra_artifacts] | flatten
}

def run_build [clone_dir, build_cmd] {
  let build_cmd_type = ($build_cmd | describe)

  do {
    # 在源码目录执行构建，保证相对路径和 build.zig 可见
    cd $clone_dir

    if (($build_cmd_type | str starts-with "list<")) {
      if (($build_cmd | length) == 0) {
        # 默认优化级别使用 ReleaseFast
        ^zig build -Doptimize=ReleaseFast
      } else {
        let cmd = (($build_cmd | first) | into string)
        if ($cmd | is-empty) {
          fail "zig-build: 'build_cmd' list cannot start with an empty command"
        }
        let args = ($build_cmd | skip 1 | each {|arg| $arg | into string })
        run-external $cmd ...$args
      }
    } else if ($build_cmd_type == "string") {
      if ($build_cmd | is-empty) {
        ^zig build -Doptimize=ReleaseFast
      } else {
        # string 形式兼容旧配置，交给 bash 解释
        ^bash -lc $build_cmd
      }
    } else {
      fail "zig-build: 'build_cmd' must be a string or list"
    }
  }
}

def install_artifacts [clone_dir, artifacts] {
  for artifact in $artifacts {
    let source = ($artifact | get -o source | default "")
    let dest = ($artifact | get -o dest | default "")
    let mode = (($artifact | get -o mode | default "644") | into string)

    if ($source | is-empty) {
      fail "zig-build: each artifact requires 'source'"
    }
    if ($dest | is-empty) {
      fail "zig-build: each artifact requires 'dest'"
    }

    # 相对路径按 clone_dir 解析，绝对路径原样使用
    let source_path = (
      if ($source | str starts-with "/") {
        $source
      } else {
        ([$clone_dir $source] | path join)
      }
    )

    let source_type = (
      try {
        $source_path | path type
      } catch {
        ""
      }
    )

    if ($source_type == "dir") {
      # Directory artifact: treat 'dest' as target directory and copy all contents.
      ^mkdir -p $dest
      ^cp -a $"($source_path)/." $"($dest)/"
    } else {
      ^install $"-Dm($mode)" $source_path $dest
    }
  }
}

def main [config] {
  let cfg = ($config | from json)

  let repository = (cfg_get $cfg "repository" "")
  if ($repository | is-empty) {
    fail "zig-build: 'repository' is required"
  }

  let zig_bin = (cfg_get $cfg "zig_bin" "")
  if ($zig_bin | is-empty) {
    fail "zig-build: 'zig_bin' is required"
  }

  let branch = (cfg_get $cfg "branch" "")
  let clone_dir = (cfg_get $cfg "clone_dir" "/tmp/zig-build")
  let build_cmd = (cfg_get $cfg "build_cmd" [])
  let output_bin = (cfg_get $cfg "output_bin" "")
  let extra_artifacts = (cfg_get $cfg "artifacts" [])

  let artifacts = (collect_artifacts $output_bin $zig_bin $extra_artifacts)
  if (($artifacts | length) == 0) {
    fail "zig-build: no install targets; set 'output_bin' or 'artifacts'"
  }

  let dnf_deps = (
    [[gcc git zig] (cfg_get $cfg "dnf_deps" [])]
      | flatten
      | uniq
  )

  # 安装 Zig 构建所需依赖后再执行 clone/build/install
  ^dnf install -y ...($dnf_deps)

  ^rm -rf $clone_dir
  if ($branch | is-not-empty) {
    ^git clone --depth 1 --branch $branch $repository $clone_dir
  } else {
    ^git clone --depth 1 $repository $clone_dir
  }

  run_build $clone_dir $build_cmd
  install_artifacts $clone_dir $artifacts
}
