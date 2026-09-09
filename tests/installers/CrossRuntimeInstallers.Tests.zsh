#!/usr/bin/env zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

repository_root=${0:A:h:h:h}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/crew-installers.XXXXXX")
export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/xdg"
target_repo="$test_root/target repo"

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p -- "$HOME" "$XDG_CONFIG_HOME/opencode" "$target_repo"

python3 - "$HOME/.copilot/mcp-config.json" \
  "$XDG_CONFIG_HOME/opencode/opencode.json" <<'PY'
import json
import pathlib
import sys

copilot, opencode = map(pathlib.Path, sys.argv[1:])
copilot.parent.mkdir(parents=True, exist_ok=True)
opencode.parent.mkdir(parents=True, exist_ok=True)
copilot.write_text(
    json.dumps({"mcpServers": {"userServer": {"type": "local"}}}),
    encoding="utf-8",
)
opencode.write_text(
    json.dumps({"theme": "user-theme", "mcp": {"userServer": {"type": "local"}}}),
    encoding="utf-8",
)
PY

"$repository_root/install-skills.zsh" \
  --runtime both --skill ask-folder --force >/dev/null
[[ -f "$HOME/.copilot/skills/ask-folder/references/tools-and-safety.md" ]]
[[ -f "$XDG_CONFIG_HOME/opencode/skills/ask-folder/references/tools-and-safety.md" ]]

"$repository_root/install.zsh" --runtime both --force >/dev/null
[[ -f "$HOME/.copilot/agents/deep-thought.agent.md" ]]
[[ -f "$XDG_CONFIG_HOME/opencode/agents/deep-thought.md" ]]

python3 - "$target_repo/hooks.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.write_text(
    json.dumps(
        {
            "version": 1,
            "hooks": {
                "sessionStart": [
                    {"type": "command", "bash": "python3 user-owned.py"}
                ],
                "userOwnedEvent": [
                    {"type": "command", "bash": "python3 user-owned-event.py"}
                ],
            },
        }
    ),
    encoding="utf-8",
)
PY

"$repository_root/install-hooks.zsh" \
  --target-repo "$target_repo" --runtime both --force >/dev/null
[[ -f "$target_repo/hooks.json" ]]
[[ -f "$target_repo/.github/hooks/hooks.json" ]]
[[ -f "$target_repo/hooks/opencode_bridge.py" ]]
(( ${#${(f)"$(find "$target_repo/.opencode/plugins" -type f -print)"}} > 0 ))

print -- "User customization" >> \
  "$XDG_CONFIG_HOME/opencode/agents/deep-thought.md"
print -- "User customization" >> \
  "$HOME/.copilot/skills/ask-folder/SKILL.md"
python3 - "$XDG_CONFIG_HOME/opencode/opencode.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
config = json.loads(path.read_text())
config["mcp"]["mslearn"] = {
    "type": "remote",
    "url": "https://user.example/mcp",
}
path.write_text(json.dumps(config), encoding="utf-8")
PY

"$repository_root/uninstall-hooks.zsh" \
  --target-repo "$target_repo" --runtime opencode --force >/dev/null
[[ -f "$target_repo/hooks.json" ]]
[[ ! -d "$target_repo/.opencode/plugins" ]]

"$repository_root/uninstall-hooks.zsh" \
  --target-repo "$target_repo" --runtime copilot --force --purge-data >/dev/null
python3 - "$target_repo/hooks.json" <<'PY'
import json
import pathlib
import sys

hooks = json.loads(pathlib.Path(sys.argv[1]).read_text())["hooks"]
assert any(
    entry.get("bash") == "python3 user-owned.py"
    for entry in hooks["sessionStart"]
)
assert "userOwnedEvent" in hooks
PY

"$repository_root/uninstall-skills.zsh" --runtime both --force >/dev/null
"$repository_root/uninstall.zsh" --runtime both --force >/dev/null

[[ -f "$HOME/.copilot/skills/ask-folder/SKILL.md" ]]
[[ -f "$XDG_CONFIG_HOME/opencode/agents/deep-thought.md" ]]
[[ ! -f "$XDG_CONFIG_HOME/opencode/agents/dotnet-bot.md" ]]

python3 - "$HOME/.copilot/mcp-config.json" \
  "$XDG_CONFIG_HOME/opencode/opencode.json" <<'PY'
import json
import pathlib
import sys

copilot, opencode = map(pathlib.Path, sys.argv[1:])
assert "userServer" in json.loads(copilot.read_text())["mcpServers"]
opencode_config = json.loads(opencode.read_text())
assert opencode_config["theme"] == "user-theme"
assert "userServer" in opencode_config["mcp"]
assert opencode_config["mcp"]["mslearn"]["url"] == "https://user.example/mcp"
PY

print -- "All cross-runtime zsh installer tests passed."
