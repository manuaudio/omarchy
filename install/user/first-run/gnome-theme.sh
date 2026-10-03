# The install-time theme set runs headless and skips its GNOME sync, so apply
# the current theme's color scheme and icons now that a session bus exists.
# omarchy-theme-set-gnome also skips silently without a bus, so fail here
# instead; that leaves first-run unmarked and the step retries next login.
if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  echo "No DBus session bus; GNOME theme will be applied on next login" >&2
  exit 1
fi

omarchy-theme-set-gnome
