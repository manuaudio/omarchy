#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const source = fs.readFileSync(path.join(root, 'shell/Commons/TimerInterval.js'), 'utf8').replace(/^\.pragma library\n/, '')
const timer = {}
vm.createContext(timer)
vm.runInContext(source, timer)

const SECOND = 1000
const MINUTE = 60 * 1000
const MAX_MS = 2147483647

assertEqual(timer.count('900', 900, 30, SECOND), 900, 'numeric strings are read as a count')
assertEqual(timer.count(900, 900, 30, SECOND), 900, 'numbers are read as a count')
assertEqual(timer.count('15m', 900, 30, SECOND), 900, 'a value with a unit suffix falls back to the default')
assertEqual(timer.count('abc', 900, 30, SECOND), 900, 'a non-numeric value falls back to the default')
assertEqual(timer.count('', 900, 30, SECOND), 900, 'an empty value falls back to the default')
assertEqual(timer.count(null, 900, 30, SECOND), 900, 'a null value falls back to the default')
assertEqual(timer.count(5, 900, 30, SECOND), 30, 'values below the minimum clamp up to it')
assertEqual(timer.count(-5, 15, 1, MINUTE), 1, 'negative values clamp up to the minimum')
assertEqual(timer.count('2.9', 15, 1, MINUTE), 2, 'fractional values round down to whole units')

assertEqual(timer.count(35791, 15, 1, MINUTE), 35791, 'the largest minute count that fits a Qt timer is kept')
assertEqual(timer.count(35792, 15, 1, MINUTE), 35791, 'the first minute count that would overflow is capped')
assert(timer.count(50000, 15, 1, MINUTE) * MINUTE <= MAX_MS, 'a huge minute count stays within the Qt timer range')
assert(timer.count(50000, 15, 1, MINUTE) * MINUTE > 0, 'a huge minute count never wraps negative')
assertEqual(timer.count(1e12, 900, 30, SECOND), 2147483, 'a huge second count is capped at the Qt timer range')
assertEqual(timer.count('Infinity', 900, 30, SECOND), 900, 'Infinity falls back to the default')

const weatherSource = fs.readFileSync(path.join(root, 'shell/plugins/panels/weather/Panel.qml'), 'utf8')
assert(/refreshMinutes: Util\.timerIntervalCount\(setting\("refreshMinutes", 15\), 15, 1, 60 \* 1000\)/.test(weatherSource), 'weather bounds its refresh interval through the shared helper')

const agentsSource = fs.readFileSync(path.join(root, 'shell/plugins/agents/Main.qml'), 'utf8')
assert(/refreshIntervalSec: Util\.timerIntervalCount\(setting\("refreshIntervalSec", 900\), 900, 30, 1000\)/.test(agentsSource), 'agents bounds its refresh interval through the shared helper')

const utilSource = fs.readFileSync(path.join(root, 'shell/Commons/Util.qml'), 'utf8')
assert(/return TimerInterval\.count\(value, fallback, min, unitMs\)/.test(utilSource), 'Util exposes the shared timer interval helper')
JS
