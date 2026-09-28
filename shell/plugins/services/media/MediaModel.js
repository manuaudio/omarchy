function isProxyPlayer(player) {
  var dbusName = String(player && player.dbusName || "").toLowerCase()
  var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function hasMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
}

function hasTrackMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.trackAlbum || player.trackArtUrl))
}

function playerCanControl(player) {
  return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause || player.canGoNext || player.canGoPrevious))
}

function canHandleAction(player, action) {
  if (!player) return false
  if (action === "next") return !!player.canGoNext
  if (action === "previous") return !!player.canGoPrevious
  if (action === "play") return !!(player.canPlay || player.canTogglePlaying)
  if (action === "pause") return !!(player.canPause || player.canTogglePlaying)
  if (action === "playPause") return !!(player.canTogglePlaying || player.canPlay || player.canPause)
  return false
}

function canCycleSource(player) {
  return !!(player && hasMetadata(player) && (player.isPlaying || player.canPlay))
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true

  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function streamLabelKey(label) {
  var key = String(label || "").toLowerCase()
  key = key.replace(/^pipewire alsa \[/, "")
  key = key.replace(/\]$/, "")
  key = key.replace(/^alsa playback \[/, "")
  key = key.replace(/[^a-z0-9]+/g, "")
  return key
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"]
    || node.description
    || p["media.name"]
    || p["node.name"]
    || node.name
}

function playerAppLabel(player) {
  if (!player) return ""
  var dbus = String(player.dbusName || "")
  dbus = dbus.replace(/^org\.mpris\.MediaPlayer2\./, "")
  dbus = dbus.replace(/\.instance[0-9]+$/, "")
  return player.desktopEntry || player.identity || dbus
}

function playerHasPlaybackStream(player, playbackStreams) {
  var playerKey = streamLabelKey(playerAppLabel(player))
  if (!playerKey) return false

  var streams = Array.isArray(playbackStreams) ? playbackStreams : []
  for (var i = 0; i < streams.length; i++) {
    var streamKey = streamLabelKey(rawStreamLabel(streams[i]))
    if (!streamKey) continue
    if (streamKey === playerKey
        || streamKey.indexOf(playerKey) !== -1
        || playerKey.indexOf(streamKey) !== -1)
      return true
  }

  return false
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function trackSignature(player) {
  if (!player) return ""
  return [
    player.trackTitle || "",
    player.trackArtist || "",
    player.trackAlbum || "",
    player.trackArtUrl || ""
  ].join("\u001f")
}

function trackChanged(previousSignature, player) {
  return trackSignature(player) !== String(previousSignature || "")
}

function labelFor(player) {
  if (!player) return ""
  return player.trackTitle || player.identity || player.desktopEntry || ""
}

function osdMessage(player, fallback) {
  if (!player) return fallback
  var label = labelFor(player)
  if (label && player.trackArtist) return label + " - " + player.trackArtist
  return label || fallback
}

// What a volume key does to the output, by omarchy-audio-output-volume's rules:
// raise and lower step 5 and clamp to 0..100 (so a boosted sink drops to 100
// on raise), unmuting as they go; mute-toggle flips mute and keeps the volume.
function playerOrder(player, startedAt, fallback) {
  var key = playerKey(player)
  var value = key && startedAt ? startedAt[key] : undefined
  return value === undefined ? fallback : value
}

// Tracks the order players started in. A player that stops becomes the
// preferred one, so play/pause resumes whatever was last heard instead of
// whichever idle app happens to hold a paused audio stream.
function nextPlayingOrder(players, startedAt, serial, preferredKey) {
  var next = {}
  var alive = {}
  var stoppedKey = ""
  var stoppedOrder = -1
  var list = players || []

  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    var key = playerKey(p)
    if (!key) continue

    alive[key] = true
    var started = startedAt ? startedAt[key] : undefined
    if (p.isPlaying) {
      if (started === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = started
      }
    } else if (started !== undefined && started > stoppedOrder) {
      stoppedKey = key
      stoppedOrder = started
    }
  }

  var preferred = stoppedKey || preferredKey || ""
  if (preferred && !alive[preferred]) preferred = ""
  return { startedAt: next, serial: serial, preferredKey: preferred }
}

function oldestPlayingPlayer(players, playbackStreams, startedAt, requirePlaybackStream) {
  var oldest = null
  var oldestOrder = 0
  var playingProxy = null
  var proxyOrder = 0
  var list = players || []

  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || !p.isPlaying) continue
    if (requirePlaybackStream && !playerHasPlaybackStream(p, playbackStreams)) continue

    var order = playerOrder(p, startedAt, i + 1000)
    if (!isProxyPlayer(p) && (!oldest || order < oldestOrder)) {
      oldest = p
      oldestOrder = order
    } else if (isProxyPlayer(p) && (!playingProxy || order < proxyOrder)) {
      playingProxy = p
      proxyOrder = order
    }
  }

  return oldest || playingProxy || null
}

// With nothing playing, the preferred player (the one last used or last heard)
// outranks a player that only holds an audio stream: Spotify keeps a corked
// stream open while paused, while browsers tear theirs down.
function selectActivePlayer(players, playbackStreams, startedAt, preferredKey) {
  var preferred = null
  var trackPlayer = null
  var trackProxy = null
  var streamPlayer = null
  var streamProxy = null
  var controllablePlayer = null
  var controllableProxy = null
  var identityPlayer = null
  var identityProxy = null
  var list = players || []

  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p) continue

    var proxy = isProxyPlayer(p)

    if (preferredKey && playerKey(p) === preferredKey && hasMetadata(p)) preferred = p

    if (playerHasPlaybackStream(p, playbackStreams)) {
      if (!proxy && !streamPlayer) streamPlayer = p
      else if (proxy && !streamProxy) streamProxy = p
    } else if (hasTrackMetadata(p)) {
      if (!proxy && !trackPlayer) trackPlayer = p
      else if (proxy && !trackProxy) trackProxy = p
    } else if (playerCanControl(p)) {
      if (!proxy && !controllablePlayer) controllablePlayer = p
      else if (proxy && !controllableProxy) controllableProxy = p
    } else if (hasMetadata(p)) {
      if (!proxy && !identityPlayer) identityPlayer = p
      else if (proxy && !identityProxy) identityProxy = p
    }
  }

  if (preferred && preferred.isPlaying) return preferred
  return oldestPlayingPlayer(list, playbackStreams, startedAt, true)
    || oldestPlayingPlayer(list, playbackStreams, startedAt, false)
    || preferred || streamPlayer || streamProxy
    || trackPlayer || trackProxy || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
}

function volumeKeyStep(action, percent, muted) {
  if (action === "raise") return { percent: Math.min(percent + 5, 100), muted: false }
  if (action === "lower") return { percent: Math.max(percent - 5, 0), muted: false }
  if (action === "mute-toggle") return { percent: percent, muted: !muted }
  return null
}

function volumeOsdIcon(percent, muted) {
  return muted || percent === 0 ? "volume-muted" : "volume-high"
}

if (typeof module !== "undefined") {
  module.exports = {
    isProxyPlayer: isProxyPlayer,
    hasMetadata: hasMetadata,
    hasTrackMetadata: hasTrackMetadata,
    playerCanControl: playerCanControl,
    canHandleAction: canHandleAction,
    canCycleSource: canCycleSource,
    nodeProps: nodeProps,
    isPlaybackStream: isPlaybackStream,
    streamLabelKey: streamLabelKey,
    rawStreamLabel: rawStreamLabel,
    playerAppLabel: playerAppLabel,
    playerHasPlaybackStream: playerHasPlaybackStream,
    playerKey: playerKey,
    trackSignature: trackSignature,
    trackChanged: trackChanged,
    labelFor: labelFor,
    osdMessage: osdMessage,
    playerOrder: playerOrder,
    nextPlayingOrder: nextPlayingOrder,
    oldestPlayingPlayer: oldestPlayingPlayer,
    selectActivePlayer: selectActivePlayer,
    volumeKeyStep: volumeKeyStep,
    volumeOsdIcon: volumeOsdIcon
  }
}
