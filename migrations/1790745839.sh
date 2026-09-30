echo "Let PipeWire follow the source's sample rate"

conf="pipewire/pipewire.conf.d/10-sample-rates.conf"

if [[ ! -f "$HOME/.config/$conf" ]]; then
  omarchy-refresh-config "$conf"
  # PipeWire only reads conf.d at startup. Apply the rates to the running graph
  # too, so the change takes effect now without interrupting playback.
  pw-metadata -n settings 0 clock.allowed-rates "[ 44100 48000 88200 96000 ]" >/dev/null 2>&1 || true
fi
