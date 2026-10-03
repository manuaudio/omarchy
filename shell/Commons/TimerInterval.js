.pragma library

// Qt stores Timer.interval as a signed 32-bit millisecond count. A larger
// product wraps negative, Qt resets it to 1ms, and a repeating timer then
// fires continuously. A NaN interval becomes 0 and does the same.
var MAX_MS = 2147483647

// Read a user-configured timer interval as a whole number of units
// (unitMs milliseconds each), falling back on anything that is not a plain
// number and clamping to [min, the most units that still fit a Qt timer].
function count(value, fallback, min, unitMs) {
  var n = NaN
  if (typeof value === "number") n = value
  else if (typeof value === "string" && value.trim() !== "") n = Number(value)
  if (!isFinite(n)) n = fallback
  var max = Math.floor(MAX_MS / unitMs)
  return Math.floor(Math.max(min, Math.min(max, n)))
}
