#!/usr/bin/env zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/scripts/install-common.zsh"

runtime=""
force=false
typeset -a requested
requested=()

while (( $# )); do
  case "$1" in
    --runtime)
      (( $# >= 2 )) || crew_die "--runtime requires a value."
      runtime="$2"; shift 2 ;;
    --runtime=*) runtime="${1#*=}"; shift ;;
    --skill)
      (( $# >= 2 )) || crew_die "--skill requires a value."
      requested+=("$2"); shift 2 ;;
    --skill=*) requested+=("${1#*=}"); shift ;;
    --force) force=true; shift ;;
    -h|--help)
      print -- "Usage: $0 [--runtime copilot|opencode|both] [--skill NAME[,NAME] ...] [--force]"
      exit 0 ;;
    *) crew_die "Unknown option: $1" ;;
  esac
done

runtime="$(crew_choose_runtime "$runtime")"
typeset -a selected parsed targets
if (( ${#requested} )); then
  parsed=("${(@f)$(crew_parse_skills "${requested[@]}")}")
  for name in "${parsed[@]}"; do
    (( ${selected[(Ie)$name]} )) || selected+=("$name")
  done
fi

targets=()
crew_has_runtime "$runtime" copilot && targets+=("$HOME/.copilot")
crew_has_runtime "$runtime" opencode && targets+=("${XDG_CONFIG_HOME:-$HOME/.config}/opencode")

for config_root in "${targets[@]}"; do
  target_root="$config_root/skills"
  manifest="$config_root/commandline-crew-manifest.json"
  print -- "Removing commandline-crew skills from $target_root"
  typeset -a runtime_selected
  if (( ${#selected} )); then
    runtime_selected=("${selected[@]}")
  else
    runtime_selected=("${(@f)$(crew_manifest_list "$manifest" skills)}")
  fi
  for name in "${runtime_selected[@]}"; do
    crew_manifest_has "$manifest" skills "$name" || continue
    target_path="$target_root/$name"
    if crew_manifest_resource_equals "$manifest" skills "$name" "$target_path" tree; then
      if [[ "$force" != true ]] && ! crew_confirm "Remove unchanged owned skill '$name'?"; then
        print -- "  Skipped: $name"
        continue
      fi
      rm -rf -- "$target_path"
      print -- "  Removed: $name"
    else
      print -- "  Preserved modified or missing skill: $name"
    fi
    crew_manifest_drop "$manifest" skills "$name"
  done
  crew_remove_empty_dir "$target_root"
done
