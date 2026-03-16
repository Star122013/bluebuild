#!/usr/bin/env bash

set -euo pipefail

CONFIG_JSON="${1:-{}}"

jq_str() {
  local query="$1"
  jq -r "${query} // empty" <<<"${CONFIG_JSON}"
}

repository="$(jq_str '.repository')"
repo_alias="$(jq_str '.repo')"
ref="$(jq_str '.ref')"
branch_alias="$(jq_str '.branch')"
theme_dir="$(jq_str '.theme_dir')"
theme_name="$(jq_str '.theme_name')"
install_root="$(jq_str '.install_root')"
set_grub_theme="$(jq -r '.set_grub_theme // true | tostring' <<<"${CONFIG_JSON}")"
grub_defaults_file="$(jq_str '.grub_defaults_file')"

repository="${repository:-${repo_alias}}"
if [[ -z "${repository}" ]]; then
  echo "grub-theme: 'repository' is required" >&2
  exit 1
fi

ref="${ref:-${branch_alias:-main}}"
theme_dir="${theme_dir:-bsol}"
theme_name="${theme_name:-${theme_dir}}"
install_root="${install_root:-/usr/share/grub/themes}"
grub_defaults_file="${grub_defaults_file:-/usr/etc/default/grub}"

tmp_root="$(mktemp -d /tmp/grub-theme.XXXXXX)"
src_repo="${tmp_root}/repo"
src_theme="${src_repo}/${theme_dir}"
dst_theme="${install_root}/${theme_name}"
theme_txt="${dst_theme}/theme.txt"

cleanup() {
  rm -rf "${tmp_root}"
}
trap cleanup EXIT

if [[ -n "${ref}" ]]; then
  git clone --depth 1 --branch "${ref}" "${repository}" "${src_repo}"
else
  git clone --depth 1 "${repository}" "${src_repo}"
fi

if [[ ! -d "${src_theme}" ]]; then
  echo "grub-theme: theme directory '${theme_dir}' not found in repo '${repository}'" >&2
  exit 1
fi

install -d "${install_root}"
rm -rf "${dst_theme}"
cp -a "${src_theme}" "${dst_theme}"

if [[ ! -f "${theme_txt}" ]]; then
  echo "grub-theme: expected '${theme_txt}' not found after install" >&2
  exit 1
fi

if [[ "${set_grub_theme}" == "true" ]]; then
  if [[ -f "${grub_defaults_file}" ]]; then
    if grep -q '^GRUB_THEME=' "${grub_defaults_file}"; then
      sed -i "s|^GRUB_THEME=.*$|GRUB_THEME=\"${theme_txt}\"|" "${grub_defaults_file}"
    else
      printf '\nGRUB_THEME="%s"\n' "${theme_txt}" >> "${grub_defaults_file}"
    fi
  else
    echo "grub-theme: '${grub_defaults_file}' not found, skipping GRUB_THEME injection"
  fi
fi
