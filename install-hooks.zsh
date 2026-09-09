#!/usr/bin/env zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/scripts/install-common.zsh"

runtime=""
force=false
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
    -h|--help)
      print -- "Usage: $0 --target-repo PATH [--runtime copilot|opencode|both] [--force]"
      exit 0 ;;
    *) crew_die "Unknown option: $1" ;;
  esac
done

[[ -n "$target_repo" ]] || crew_die "--target-repo is required."
[[ -d "$target_repo" ]] || crew_die "Target repository not found: $target_repo"
target_repo="${target_repo:A}"
runtime="$(crew_choose_runtime "$runtime")"

copy_tree_files() {
  local source_root="$1" target_root="$2" label="$3" category="$4"
  [[ -d "$source_root" ]] || crew_die "$label source directory not found: $source_root"
  local source_file relative
  typeset -a files
  files=("$source_root"/**/*(.N))
  (( ${#files} )) || crew_die "No files found in $label source directory: $source_root"
  for source_file in "${files[@]}"; do
    relative="${source_file#$source_root/}"
    crew_copy_file "$source_file" "$target_root/$relative" "$force" "$label/$relative"
    if [[ "$CREW_LAST_ACTION" == installed ]]; then
      crew_manifest_record "$manifest" "$category" "$label/$relative" file "$source_file"
    fi
  done
}

copilot_python_names=(
  db.py session_start.py session_end.py user_prompt.py pre_tool_use.py
  post_tool_use.py error_occurred.py report.py
)

typeset -a plugin_files opencode_python_names
plugin_files=()
opencode_python_names=()
if crew_has_runtime "$runtime" opencode; then
  source_plugins="$SCRIPT_DIR/.opencode/plugins"
  [[ -d "$source_plugins" ]] || crew_die "OpenCode plugin source directory not found: $source_plugins"
  plugin_files=("$source_plugins"/**/*(.N))
  (( ${#plugin_files} )) || crew_die "No OpenCode plugin files found in $source_plugins."
  opencode_python_names=(db.py)
  referenced="$(grep -Eho '[A-Za-z0-9_.-]+\.py' "${plugin_files[@]}" 2>/dev/null || true)"
  if [[ -n "$referenced" ]]; then
    opencode_python_names+=("${(@f)referenced}")
  fi
  [[ -f "$SCRIPT_DIR/hooks/opencode_bridge.py" ]] && opencode_python_names+=(opencode_bridge.py)
  opencode_python_names=(${(u)opencode_python_names})
  for name in "${opencode_python_names[@]}"; do
    [[ -f "$SCRIPT_DIR/hooks/$name" ]] ||
      crew_die "OpenCode plugin requires missing Python file: hooks/$name"
  done
fi

print -- "Commandline Crew - Hooks Installer ($runtime)"
print -- "Target repository: $target_repo"
manifest="$target_repo/.commandline-crew/manifest.json"

install_owned_hook_file() {
  local source_file="$1" relative="$2" category="$3" other_category="$4"
  local other_owned=false
  if crew_manifest_has "$manifest" "$other_category" "$relative"; then
    other_owned=true
  fi
  if crew_manifest_has "$manifest" "$other_category" "$relative" &&
     crew_file_equals "$source_file" "$target_repo/$relative"; then
    crew_manifest_record "$manifest" "$category" "$relative" file "$source_file"
    crew_manifest_record "$manifest" "$other_category" "$relative" file "$source_file"
    print -- "  Shared existing owned file: $relative"
    return 0
  fi
  crew_copy_file "$source_file" "$target_repo/$relative" "$force" "$relative"
  if [[ "$CREW_LAST_ACTION" == installed ]]; then
    crew_manifest_record "$manifest" "$category" "$relative" file "$source_file"
    if [[ "$other_owned" == true ]]; then
      crew_manifest_record "$manifest" "$other_category" "$relative" file "$source_file"
    fi
  fi
}

if crew_has_runtime "$runtime" copilot; then
  source_hooks="$SCRIPT_DIR/hooks"
  source_json="$SCRIPT_DIR/hooks.json"
  [[ -d "$source_hooks" ]] || crew_die "Copilot hook scripts not found: $source_hooks"

  print -- "Copilot hook scripts"
  for name in "${copilot_python_names[@]}"; do
    install_owned_hook_file "$source_hooks/$name" "hooks/$name" copilotFiles opencodeFiles
  done
  added="$(crew_hook_merge "$source_json" "$target_repo/hooks.json" "$manifest" copilotHooksRoot hooks.json)"
  print -- "  Added $added hook command(s): hooks.json"
  added="$(crew_hook_merge "$source_json" "$target_repo/.github/hooks/hooks.json" "$manifest" copilotHooksAgent .github/hooks/hooks.json)"
  print -- "  Added $added hook command(s): .github/hooks/hooks.json"
fi

if crew_has_runtime "$runtime" opencode; then
  print -- "OpenCode plugin and bridge"
  copy_tree_files "$source_plugins" "$target_repo/.opencode/plugins" ".opencode/plugins" opencodeFiles
  for name in "${opencode_python_names[@]}"; do
    install_owned_hook_file "$SCRIPT_DIR/hooks/$name" "hooks/$name" opencodeFiles copilotFiles
  done
fi

if [[ -f "$target_repo/.gitignore" ]] && ! grep -Eq '(^|/)observability/?$' "$target_repo/.gitignore"; then
  print -- "TIP: Add 'observability/' to $target_repo/.gitignore."
fi
print -- "Hooks installation complete."
