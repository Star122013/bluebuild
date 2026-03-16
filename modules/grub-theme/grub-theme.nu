#!/usr/bin/env nu

def cfg_get [cfg: record, key: string, fallback: any]: any {
  $cfg
    | get -i $key
    | default $fallback
}

def fail [msg: string]: nothing -> nothing {
  error make { msg: $msg }
}

def main [config: string]: nothing -> nothing {
  let cfg = $config | from json

  let repository = (
    $cfg
      | get -i repository
      | default ($cfg | get -i repo | default "")
  )
  if ($repository | is-empty) {
    fail "grub-theme: 'repository' is required"
  }

  let ref = (cfg_get $cfg "ref" (cfg_get $cfg "branch" "main"))
  let theme_dir = (cfg_get $cfg "theme_dir" "bsol")
  let theme_name = (
    $cfg
      | get -i theme_name
      | default $theme_dir
  )
  let install_root = (cfg_get $cfg "install_root" "/usr/share/grub/themes")
  let set_grub_theme = (cfg_get $cfg "set_grub_theme" true)
  let grub_defaults_file = (cfg_get $cfg "grub_defaults_file" "/usr/etc/default/grub")

  let tmp_root = (^mktemp -d /tmp/grub-theme.XXXXXX | str trim)
  let src_repo = ([$tmp_root "repo"] | path join)
  let src_theme = ([$src_repo $theme_dir] | path join)
  let dst_theme = ([$install_root $theme_name] | path join)
  let theme_txt = ([$dst_theme "theme.txt"] | path join)

  if ($ref | is-not-empty) {
    ^git clone --depth 1 --branch $ref $repository $src_repo
  } else {
    ^git clone --depth 1 $repository $src_repo
  }

  if not ($src_theme | path exists) {
    ^rm -rf $tmp_root
    fail $"grub-theme: theme directory '($theme_dir)' not found in repo '($repository)'"
  }

  ^install -d $install_root
  ^rm -rf $dst_theme
  ^cp -a $src_theme $dst_theme

  if not ($theme_txt | path exists) {
    ^rm -rf $tmp_root
    fail $"grub-theme: expected '($theme_txt)' not found after install"
  }

  if $set_grub_theme {
    if ($grub_defaults_file | path exists) {
      let lines = (open --raw $grub_defaults_file | lines)
      let has_key = ($lines | any {|line| $line | str starts-with "GRUB_THEME=" })

      if $has_key {
        let updated = (
          $lines
            | each {|line|
              if ($line | str starts-with "GRUB_THEME=") {
                $"GRUB_THEME=\"($theme_txt)\""
              } else {
                $line
              }
            }
            | str join (char nl)
        )
        $'($updated)(char nl)' | save -f $grub_defaults_file
      } else {
        let raw = (open --raw $grub_defaults_file)
        let nl = if ($raw | str ends-with (char nl)) { "" } else { (char nl) }
        $'($raw)($nl)GRUB_THEME="($theme_txt)"(char nl)' | save -f $grub_defaults_file
      }
    } else {
      print $"grub-theme: '($grub_defaults_file)' not found, skipping GRUB_THEME injection"
    }
  }

  ^rm -rf $tmp_root
}
