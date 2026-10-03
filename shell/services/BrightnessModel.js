// omarchy-brightness-display's steps for the brightness keys: 1% at or below
// 5%, otherwise 5%, kept between 1% and 100%.
function brightnessKeyTarget(action, current) {
  if (action === "raise") return Math.min(current < 5 ? current + 1 : current + 5, 100)
  return Math.max(current <= 5 ? current - 1 : current - 5, 1)
}

// The raw backlight level a key press writes, from the raw level and
// max_brightness. It takes the percentage step above, rounded the way
// brightnessctl rounds "N%", but always moves at least one raw step: on a
// coarse backlight (max_brightness 7, 8, 10, 15, 24) a 5% step is under half a
// raw step and would otherwise round back to where it started. Lowering stops
// at 1%, and never at 0, which would turn the panel off.
function brightnessKeyRawTarget(action, raw, max) {
  var target = Math.round(brightnessKeyTarget(action, Math.round(100 * raw / max)) / 100 * max)
  if (action === "raise") return Math.min(Math.max(target, raw + 1), max)

  var floor = Math.max(Math.round(max / 100), 1)
  if (raw <= floor) return raw
  return Math.max(Math.min(target, raw - 1), floor)
}

if (typeof module !== "undefined") {
  module.exports = {
    brightnessKeyTarget: brightnessKeyTarget,
    brightnessKeyRawTarget: brightnessKeyRawTarget
  }
}
