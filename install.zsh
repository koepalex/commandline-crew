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
print -- "Commandline Crew - Installer ($runtime)"

if crew_has_runtime "$runtime" copilot; then
  source_agents="$SCRIPT_DIR/.github/agents"
  source_mcp="$SCRIPT_DIR/.copilot/mcp-config.json"
  target_agents="$HOME/.copilot/agents"
  target_mcp="$HOME/.copilot/mcp-config.json"
  manifest="$HOME/.copilot/commandline-crew-manifest.json"
  [[ -d "$source_agents" ]] || crew_die "Copilot agent sources not found: $source_agents"

  print -- "Copilot agents"
  mkdir -p -- "$target_agents"
  typeset -a copilot_agents
  copilot_agents=("$source_agents"/*.agent.md(N))
  (( ${#copilot_agents} )) || crew_die "No Copilot agents (*.agent.md) found in $source_agents."
  for source_file in "${copilot_agents[@]}"; do
    crew_copy_file "$source_file" "$target_agents/${source_file:t}" "$force" "${source_file:t}"
    if [[ "$CREW_LAST_ACTION" == installed ]]; then
      crew_manifest_record "$manifest" agents "${source_file:t}" file "$source_file"
    fi
  done
  for name in "${(@f)$(crew_json_entry_names "$source_mcp" mcpServers)}"; do
    state="$(crew_json_entry_state "$source_mcp" "$target_mcp" mcpServers mcpServers "$name")"
    if [[ "$state" != missing && "$force" != true ]] &&
       ! crew_confirm "Overwrite MCP entry '$name' in Copilot MCP config?"; then
      print -- "  Skipped MCP entry: $name"
      continue
    fi
    crew_json_entry_update set "$source_mcp" "$target_mcp" mcpServers mcpServers "$name"
    crew_manifest_record "$manifest" mcp "$name" json "$source_mcp" mcpServers "$name"
    print -- "  Installed MCP entry: $name"
  done
fi

if crew_has_runtime "$runtime" opencode; then
  source_agents="$SCRIPT_DIR/.opencode/agents"
  source_mcp="$SCRIPT_DIR/.opencode/opencode.json"
  config_root="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  target_agents="$config_root/agents"
  target_mcp="$config_root/opencode.json"
  manifest="$config_root/commandline-crew-manifest.json"
  [[ -d "$source_agents" ]] || crew_die "OpenCode adapter sources not found: $source_agents"

  print -- "OpenCode agents"
  mkdir -p -- "$target_agents"
  typeset -a opencode_agents
  opencode_agents=("$source_agents"/*(.N))
  (( ${#opencode_agents} )) || crew_die "No OpenCode agent adapters found in $source_agents."
  for source_file in "${opencode_agents[@]}"; do
    crew_copy_file "$source_file" "$target_agents/${source_file:t}" "$force" "${source_file:t}"
    if [[ "$CREW_LAST_ACTION" == installed ]]; then
      crew_manifest_record "$manifest" agents "${source_file:t}" file "$source_file"
    fi
  done
  for name in "${(@f)$(crew_json_entry_names "$source_mcp" mcp)}"; do
    state="$(crew_json_entry_state "$source_mcp" "$target_mcp" mcp mcp "$name")"
    if [[ "$state" != missing && "$force" != true ]] &&
       ! crew_confirm "Overwrite MCP entry '$name' in OpenCode MCP config?"; then
      print -- "  Skipped MCP entry: $name"
      continue
    fi
    crew_json_entry_update set "$source_mcp" "$target_mcp" mcp mcp "$name"
    crew_manifest_record "$manifest" mcp "$name" json "$source_mcp" mcp "$name"
    print -- "  Installed MCP entry: $name"
  done
fi

print -- "Installation complete."
