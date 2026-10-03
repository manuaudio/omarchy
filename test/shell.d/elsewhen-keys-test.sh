#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# PanelKeyCatcher keeps some letters for moving and deleting and never passes
# them on, so a panel shortcut on one of those letters silently does nothing.
# Run the catcher's real key handler on every key Elsewhen's onTextKey answers.
run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

function blockAfter(source, opener, file) {
  const start = source.indexOf(opener)
  if (start === -1) fail(`${file} has ${opener}`)
  let depth = 0
  for (let i = start + opener.length - 1; i < source.length; i++) {
    if (source[i] === '{') depth++
    else if (source[i] === '}' && --depth === 0) return source.slice(start + opener.length, i)
  }
  fail(`${file} closes ${opener}`)
}

const catcherFile = 'shell/Ui/PanelKeyCatcher.qml'
const catcherBody = blockAfter(fs.readFileSync(path.join(root, catcherFile), 'utf8'), 'Keys.onPressed: function(event) {', catcherFile)

// Qt's own values; a name the handler starts using without one here fails loudly.
const qtValues = {
  Key_Escape: 0x01000000, Key_Tab: 0x01000001, Key_Backtab: 0x01000002,
  Key_Return: 0x01000004, Key_Enter: 0x01000005, Key_Delete: 0x01000007,
  Key_Left: 0x01000012, Key_Up: 0x01000013, Key_Right: 0x01000014, Key_Down: 0x01000015,
  Key_Space: 0x20, Key_J: 0x4a, Key_K: 0x4b,
  ShiftModifier: 0x02000000, ControlModifier: 0x04000000, AltModifier: 0x08000000
}
const Qt = new Proxy(qtValues, {
  get(target, name) {
    if (!(name in target)) throw new Error(`stand-in Qt lacks ${String(name)}`)
    return target[name]
  }
})

const signals = ['moveRequested', 'reorderRequested', 'activateRequested', 'returnRequested', 'closeRequested', 'deleteRequested', 'tabRequested', 'textKey']

function signalsFor(key, text) {
  const emitted = []
  const scope = { Qt, blocked: false, reorderable: false }
  for (const name of signals) scope[name] = () => emitted.push(name)
  const handler = vm.runInNewContext(`(function(event) {${catcherBody}})`, scope)
  handler({ key, text, modifiers: 0, accepted: false })
  return emitted.join(',')
}

// A plain press of a printable key: Qt's key code for it is its uppercase code point.
function signalsForText(text) {
  return signalsFor(text.toUpperCase().codePointAt(0), text)
}

assertEqual(signalsFor(Qt.Key_Escape, '\x1b'), 'closeRequested', 'the key catcher runs on a stand-in scope')

const panelFile = 'shell/plugins/panels/elsewhen/Panel.qml'
const textKeyBody = blockAfter(fs.readFileSync(path.join(root, panelFile), 'utf8'), 'onTextKey: function(text, modifiers) {', panelFile)
const keys = [...new Set([...textKeyBody.matchAll(/key === "([^"]+)"/g)].map(match => match[1]))]
assert(keys.length > 0, 'elsewhen names the keys it answers')

for (const key of keys)
  assertEqual(signalsForText(key), 'textKey', `elsewhen's "${key}" key reaches its text handler`)
JS
