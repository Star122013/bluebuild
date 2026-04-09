#!/bin/nu

def cfg_get [cfg, key, fallback] {
  $cfg | get -o $key | default fallback
}

def fail [msg] {
  error make {msg: $msg}
}

def run_build [clone_dir, build_cmd] {
  let build_cmd_type = ($build_cmd | describe )

  do { 
    cd $clone_dir
    
    if ($build_cmd_type | str starts-with "list<") {
      if (($build_cmd | length) == 0) {
        ^go build .
      } else {
        let cmd = ($build_cmd | first | into string)
        let args = ($build_cmd | skip 1 | each {|arg| $arg | into string })
        run-external $cmd ...$args
      }
    }
    else if ($build_cmd_type == string) {
      if ($build_cmd | is-empty) {
        ^go build .
      }else{
        ^bash -lc $build_cmd
      }
    }
  }
}

def main [config] {
  let cfg = ($config | from json )
  let repo = (cfg_get $cfg "repository" "")
  let branch = (cfg_get $cfg "branch" "main")
  let clone_dir = (cfg_get $cfg "clone_dir" "/tmp/go-build")
  let build_cmd = (cfg_get $cfg "build_cmd" [])
  let output_bin = ($build_cmd | last)
  let bin_name = ["/out", ($output_bin | path basename )] | path join
  let dnf_deps = (
    [[gcc go git] (cfg_get $cfg dnf_deps [])]
    | flatten 
    | uniq 
    )
    
  ^dnf install -y ...$dnf_deps

  ^rm -rf $clone_dir
  ^git clone $repo -b $branch --depth=1 $clone_dir

  run_build $clone_dir $build_cmd
  ^install -Dm 755 $output_bin $bin_name
}
