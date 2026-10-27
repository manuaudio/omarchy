#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const idle = requireFromRoot('shell/plugins/services/idle/IdleModel.js')

assertEqual(idle.secondsFromConfig('42.9', 10), 42, 'idle floors configured seconds')
assertEqual(idle.secondsFromConfig('-1', 10), 10, 'idle rejects negative seconds')
assertEqual(idle.secondsFromConfig('nope', 10), 10, 'idle rejects invalid seconds')
assertEqual(idle.secondsFromConfig(0, 300), 0, 'idle keeps an explicit zero timeout')
assertEqual(idle.firstIdleTimeout(150, 300), 150, 'idle uses the sooner of screensaver and lock')
assertEqual(idle.firstIdleTimeout(0, 300), 300, 'idle ignores a disabled screensaver when computing first idle')
assertEqual(idle.firstIdleTimeout(150, 0), 150, 'idle ignores a disabled lock when computing first idle')
assertEqual(idle.firstIdleTimeout(0, 0), 0, 'idle has no first-idle timeout when both actions are disabled')
assertEqual(idle.delayAfterFirstIdle(300, 150), 150, 'idle delays lock until its own timeout')
assertEqual(idle.delayAfterFirstIdle(150, 150), 0, 'idle fires an action immediately when it is the first timeout')
assertEqual(idle.delayAfterFirstIdle(0, 150), 0, 'idle does not schedule a disabled action')

assertDeepEqual(idle.eventParts({ data: 'a,b,c' }, 2), ['a', 'b', 'c'], 'idle parses raw event data')
assertDeepEqual(
  idle.eventParts({ parse: function(count) { return ['parsed', count] } }, 4),
  ['parsed', 4],
  'idle prefers event parser when available'
)

assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, 'b', true),
  { windows: { a: true, b: true }, count: 2 },
  'idle adds visible screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true, b: true }, 'a', false),
  { windows: { b: true }, count: 1 },
  'idle removes closed screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, '', false),
  { windows: { a: true }, count: 1 },
  'idle leaves screensaver windows unchanged without an address'
)
const serviceSource = require('fs').readFileSync(root + '/shell/plugins/services/idle/Service.qml', 'utf8')
assertDeepEqual(
  idle.screensaverWindowsFromToplevels([
    { address: '0xabc', lastIpcObject: { class: 'org.omarchy.screensaver' } },
    { address: '0xdef', lastIpcObject: { class: 'foot' } }
  ], 'org.omarchy.screensaver'),
  { windows: { '0xabc': true }, count: 1 },
  'idle restores already-open screensaver windows from Hyprland'
)
assert(
  /function syncScreensaverWindows\(\)[\s\S]*?Hyprland\.toplevels\.values/.test(serviceSource) &&
    /target: Hyprland\.toplevels[\s\S]*?onValuesChanged.*syncScreensaverWindows\(\)/.test(serviceSource) &&
    /Component\.onCompleted:[\s\S]*?syncScreensaverWindows\(\)/.test(serviceSource),
  'idle seeds the screensaver count at startup and refreshes it with Hyprland clients'
)
const syncBody = serviceSource.match(/function syncScreensaverWindows\(\) \{[\s\S]*?\n  \}/)[0]
assert(
  syncBody.includes('handleScreensaverWindowOpened(') &&
    !syncBody.includes('handleScreensaverWindowClosed(') &&
    !syncBody.includes('root.screensaverWindows ='),
  'idle sync never closes a counted screensaver whose class Hyprland has not reported yet'
)
const eventBody = serviceSource.match(/function handleHyprlandEvent\(event\) \{[\s\S]*?\n  \}/)[0]
assert(
  /!root\.closedWindows\[address\]\) root\.handleScreensaverWindowOpened/.test(syncBody) &&
    /if \(address\) root\.closedWindows\[address\] = true\n\s*if \(root\.screensaverWindows\[address\]\) root\.handleScreensaverWindowClosed\(address\)/.test(eventBody) &&
    /delete root\.closedWindows\[/.test(eventBody.split('closewindow')[0]),
  'idle sync never revives a window closewindow closed, counted or not, until that address opens again'
)
assertDeepEqual(
  idle.screensaverWindowsFromToplevels([{ address: 'abc', lastIpcObject: {} }], 'org.omarchy.screensaver'),
  { windows: {}, count: 0 },
  'idle cannot classify a toplevel before Hyprland reports its class'
)

// A force-launched screensaver stays up across idle cycles, and the bar reads
// this count to stay below it, so starting or cancelling a cycle keeps it.
const idleSource = require('fs').readFileSync(root + '/shell/plugins/services/idle/Service.qml', 'utf8')
for (const name of ['startIdleCycle', 'cancelIdleCycle']) {
  const body = idleSource.match(new RegExp('function ' + name + '\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}'))
  assert(body && !body[0].includes('resetScreensaverWindows()'), name + ' keeps screensaver windows that are still open')
}
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mkdir -p "$test_home"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" stay-awake >/dev/null
[[ -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists enabled state"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" allow-idle >/dev/null
[[ ! -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists disabled state"

pass "Stay Awake toggle persists state"
