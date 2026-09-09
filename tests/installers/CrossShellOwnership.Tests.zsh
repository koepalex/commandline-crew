#!/usr/bin/env zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

repository_root=${0:A:h:h:h}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/crew-cross-shell.XXXXXX")
export HOME="$test_root/home"
export USERPROFILE="$HOME"
export XDG_CONFIG_HOME="$test_root/xdg"
target_repo="$test_root/target"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p -- "$HOME" "$XDG_CONFIG_HOME" "$target_repo"

pwsh -NoProfile -File "$repository_root/install.ps1" \
  -Runtime both -Force >/dev/null
pwsh -NoProfile -File "$repository_root/install-skills.ps1" \
  -Runtime both -Skill ask-folder -Force >/dev/null
pwsh -NoProfile -File "$repository_root/install-hooks.ps1" \
  -TargetRepo "$target_repo" -Runtime both -Force >/dev/null

python3 - "$target_repo/hooks/db.py" \
  "$target_repo/.commandline-crew/manifest.json" <<'PY'
import hashlib
import json
import pathlib
import sys

hook_path, manifest_path = map(pathlib.Path, sys.argv[1:])
old_content = b"# simulated older shared hook\n"
hook_path.write_bytes(old_content)
old_hash = hashlib.sha256(old_content).hexdigest()
manifest = json.loads(manifest_path.read_text())
manifest["copilotFiles"]["hooks/db.py"]["sha256"] = old_hash
manifest["opencodeFiles"]["hooks/db.py"]["sha256"] = old_hash
manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
PY
pwsh -NoProfile -File "$repository_root/install-hooks.ps1" \
  -TargetRepo "$target_repo" -Runtime copilot -Force >/dev/null

"$repository_root/uninstall-hooks.zsh" \
  --target-repo "$target_repo" --runtime copilot --force >/dev/null
[[ -f "$target_repo/hooks/db.py" ]]
"$repository_root/uninstall-hooks.zsh" \
  --target-repo "$target_repo" --runtime opencode --force >/dev/null
"$repository_root/uninstall-skills.zsh" --runtime both --force >/dev/null
"$repository_root/uninstall.zsh" --runtime both --force >/dev/null

[[ ! -f "$HOME/.copilot/agents/deep-thought.agent.md" ]]
[[ ! -f "$XDG_CONFIG_HOME/opencode/agents/deep-thought.md" ]]
[[ ! -d "$HOME/.copilot/skills/ask-folder" ]]
[[ ! -d "$XDG_CONFIG_HOME/opencode/skills/ask-folder" ]]
[[ ! -f "$target_repo/hooks.json" ]]
[[ ! -d "$target_repo/.opencode/plugins" ]]

"$repository_root/install.zsh" --runtime both --force >/dev/null
"$repository_root/install-skills.zsh" \
  --runtime both --skill ask-folder --force >/dev/null
"$repository_root/install-hooks.zsh" \
  --target-repo "$target_repo" --runtime both --force >/dev/null

python3 - "$target_repo/hooks/db.py" \
  "$target_repo/.commandline-crew/manifest.json" <<'PY'
import hashlib
import json
import pathlib
import sys

hook_path, manifest_path = map(pathlib.Path, sys.argv[1:])
old_content = b"# simulated older shared hook\n"
hook_path.write_bytes(old_content)
old_hash = hashlib.sha256(old_content).hexdigest()
manifest = json.loads(manifest_path.read_text())
manifest["copilotFiles"]["hooks/db.py"]["sha256"] = old_hash
manifest["opencodeFiles"]["hooks/db.py"]["sha256"] = old_hash
manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
PY
"$repository_root/install-hooks.zsh" \
  --target-repo "$target_repo" --runtime opencode --force >/dev/null

pwsh -NoProfile -File "$repository_root/uninstall-hooks.ps1" \
  -TargetRepo "$target_repo" -Runtime opencode -Force >/dev/null
[[ -f "$target_repo/hooks/db.py" ]]
pwsh -NoProfile -File "$repository_root/uninstall-hooks.ps1" \
  -TargetRepo "$target_repo" -Runtime copilot -Force >/dev/null
pwsh -NoProfile -File "$repository_root/uninstall-skills.ps1" \
  -Runtime both -Force >/dev/null
pwsh -NoProfile -File "$repository_root/uninstall.ps1" \
  -Runtime both -Force >/dev/null

[[ ! -f "$HOME/.copilot/agents/deep-thought.agent.md" ]]
[[ ! -f "$XDG_CONFIG_HOME/opencode/agents/deep-thought.md" ]]
[[ ! -d "$HOME/.copilot/skills/ask-folder" ]]
[[ ! -d "$XDG_CONFIG_HOME/opencode/skills/ask-folder" ]]
[[ ! -f "$target_repo/hooks.json" ]]
[[ ! -d "$target_repo/.opencode/plugins" ]]

print -- "All cross-shell ownership tests passed."
