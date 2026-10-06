#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command jq

if ! command -v quickshell >/dev/null 2>&1; then
  skip "quickshell unavailable; skipping startup config runtime test"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/qml" "$test_tmp/home"
ln -s "$ROOT/shell/Commons" "$test_tmp/qml/Commons"
config="$test_tmp/shell.json"
printf '%s\n' '{"version":1,"plugins":["custom.plugin"]}' >"$config"

ROOT="$ROOT" FIXTURE="$test_tmp/qml/shell.qml" python3 <<'PY'
import os
import re
from pathlib import Path

source = (Path(os.environ["ROOT"]) / "shell/shell.qml").read_text()


def function_source(name):
  marker = f"  function {name}("
  start = source.index(marker)
  brace = source.index("{", start)
  depth = 0
  for index in range(brace, len(source)):
    if source[index] == "{":
      depth += 1
    elif source[index] == "}":
      depth -= 1
      if depth == 0:
        return source[start:index + 1]
  raise ValueError(f"unterminated function: {name}")


user_config_view = re.search(r"FileView\s*\{\s*\n\s*id: userConfigFile[\s\S]*?\n\s*\}", source)
completed = re.search(r"Component\.onCompleted:\s*\{([\s\S]*?)\n\s*\}", source)
if not user_config_view or not re.search(r"\n\s*blockLoading:\s*true\s*\n", user_config_view.group(0)):
  raise SystemExit("user config FileView does not make its initial read blocking")
if not completed or not completed.group(1).lstrip().startswith("shell.applyShellConfig()"):
  raise SystemExit("shell does not apply user config before startup work")

functions = "\n\n".join(function_source(name) for name in (
  "applyShellConfig",
  "persistShellConfig",
  "mutateShellConfig",
))
fixture = f'''import QtQml
import Quickshell
import Quickshell.Io
import "Commons"

ShellRoot {{
  id: shell

  property var builtinShellConfig: ({{ version: 1, plugins: [] }})
  property var defaultsConfig: builtinShellConfig
  property var shellConfig: builtinShellConfig

{functions}

  FileView {{
    id: userConfigFile
    path: Quickshell.env("TEST_CONFIG")
    blockLoading: true
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: shell.applyShellConfig()
    onLoadFailed: function(error) {{ shell.applyShellConfig() }}
    onFileChanged: reload()
  }}

  Component.onCompleted: {{
    shell.applyShellConfig()
    shell.mutateShellConfig(function(copy) {{ copy.autoSeed = true }})
    quitTimer.start()
  }}

  Timer {{
    id: quitTimer
    interval: 100
    onTriggered: Qt.quit()
  }}
}}
'''
Path(os.environ["FIXTURE"]).write_text(fixture)
PY

run_harness() {
  local label=$1 log=$2

  TEST_CONFIG="$config" HOME="$test_tmp/home" QT_QPA_PLATFORM=offscreen \
    timeout 5 quickshell -p "$test_tmp/qml" --no-color >"$log" 2>&1 || {
      cat "$log" >&2
      fail "$label"
    }
}

run_harness "existing startup config harness runs" "$test_tmp/quickshell-existing.log"
jq -e '.plugins == ["custom.plugin"] and .autoSeed == true' "$config" >/dev/null ||
  fail "startup mutation preserves the loaded user config" "$(cat "$config")"
pass "startup mutation preserves the loaded user config"

rm "$config"
run_harness "missing startup config harness runs" "$test_tmp/quickshell-missing.log"
jq -e '.plugins == [] and .autoSeed == true' "$config" >/dev/null ||
  fail "startup mutation creates a genuinely missing user config" "$(cat "$config")"
pass "startup mutation creates a genuinely missing user config"
