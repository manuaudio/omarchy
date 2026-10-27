function secondsFromConfig(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
}

// 0 means the action is disabled, not "fire immediately". min(0, 300) would
// otherwise make IdleMonitor report idle as soon as an inhibitor is released.
function firstIdleTimeout(screensaverSeconds, lockSeconds) {
  var times = []
  if (screensaverSeconds > 0) times.push(screensaverSeconds)
  if (lockSeconds > 0) times.push(lockSeconds)
  if (times.length === 0) return 0
  var min = times[0]
  for (var i = 1; i < times.length; i++) {
    if (times[i] < min) min = times[i]
  }
  return min
}

function delayAfterFirstIdle(timeoutSeconds, firstIdleSeconds) {
  if (!(timeoutSeconds > 0)) return 0
  var delay = timeoutSeconds - firstIdleSeconds
  return delay > 0 ? delay : 0
}

function eventParts(event, count) {
  try {
    if (event && event.parse) return event.parse(count)
  } catch (error) {
  }
  return String(event && event.data ? event.data : "").split(",")
}

function windowAddress(address) {
  return String(address || "").replace(/^0x/i, "").toLowerCase()
}

function screensaverWindowsAfter(windows, address, visible) {
  var key = windowAddress(address)
  var next = {}
  for (var existing in windows || {}) {
    var normalized = windowAddress(existing)
    if (normalized && normalized !== key && windows[existing]) next[normalized] = true
  }

  if (key && visible) next[key] = true

  return {
    windows: next,
    count: Object.keys(next).length
  }
}

function screensaverWindowsFromToplevels(toplevels, screensaverClass) {
  var windows = {}
  for (var i = 0; i < (toplevels || []).length; i++) {
    var toplevel = toplevels[i]
    var client = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : {}
    var address = String(toplevel && (toplevel.address || client.address) || "")
    if (address && String(client.class || "") === screensaverClass) windows[address] = true
  }
  return screensaverWindowsAfter(windows, "", false)
}

if (typeof module !== "undefined") {
  module.exports = {
    secondsFromConfig: secondsFromConfig,
    firstIdleTimeout: firstIdleTimeout,
    delayAfterFirstIdle: delayAfterFirstIdle,
    eventParts: eventParts,
    windowAddress: windowAddress,
    screensaverWindowsAfter: screensaverWindowsAfter,
    screensaverWindowsFromToplevels: screensaverWindowsFromToplevels
  }
}
