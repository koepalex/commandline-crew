#!/usr/bin/env zsh

crew_die() {
  print -u2 -- "ERROR: $*"
  return 1
}

crew_require_python() {
  (( $+commands[python3] )) || crew_die "python3 is required for safe JSON configuration updates."
}

crew_confirm() {
  local prompt="$1" reply
  read "reply?$prompt [y/N] "
  [[ "$reply" == [Yy] ]]
}

crew_choose_runtime() {
  local runtime="${1:-}" reply
  if [[ -z "$runtime" ]]; then
    print -u2 -- "Select runtime:"
    print -u2 -- "  [1] copilot"
    print -u2 -- "  [2] opencode"
    print -u2 -- "  [3] both"
    read "reply?Runtime [1-3]: "
    case "$reply" in
      1|copilot) runtime=copilot ;;
      2|opencode) runtime=opencode ;;
      3|both) runtime=both ;;
      *) crew_die "Invalid runtime selection: ${reply:-<empty>}" ;;
    esac
  fi
  case "$runtime" in
    copilot|opencode|both) print -r -- "$runtime" ;;
    *) crew_die "--runtime must be copilot, opencode, or both (got '$runtime')." ;;
  esac
}

crew_has_runtime() {
  [[ "$1" == "$2" || "$1" == both ]]
}

crew_copy_file() {
  local source="$1" target="$2" force="$3" label="${4:-$2}"
  [[ -f "$source" ]] || crew_die "Required source file not found: $source"
  if [[ -e "$target" && "$force" != true ]] && ! crew_confirm "Overwrite '$label'?"; then
    print -- "  Skipped: $label"
    CREW_LAST_ACTION=skipped
    return 0
  fi
  mkdir -p -- "${target:h}"
  cp -f -- "$source" "$target"
  print -- "  Installed: $label"
  CREW_LAST_ACTION=installed
}

crew_remove_path() {
  local target="$1" force="$2" label="${3:-$1}"
  if [[ ! -e "$target" ]]; then
    print -- "  Not found: $label"
    return 0
  fi
  if [[ "$force" != true ]] && ! crew_confirm "Remove '$label'?"; then
    print -- "  Skipped: $label"
    return 0
  fi
  rm -rf -- "$target"
  print -- "  Removed: $label"
}

crew_remove_empty_dir() {
  local directory="$1"
  [[ -d "$directory" ]] || return 0
  if [[ -z "$(find "$directory" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    rmdir -- "$directory"
  fi
  return 0
}

crew_json_conflicts() {
  local source="$1" target="$2" source_key="$3" target_key="$4"
  crew_require_python
  python3 - "$source" "$target" "$source_key" "$target_key" <<'PY'
import json
import pathlib
import sys

source_path, target_path = map(pathlib.Path, sys.argv[1:3])
source_key, target_key = sys.argv[3:5]
try:
    source = json.loads(source_path.read_text(encoding="utf-8"))
except FileNotFoundError:
    raise SystemExit(f"ERROR: Required source JSON not found: {source_path}")
except json.JSONDecodeError as exc:
    raise SystemExit(f"ERROR: Malformed source JSON {source_path}: {exc}")
owned = source.get(source_key)
if not isinstance(owned, dict):
    raise SystemExit(f"ERROR: {source_path} must contain an object named '{source_key}'.")
if not target_path.exists():
    raise SystemExit(0)
try:
    target = json.loads(target_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    raise SystemExit(f"ERROR: Malformed target JSON {target_path}: {exc}")
existing = target.get(target_key, {})
if existing is not None and not isinstance(existing, dict):
    raise SystemExit(f"ERROR: {target_path} property '{target_key}' must be an object.")
for name in owned.keys() & (existing or {}).keys():
    print(name)
PY
}

crew_json_update() {
  local action="$1" source="$2" target="$3" source_key="$4" target_key="$5"
  crew_require_python
  python3 - "$action" "$source" "$target" "$source_key" "$target_key" <<'PY'
import json
import os
import pathlib
import tempfile
import sys

action, source_arg, target_arg, source_key, target_key = sys.argv[1:6]
source_path = pathlib.Path(source_arg)
target_path = pathlib.Path(target_arg)
try:
    source = json.loads(source_path.read_text(encoding="utf-8"))
except FileNotFoundError:
    raise SystemExit(f"ERROR: Required source JSON not found: {source_path}")
except json.JSONDecodeError as exc:
    raise SystemExit(f"ERROR: Malformed source JSON {source_path}: {exc}")
owned = source.get(source_key)
if not isinstance(owned, dict):
    raise SystemExit(f"ERROR: {source_path} must contain an object named '{source_key}'.")

target_exists = target_path.exists()
if target_exists:
    try:
        target = json.loads(target_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"ERROR: Malformed target JSON {target_path}: {exc}")
    if not isinstance(target, dict):
        raise SystemExit(f"ERROR: Target JSON root must be an object: {target_path}")
else:
    target = dict(source)

entries = target.get(target_key)
if entries is None:
    entries = {}
elif not isinstance(entries, dict):
    raise SystemExit(f"ERROR: {target_path} property '{target_key}' must be an object.")

if action == "merge":
    entries.update(owned)
    target[target_key] = entries
elif action == "merge-missing":
    for name, value in owned.items():
        entries.setdefault(name, value)
    target[target_key] = entries
elif action == "remove":
    for name in owned:
        entries.pop(name, None)
    if entries:
        target[target_key] = entries
    else:
        target.pop(target_key, None)
else:
    raise SystemExit(f"ERROR: Unknown JSON action: {action}")

target_path.parent.mkdir(parents=True, exist_ok=True)
fd, temporary_name = tempfile.mkstemp(
    prefix=f".{target_path.name}.", suffix=".tmp", dir=target_path.parent
)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(target, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    if target_path.exists():
        os.chmod(temporary_name, target_path.stat().st_mode)
    os.replace(temporary_name, target_path)
except BaseException:
    try:
        os.unlink(temporary_name)
    except FileNotFoundError:
        pass
    raise
PY
}

crew_merge_json() {
  local source="$1" target="$2" source_key="$3" target_key="$4" force="$5" label="$6"
  local conflicts
  conflicts="$(crew_json_conflicts "$source" "$target" "$source_key" "$target_key")"
  if [[ -n "$conflicts" && "$force" != true ]]; then
    print -- "  Existing repo-owned entries in $label:"
    print -r -- "$conflicts" | sed 's/^/    - /'
    if ! crew_confirm "Overwrite these entries?"; then
      crew_json_update merge-missing "$source" "$target" "$source_key" "$target_key"
      print -- "  Preserved existing entries and merged new entries: $label"
      return 0
    fi
  fi
  crew_json_update merge "$source" "$target" "$source_key" "$target_key"
  print -- "  Updated: $label"
}

crew_remove_json() {
  local source="$1" target="$2" source_key="$3" target_key="$4" force="$5" label="$6"
  [[ -e "$target" ]] || {
    print -- "  Not found: $label"
    return 0
  }
  if [[ "$force" != true ]] && ! crew_confirm "Remove commandline-crew entries from '$label'?"; then
    print -- "  Skipped: $label"
    return 0
  fi
  crew_json_update remove "$source" "$target" "$source_key" "$target_key"
  print -- "  Updated: $label"
}

crew_parse_skills() {
  local value item
  for value in "$@"; do
    for item in ${(s:,:)value}; do
      item="${item#"${item%%[![:space:]]*}"}"
      item="${item%"${item##*[![:space:]]}"}"
      [[ -n "$item" ]] && print -r -- "$item"
    done
  done
}

crew_file_hash() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  python3 - "$file" <<'PY'
import hashlib, pathlib, sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

crew_file_equals() {
  [[ "$(crew_file_hash "$1")" == "$(crew_file_hash "$2")" ]]
}

crew_tree_hash() {
  local directory="$1"
  python3 - "$directory" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
if not root.is_dir():
    raise SystemExit(1)
h = hashlib.sha256()
for path in sorted(p for p in root.rglob("*") if p.is_file()):
    rel = path.relative_to(root).as_posix()
    if any(part in {"bin", "obj"} for part in path.relative_to(root).parts):
        continue
    h.update(rel.encode()); h.update(b"\0"); h.update(path.read_bytes()); h.update(b"\0")
print(h.hexdigest())
PY
}

crew_tree_equals() {
  [[ "$(crew_tree_hash "$1")" == "$(crew_tree_hash "$2")" ]]
}

crew_manifest_record() {
  local manifest="$1" category="$2" name="$3" kind="$4" source="$5" source_key="${6:-}" entry="${7:-}"
  crew_require_python
  python3 - "$manifest" "$category" "$name" "$kind" "$source" "$source_key" "$entry" <<'PY'
import hashlib, json, os, pathlib, tempfile, sys
manifest, category, name, kind, source, source_key, entry = sys.argv[1:8]
p = pathlib.Path(manifest)
try:
    data = json.loads(p.read_text()) if p.exists() else {"version": 1}
except json.JSONDecodeError as exc:
    raise SystemExit(f"ERROR: Malformed ownership manifest {p}: {exc}")
if kind == "file":
    value = {"sha256": hashlib.sha256(pathlib.Path(source).read_bytes()).hexdigest()}
elif kind == "tree":
    root = pathlib.Path(source); h = hashlib.sha256()
    for path in sorted(x for x in root.rglob("*") if x.is_file()):
        rel = path.relative_to(root)
        if any(part in {"bin", "obj"} for part in rel.parts): continue
        h.update(rel.as_posix().encode()); h.update(b"\0"); h.update(path.read_bytes()); h.update(b"\0")
    value = {"treeSha256": h.hexdigest()}
elif kind == "json":
    obj = json.loads(pathlib.Path(source).read_text())
    value = obj[source_key][entry]
else:
    raise SystemExit(f"ERROR: Unknown manifest record kind: {kind}")
data.setdefault(category, {})[name] = value
p.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=f".{p.name}.", suffix=".tmp", dir=p.parent)
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, p)
except BaseException:
    try: os.unlink(tmp)
    except FileNotFoundError: pass
    raise
PY
}

crew_manifest_list() {
  local manifest="$1" category="$2"
  [[ -f "$manifest" ]] || return 0
  python3 - "$manifest" "$category" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
try: data = json.loads(p.read_text())
except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed ownership manifest {p}: {exc}")
for name in data.get(sys.argv[2], {}): print(name)
PY
}

crew_manifest_has() {
  local manifest="$1" category="$2" name="$3"
  [[ -f "$manifest" ]] || return 1
  python3 - "$manifest" "$category" "$name" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1])
try: data=json.loads(p.read_text())
except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed ownership manifest {p}: {exc}")
raise SystemExit(0 if sys.argv[3] in data.get(sys.argv[2], {}) else 1)
PY
}

crew_manifest_drop() {
  local manifest="$1" category="$2" name="$3"
  [[ -f "$manifest" ]] || return 0
  python3 - "$manifest" "$category" "$name" <<'PY'
import json, os, pathlib, tempfile, sys
p=pathlib.Path(sys.argv[1]); data=json.loads(p.read_text()); category=sys.argv[2]
data.get(category, {}).pop(sys.argv[3], None)
if not data.get(category): data.pop(category, None)
if set(data) <= {"version"}:
    p.unlink(missing_ok=True); raise SystemExit(0)
fd,tmp=tempfile.mkstemp(prefix=f".{p.name}.",suffix=".tmp",dir=p.parent)
with os.fdopen(fd,"w") as f:
    json.dump(data,f,indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
os.replace(tmp,p)
PY
}

crew_manifest_resource_equals() {
  local manifest="$1" category="$2" name="$3" target="$4" kind="$5"
  python3 - "$manifest" "$category" "$name" "$target" "$kind" <<'PY'
import hashlib, json, pathlib, sys
mp=pathlib.Path(sys.argv[1]); category,name,target,kind=sys.argv[2:6]
try: data=json.loads(mp.read_text())
except (FileNotFoundError, json.JSONDecodeError): raise SystemExit(1)
record=data.get(category,{}).get(name)
p=pathlib.Path(target)
if record is None or not p.exists(): raise SystemExit(1)
if kind=="file":
    actual=hashlib.sha256(p.read_bytes()).hexdigest()
    expected=record.get("sha256") if isinstance(record,dict) else None
elif kind=="tree":
    if not p.is_dir(): raise SystemExit(1)
    h=hashlib.sha256()
    for child in sorted(x for x in p.rglob("*") if x.is_file()):
        rel=child.relative_to(p)
        if any(part in {"bin","obj"} for part in rel.parts): continue
        h.update(rel.as_posix().encode()); h.update(b"\0"); h.update(child.read_bytes()); h.update(b"\0")
    actual=h.hexdigest()
    expected=record.get("treeSha256") if isinstance(record,dict) else None
else: raise SystemExit(1)
raise SystemExit(0 if actual==expected else 1)
PY
}

crew_manifest_json_entry_state() {
  local manifest="$1" category="$2" name="$3" target="$4" target_key="$5"
  python3 - "$manifest" "$category" "$name" "$target" "$target_key" <<'PY'
import json, pathlib, sys
mp=pathlib.Path(sys.argv[1]); category,name=sys.argv[2:4]; tp=pathlib.Path(sys.argv[4]); key=sys.argv[5]
try: manifest=json.loads(mp.read_text())
except (FileNotFoundError,json.JSONDecodeError): print("missing"); raise SystemExit
record=manifest.get(category,{}).get(name)
if record is None or not tp.exists(): print("missing"); raise SystemExit
try: target=json.loads(tp.read_text())
except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed target JSON {tp}: {exc}")
entries=target.get(key,{})
if not isinstance(entries,dict): raise SystemExit(f"ERROR: {tp} property '{key}' must be an object.")
print("missing" if name not in entries else ("equal" if entries[name]==record else "different"))
PY
}

crew_manifest_json_entry_remove() {
  local manifest="$1" category="$2" name="$3" target="$4" target_key="$5"
  python3 - "$manifest" "$category" "$name" "$target" "$target_key" <<'PY'
import json, os, pathlib, tempfile, sys
mp=pathlib.Path(sys.argv[1]); category,name=sys.argv[2:4]; tp=pathlib.Path(sys.argv[4]); key=sys.argv[5]
manifest=json.loads(mp.read_text()); record=manifest.get(category,{}).get(name)
target=json.loads(tp.read_text()); entries=target.get(key,{})
if entries.get(name)==record: entries.pop(name,None)
if entries: target[key]=entries
else: target.pop(key,None)
if not target: tp.unlink(missing_ok=True); raise SystemExit
fd,tmp=tempfile.mkstemp(prefix=f".{tp.name}.",suffix=".tmp",dir=tp.parent)
with os.fdopen(fd,"w") as f:
    json.dump(target,f,indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
os.replace(tmp,tp)
PY
}

crew_json_entry_names() {
  python3 - "$1" "$2" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1])
try: data=json.loads(p.read_text())
except FileNotFoundError: raise SystemExit(f"ERROR: Required source JSON not found: {p}")
except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed source JSON {p}: {exc}")
entries=data.get(sys.argv[2])
if not isinstance(entries,dict): raise SystemExit(f"ERROR: {p} must contain object '{sys.argv[2]}'.")
print("\n".join(entries))
PY
}

crew_json_entry_state() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, pathlib, sys
s,t,sk,tk,name=sys.argv[1:6]; source=json.loads(pathlib.Path(s).read_text()); p=pathlib.Path(t)
if not p.exists(): print("missing"); raise SystemExit
try: target=json.loads(p.read_text())
except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed target JSON {p}: {exc}")
entries=target.get(tk,{})
if not isinstance(entries,dict): raise SystemExit(f"ERROR: {p} property '{tk}' must be an object.")
print("missing" if name not in entries else ("equal" if entries[name] == source[sk][name] else "different"))
PY
}

crew_json_entry_update() {
  local action="$1" source="$2" target="$3" source_key="$4" target_key="$5" name="$6"
  python3 - "$action" "$source" "$target" "$source_key" "$target_key" "$name" <<'PY'
import json, os, pathlib, tempfile, sys
action,s,t,sk,tk,name=sys.argv[1:7]; sp=pathlib.Path(s); tp=pathlib.Path(t)
try: source=json.loads(sp.read_text())
except FileNotFoundError: raise SystemExit(f"ERROR: Required source JSON not found: {sp}")
except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed source JSON {sp}: {exc}")
if tp.exists():
    try: target=json.loads(tp.read_text())
    except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed target JSON {tp}: {exc}")
else: target={}
entries=target.get(tk,{})
if not isinstance(entries,dict): raise SystemExit(f"ERROR: {tp} property '{tk}' must be an object.")
if action=="set":
    entries[name]=source[sk][name]; target[tk]=entries
    if not tp.exists() and "$schema" in source: target["$schema"]=source["$schema"]
elif action=="remove":
    if entries.get(name)==source[sk].get(name): entries.pop(name,None)
    if entries: target[tk]=entries
    else: target.pop(tk,None)
else: raise SystemExit("ERROR: Invalid JSON entry action.")
tp.parent.mkdir(parents=True,exist_ok=True)
if not target:
    tp.unlink(missing_ok=True); raise SystemExit
fd,tmp=tempfile.mkstemp(prefix=f".{tp.name}.",suffix=".tmp",dir=tp.parent)
with os.fdopen(fd,"w") as f:
    json.dump(target,f,indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
os.replace(tmp,tp)
PY
}

crew_hook_merge() {
  local source="$1" target="$2" manifest="$3" category="$4" config_path="$5"
  python3 - "$source" "$target" "$manifest" "$category" "$config_path" <<'PY'
import json, os, pathlib, tempfile, sys
sp,tp,mp=map(pathlib.Path,sys.argv[1:4]); category,config_path=sys.argv[4:6]
try: source=json.loads(sp.read_text())
except FileNotFoundError: raise SystemExit(f"ERROR: Required hooks JSON not found: {sp}")
except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed source JSON {sp}: {exc}")
target_existed=tp.exists()
if target_existed:
    try: target=json.loads(tp.read_text())
    except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed target JSON {tp}: {exc}")
else: target={}
hooks=target.setdefault("hooks",{})
if not isinstance(hooks,dict): raise SystemExit(f"ERROR: {tp} property 'hooks' must be an object.")
try: manifest=json.loads(mp.read_text()) if mp.exists() else {"version":1}
except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed ownership manifest {mp}: {exc}")
records=manifest.setdefault(category,{})
if not target_existed:
    manifest.setdefault("createdConfigs",{})[config_path]=True
added=0
for event, commands in source.get("hooks",{}).items():
    if not isinstance(commands,list): raise SystemExit(f"ERROR: Source hook '{event}' must be an array.")
    current=hooks.setdefault(event,[])
    if not isinstance(current,list): raise SystemExit(f"ERROR: Target hook '{event}' must be an array.")
    for command in commands:
        if command not in current:
            current.append(command); records.setdefault(event,[]).append(command); added+=1
def write_atomic(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix=f".{path.name}.",suffix=".tmp",dir=path.parent)
    with os.fdopen(fd,"w") as f:
        json.dump(data,f,indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
    os.replace(tmp,path)
write_atomic(tp,target)
if added: write_atomic(mp,manifest)
print(added)
PY
}

crew_hook_unmerge() {
  local target="$1" manifest="$2" category="$3" config_path="$4"
  [[ -f "$manifest" ]] || return 0
  python3 - "$target" "$manifest" "$category" "$config_path" <<'PY'
import json, os, pathlib, tempfile, sys
tp,mp=map(pathlib.Path,sys.argv[1:3]); category,config_path=sys.argv[3:5]
manifest=json.loads(mp.read_text()); records=manifest.get(category,{})
if not records: raise SystemExit
if tp.exists():
    try: target=json.loads(tp.read_text())
    except json.JSONDecodeError as exc: raise SystemExit(f"ERROR: Malformed target JSON {tp}: {exc}")
    hooks=target.get("hooks",{})
    if not isinstance(hooks,dict): raise SystemExit(f"ERROR: {tp} property 'hooks' must be an object.")
    for event, commands in records.items():
        current=hooks.get(event,[])
        for command in commands:
            if command in current:
                current.remove(command)
        if not current: hooks.pop(event,None)
    if not hooks: target.pop("hooks",None)
else: target={}
manifest.pop(category,None)
created=manifest.get("createdConfigs",{})
was_created=created.pop(config_path,None) is True
if not created: manifest.pop("createdConfigs",None)
def write_atomic(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix=f".{path.name}.",suffix=".tmp",dir=path.parent)
    with os.fdopen(fd,"w") as f:
        json.dump(data,f,indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
    os.replace(tmp,path)
if tp.exists():
    if target or not was_created: write_atomic(tp,target)
    else: tp.unlink()
if set(manifest) <= {"version"}: mp.unlink(missing_ok=True)
else: write_atomic(mp,manifest)
PY
}
