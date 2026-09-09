#!/usr/bin/env zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/scripts/install-common.zsh"

runtime=""
force=false
while (( $# )); do
  case "$1" in
    --runtime)
      (( $# >= 2 )) || crew_die "--runtime requires a value."
      runtime="$2"; shift 2 ;;
    --runtime=*) runtime="${1#*=}"; shift ;;
    --force) force=true; shift ;;
    -h|--help)
      print -- "Usage: $0 [--runtime copilot|opencode|both] [--force]"
      exit 0 ;;
    *) crew_die "Unknown option: $1" ;;
  esac
done

runtime="$(crew_choose_runtime "$runtime")"
print -- "Commandline Crew - Uninstaller ($runtime)"

if crew_has_runtime "$runtime" copilot; then
  source_agents="$SCRIPT_DIR/.github/agents"
  source_mcp="$SCRIPT_DIR/.copilot/mcp-config.json"
  target_agents="$HOME/.copilot/agents"
  target_mcp="$HOME/.copilot/mcp-config.json"
  manifest="$HOME/.copilot/commandline-crew-manifest.json"
  print -- "Copilot agents"
  for name in "${(@f)$(crew_manifest_list "$manifest" agents)}"; do
    target_file="$target_agents/$name"
    if crew_manifest_resource_equals "$manifest" agents "$name" "$target_file" file; then
      if [[ "$force" == true ]] || crew_confirm "Remove unchanged owned agent '$name'?"; then
        rm -f -- "$target_file"
        print -- "  Removed: $name"
      else
        print -- "  Skipped: $name"
        continue
      fi
    else
      print -- "  Preserved modified or missing agent: $name"
    fi
    crew_manifest_drop "$manifest" agents "$name"
  done
  crew_remove_empty_dir "$target_agents"
  for name in "${(@f)$(crew_manifest_list "$manifest" mcp)}"; do
    state="$(crew_manifest_json_entry_state "$manifest" mcp "$name" "$target_mcp" mcpServers)"
    if [[ "$state" == equal ]]; then
      if [[ "$force" != true ]] && ! crew_confirm "Remove unchanged owned MCP entry '$name'?"; then
        print -- "  Skipped MCP entry: $name"
        continue
      fi
      crew_manifest_json_entry_remove "$manifest" mcp "$name" "$target_mcp" mcpServers
      print -- "  Removed MCP entry: $name"
    else
      print -- "  Preserved modified MCP entry: $name"
    fi
    crew_manifest_drop "$manifest" mcp "$name"
  done
fi

if crew_has_runtime "$runtime" opencode; then
  source_agents="$SCRIPT_DIR/.opencode/agents"
  source_mcp="$SCRIPT_DIR/.opencode/opencode.json"
  config_root="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  target_agents="$config_root/agents"
  target_mcp="$config_root/opencode.json"
  manifest="$config_root/commandline-crew-manifest.json"
  print -- "OpenCode agents"
  for name in "${(@f)$(crew_manifest_list "$manifest" agents)}"; do
    target_file="$target_agents/$name"
    if crew_manifest_resource_equals "$manifest" agents "$name" "$target_file" file; then
      if [[ "$force" == true ]] || crew_confirm "Remove unchanged owned agent '$name'?"; then
        rm -f -- "$target_file"
        print -- "  Removed: $name"
      else
        print -- "  Skipped: $name"
        continue
      fi
    else
      print -- "  Preserved modified or missing agent: $name"
    fi
    crew_manifest_drop "$manifest" agents "$name"
  done
  crew_remove_empty_dir "$target_agents"
  for name in "${(@f)$(crew_manifest_list "$manifest" mcp)}"; do
    state="$(crew_manifest_json_entry_state "$manifest" mcp "$name" "$target_mcp" mcp)"
    if [[ "$state" == equal ]]; then
      if [[ "$force" != true ]] && ! crew_confirm "Remove unchanged owned MCP entry '$name'?"; then
        print -- "  Skipped MCP entry: $name"
        continue
      fi
      crew_manifest_json_entry_remove "$manifest" mcp "$name" "$target_mcp" mcp
      print -- "  Removed MCP entry: $name"
    else
      print -- "  Preserved modified MCP entry: $name"
    fi
    crew_manifest_drop "$manifest" mcp "$name"
  done
fi

print -- "Uninstall complete."
