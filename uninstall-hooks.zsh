#!/usr/bin/env zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/scripts/install-common.zsh"

runtime=""
force=false
purge_data=false
target_repo=""
while (( $# )); do
  case "$1" in
    --runtime)
      (( $# >= 2 )) || crew_die "--runtime requires a value."
      runtime="$2"; shift 2 ;;
    --runtime=*) runtime="${1#*=}"; shift ;;
    --target-repo)
      (( $# >= 2 )) || crew_die "--target-repo requires a path."
      target_repo="$2"; shift 2 ;;
    --target-repo=*) target_repo="${1#*=}"; shift ;;
    --force) force=true; shift ;;
    --purge-data) purge_data=true; shift ;;
    -h|--help)
      print -- "Usage: $0 --target-repo PATH [--runtime copilot|opencode|both] [--force] [--purge-data]"
      exit 0 ;;
    *) crew_die "Unknown option: $1" ;;
  esac
done

[[ -n "$target_repo" ]] || crew_die "--target-repo is required."
[[ -d "$target_repo" ]] || crew_die "Target repository not found: $target_repo"
target_repo="${target_repo:A}"
runtime="$(crew_choose_runtime "$runtime")"

print -- "Commandline Crew - Hooks Uninstaller ($runtime)"
print -- "Target repository: $target_repo"
manifest="$target_repo/.commandline-crew/manifest.json"

remove_recorded_files() {
  local category="$1" other_category="$2" relative target_file
  for relative in "${(@f)$(crew_manifest_list "$manifest" "$category")}"; do
    if crew_manifest_has "$manifest" "$other_category" "$relative"; then
      print -- "  Preserved shared file: $relative"
      crew_manifest_drop "$manifest" "$category" "$relative"
      continue
    fi
    target_file="$target_repo/$relative"
    if crew_manifest_resource_equals "$manifest" "$category" "$relative" "$target_file" file; then
      if [[ "$force" != true ]] && ! crew_confirm "Remove unchanged owned file '$relative'?"; then
        print -- "  Skipped: $relative"
        continue
      fi
      rm -f -- "$target_file"
      print -- "  Removed: $relative"
    else
      print -- "  Preserved modified or missing file: $relative"
    fi
    crew_manifest_drop "$manifest" "$category" "$relative"
  done
}

if crew_has_runtime "$runtime" copilot; then
  print -- "Copilot hooks"
  if [[ -n "$(crew_manifest_list "$manifest" copilotHooksRoot)" ]]; then
    if [[ "$force" == true ]] || crew_confirm "Remove unchanged owned commands from hooks.json?"; then
      crew_hook_unmerge "$target_repo/hooks.json" "$manifest" copilotHooksRoot hooks.json
    fi
  fi
  if [[ -n "$(crew_manifest_list "$manifest" copilotHooksAgent)" ]]; then
    if [[ "$force" == true ]] || crew_confirm "Remove unchanged owned commands from .github/hooks/hooks.json?"; then
      crew_hook_unmerge "$target_repo/.github/hooks/hooks.json" "$manifest" copilotHooksAgent .github/hooks/hooks.json
    fi
  fi
  remove_recorded_files copilotFiles opencodeFiles
  crew_remove_empty_dir "$target_repo/hooks"
  crew_remove_empty_dir "$target_repo/.github/hooks"
fi

if crew_has_runtime "$runtime" opencode; then
  print -- "OpenCode plugin and bridge"
  remove_recorded_files opencodeFiles copilotFiles
  crew_remove_empty_dir "$target_repo/hooks"
  crew_remove_empty_dir "$target_repo/.opencode/plugins"
  crew_remove_empty_dir "$target_repo/.opencode"
fi

crew_remove_empty_dir "$target_repo/.commandline-crew"

if [[ "$purge_data" == true ]]; then
  crew_remove_path "$target_repo/observability" "$force" "observability/"
elif [[ -d "$target_repo/observability" ]]; then
  print -- "Observability data preserved at $target_repo/observability (use --purge-data to remove it)."
fi
print -- "Hooks uninstall complete."
