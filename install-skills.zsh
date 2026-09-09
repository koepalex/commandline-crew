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
source_root="$SCRIPT_DIR/skills"
[[ -d "$source_root" ]] || crew_die "Source skills directory not found: $source_root"

typeset -a available selected parsed
available=()
for directory in "$source_root"/*(/N); do
  if [[ -f "$directory/SKILL.md" ]]; then
    available+=("${directory:t}")
  else
    print -- "Skipped ${directory:t}: missing SKILL.md"
  fi
done
available=(${(on)available})
(( ${#available} )) || crew_die "No valid skills found in $source_root."

if (( ${#requested} )); then
  parsed=("${(@f)$(crew_parse_skills "${requested[@]}")}")
  for name in "${parsed[@]}"; do
    (( ${available[(Ie)$name]} )) || crew_die "Unknown skill '$name'. Available: ${(j:, :)available}"
    (( ${selected[(Ie)$name]} )) || selected+=("$name")
  done
elif [[ "$force" == true ]]; then
  selected=("${available[@]}")
else
  print -- "Available skills:"
  integer index=1
  for name in "${available[@]}"; do
    print -- "  [$index] $name"
    (( index++ ))
  done
  local_reply=""
  read "local_reply?Select by number or name (comma-separated), or 'all': "
  [[ -n "$local_reply" ]] || {
    print -- "Installation cancelled."
    exit 0
  }
  if [[ "$local_reply" == all ]]; then
    selected=("${available[@]}")
  else
    parsed=("${(@f)$(crew_parse_skills "$local_reply")}")
    for choice in "${parsed[@]}"; do
      if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#available} )); then
        name="${available[$choice]}"
      elif (( ${available[(Ie)$choice]} )); then
        name="$choice"
      else
        crew_die "Invalid skill selection: $choice"
      fi
      (( ${selected[(Ie)$name]} )) || selected+=("$name")
    done
  fi
fi

typeset -a targets
targets=()
crew_has_runtime "$runtime" copilot && targets+=("$HOME/.copilot")
crew_has_runtime "$runtime" opencode && targets+=("${XDG_CONFIG_HOME:-$HOME/.config}/opencode")

for config_root in "${targets[@]}"; do
  target_root="$config_root/skills"
  manifest="$config_root/commandline-crew-manifest.json"
  mkdir -p -- "$target_root"
  print -- "Installing skills to $target_root"
  for name in "${selected[@]}"; do
    source_path="$source_root/$name"
    target_path="$target_root/$name"
    if [[ -e "$target_path" ]]; then
      if [[ "$force" != true ]] && ! crew_confirm "Replace stale skill '$target_path'?"; then
        print -- "  Skipped: $name"
        continue
      fi
      rm -rf -- "$target_path"
    fi
    mkdir -p -- "$target_path"
    cp -R -- "$source_path/." "$target_path/"
    find "$target_path" -type d \( -name bin -o -name obj \) -prune -exec rm -rf -- {} +
    crew_manifest_record "$manifest" skills "$name" tree "$source_path"
    print -- "  Installed: $name"
  done
done
