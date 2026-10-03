#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const model = requireFromRoot('shell/services/BrightnessModel.js')

// The in-shell brightness keys follow omarchy-brightness-display's steps.
const steps = [
  ['raise', 60, 65], ['lower', 60, 55],
  ['raise', 4, 5], ['raise', 5, 10], ['lower', 5, 4], ['lower', 6, 1],
  ['raise', 98, 100], ['raise', 100, 100], ['lower', 1, 1], ['lower', 2, 1],
]
for (const [action, current, target] of steps) {
  assertEqual(model.brightnessKeyTarget(action, current), target, `brightness ${action} from ${current}% lands on ${target}%`)
}

// The keys write a raw level, not a percentage: brightnessctl turns "N%" into
// roundf(N / 100 * max) with no minimum step, so on a coarse backlight a 5%
// step rounds back to the level it started from and the keys stick.
const brightnessctlRaw = (percent, max) => Math.round(percent / 100 * max)
for (const max of [7, 8, 10, 15, 24, 100, 255, 937, 19393]) {
  // 1% as brightnessctl writes it, but never 0, which turns the panel off.
  const floor = Math.max(brightnessctlRaw(1, max), 1)
  const wrong = []
  for (let raw = 0; raw <= max; raw++) {
    const up = model.brightnessKeyRawTarget('raise', raw, max)
    const down = model.brightnessKeyRawTarget('lower', raw, max)
    const upOk = Number.isInteger(up) && (raw < max ? up > raw && up <= max : up === max)
    const downOk = Number.isInteger(down) && (raw > floor ? down < raw && down >= floor : down === raw)
    if (!upOk) wrong.push(`raise ${raw}->${up}`)
    if (!downOk) wrong.push(`lower ${raw}->${down}`)
  }
  assertDeepEqual(wrong, [], `brightness keys on max_brightness ${max} move every level by at least one raw step, between ${floor} and ${max}`)
}

// On a fine backlight the raw target is the percentage step the script takes.
for (const max of [100, 19393]) {
  for (const [action, current, target] of steps) {
    const raw = brightnessctlRaw(current, max)
    assertEqual(model.brightnessKeyRawTarget(action, raw, max), brightnessctlRaw(target, max), `on max ${max}, brightness ${action} from ${current}% writes ${target}%`)
  }
}

const qml = fs.readFileSync(path.join(root, 'shell/services/BrightnessKeys.qml'), 'utf8')
assert(
  qml.includes('if (!/^(eDP|LVDS|DSI)-/.test(name) || !device) return false'),
  'brightness keys act in the shell only on the internal panel and defer external and Apple displays to the script'
)
assert(
  /if \(setProc\.running\) return true/.test(qml),
  'brightness keys drop a press that overlaps one still being applied, as the script does'
)
assert(
  /file\.reload\(\)\s*file\.waitForJob\(\)/.test(qml),
  'brightness keys read the current level fresh, so a level changed elsewhere steps from the right place'
)
assert(
  qml.includes('BrightnessModel.brightnessKeyRawTarget(action, readNumber(brightnessFile), max)') &&
    !/brightnessKeyTarget\(action, current\) \+ "%"/.test(qml),
  'brightness keys write the raw level the model picks, not a percentage brightnessctl can round back'
)
assert(
  qml.includes('var percent = Math.round(100 * readNumber(brightnessFile) / max)'),
  'brightness keys compute percentages as brightnessctl reports them'
)

const shellQml = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')
assert(
  /if \(!shell\.brightnessKeys\.handle\(entry\.target\)\)\s*Util\.execArgv\(\["omarchy-brightness-display", entry\.target === "raise" \? "\+5%" : "5%-"\]\)/.test(shellQml),
  'a brightness key the shell declines runs omarchy-brightness-display'
)
JS
