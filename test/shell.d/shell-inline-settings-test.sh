#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const shellQml = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')

// Lift updateEntryInline out of shell.qml and run it against stubbed shell
// state: the Util helpers it calls, the current config, and the persister.
const match = shellQml.match(/\n  function updateEntryInline\(moduleName, settings\) \{\n[\s\S]*?\n  \}\n/)
assert(match, 'shell.qml defines updateEntryInline')

const Util = {
  isPlainObject: value => value !== null && typeof value === 'object' && !Array.isArray(value),
  canonicalWidgetId: id => String(id || '')
}

function update(config, moduleName, settings) {
  const persisted = []
  const run = new Function(
    'Util', 'shellConfig', 'builtinShellConfig', 'persistShellConfig', 'moduleName', 'settings',
    `${match[0]}\nreturn updateEntryInline(moduleName, settings)`
  )
  const result = run(Util, config, null, next => persisted.push(next), moduleName, settings)
  return { result, persisted }
}

let out = update(
  { bar: { layout: { left: [], center: ['omarchy.clock'], right: [] } }, plugins: [] },
  'omarchy.clock',
  { format: 'long' }
)
assertEqual(out.result, true, 'string layout entry reports a change')
assertEqual(out.persisted.length, 1, 'string layout entry is persisted')
assertDeepEqual(
  out.persisted[0].bar.layout.center,
  [{ id: 'omarchy.clock', format: 'long' }],
  'string layout entry is rewritten to an object carrying the settings'
)

out = update(
  { bar: { layout: { left: [], center: [], right: [] } }, plugins: ['omarchy.elsewhen'] },
  'omarchy.elsewhen',
  { id: 'ignored', cities: ['Tokyo'] }
)
assertEqual(out.result, true, 'string plugins entry reports a change')
assertEqual(out.persisted.length, 1, 'string plugins entry is persisted')
assertDeepEqual(
  out.persisted[0].plugins,
  [{ id: 'omarchy.elsewhen', cities: ['Tokyo'] }],
  'string plugins entry is rewritten to an object carrying the settings'
)

out = update(
  { bar: { layout: { left: [{ id: 'omarchy.power', percentage: false }], center: [], right: [] } }, plugins: [] },
  'omarchy.power',
  { percentage: true }
)
assertEqual(out.result, true, 'object layout entry reports a change')
assertDeepEqual(
  out.persisted[0].bar.layout.left,
  [{ id: 'omarchy.power', percentage: true }],
  'object layout entry is replaced with the new settings'
)

out = update(
  { bar: { layout: { left: [{ id: 'omarchy.power', percentage: true }], center: [], right: [] } }, plugins: [] },
  'omarchy.power',
  { percentage: true }
)
assertEqual(out.result, false, 'unchanged object layout entry reports no change')
assertEqual(out.persisted.length, 0, 'unchanged object layout entry is not persisted')

out = update(
  { bar: { layout: { left: ['omarchy.power'], center: [], right: [] } }, plugins: ['omarchy.mullvad'] },
  'omarchy.unknown',
  { value: 1 }
)
assertEqual(out.result, false, 'unknown id reports no change')
assertEqual(out.persisted.length, 0, 'unknown id is not persisted')
JS
