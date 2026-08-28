# Shared helpers for the dori-* scripts. Sourced, never run on its own.
#
# Two things live here because getting them wrong is a security bug rather than
# a bug: where runtime state is kept, and how Dori decides that a process is
# one of its own.

# Runtime state belongs in $XDG_RUNTIME_DIR — per user, 0700, gone at logout.
# Without it (a bare ssh session, a cron job) the old fallback was /tmp/dori,
# a name any other user on the machine can create first and then own or point
# somewhere else. Use a uid-suffixed directory instead, create it 0700, and
# refuse outright to use one this user does not own.
dori_rundir() {
  local dir uid
  uid=$(id -u)
  if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
    dir="$XDG_RUNTIME_DIR/dori"
  else
    dir="/tmp/dori-$uid"
  fi
  # No -p: the parent ($XDG_RUNTIME_DIR, or /tmp) always exists already, and
  # under -p the mode applies only to the deepest directory — so dropping it
  # keeps 0700 guaranteed at creation rather than set a moment afterwards.
  mkdir -m 700 "$dir" 2>/dev/null
  if [[ -L $dir || ! -d $dir ]] || [[ "$(stat -c %u "$dir" 2>/dev/null)" != "$uid" ]]; then
    echo "dori: $dir is not a directory this user owns; refusing to use it" >&2
    return 1
  fi
  chmod 700 "$dir" 2>/dev/null
  printf '%s\n' "$dir"
}

# Everything Dori keeps running — the camera stream, the mirror, a recording,
# the notification relay — runs as a transient systemd user unit with a fixed
# name: dori-camera, dori-mirror, dori-record, dori-notify.
#
# That is the whole ownership model. Dori never looks for its processes by
# name, argument, or pid: a unit called dori-mirror was started by Dori and
# nothing else, and `systemctl --user stop dori-mirror` signals that unit's
# cgroup, so there is no pid to validate and no window in which the pid could
# have been recycled. Another scrcpy on this login — however it was started,
# whatever its command line says — is not in that unit and cannot be touched.
#
# The unit's Description carries the one fact about each service that the
# panel wants back (which camera, which file), so it reads in `systemctl
# --user status` too.

dori_unit() { printf 'dori-%s.service\n' "$1"; }

dori_unit_active() {
  systemctl --user is-active --quiet "$(dori_unit "$1")" 2>/dev/null
}

dori_unit_description() {
  dori_unit_active "$1" || return 1
  systemctl --user show "$(dori_unit "$1")" -p Description --value 2>/dev/null
}

# dori_unit_start NAME LOG DESCRIPTION COMMAND...
#
# Output goes to LOG so "see $LOG" in the error messages stays true. The user
# manager already has the session's display variables; the adb and scrcpy
# knobs, and PATH, are copied from the caller — only the ones that are set,
# because an empty ADB_SERVER_SOCKET is not the same as an absent one.
dori_unit_start() {
  local name=$1 log=$2 desc=$3
  shift 3
  local env=() var
  for var in PATH ADB_SERVER_SOCKET ANDROID_ADB_SERVER_PORT ANDROID_ADB_SERVER_ADDRESS \
    ADB_TRACE SCRCPY_SERVER_PATH SCRCPY_ICON_PATH WAYLAND_DISPLAY DISPLAY \
    HYPRLAND_INSTANCE_SIGNATURE SDL_VIDEODRIVER; do
    [[ -n ${!var:-} ]] && env+=(-E "$var")
  done
  # A unit that died and was not collected would block the name. --collect
  # keeps that from happening; reset-failed covers a unit started without it.
  systemctl --user reset-failed "$(dori_unit "$name")" 2>/dev/null
  systemd-run --user --unit="dori-$name" --collect --quiet \
    -p Description="$desc" \
    -p StandardOutput=append:"$log" -p StandardError=inherit \
    -p TimeoutStopSec=20 \
    "${env[@]}" -- "$@"
}

# Stop the unit and wait for it to be gone. SIGTERM first, so scrcpy can
# finalise a recording; SIGKILL only after TimeoutStopSec.
dori_unit_stop() {
  dori_unit_active "$1" || return 0
  systemctl --user stop "$(dori_unit "$1")" 2>/dev/null
}

dori_require_user_systemd() {
  # "degraded" or "starting" exit non-zero but still mean the manager is there;
  # only no answer, or "offline", means there is no user session to run in.
  local state
  state=$(systemctl --user is-system-running 2>/dev/null)
  [[ -n $state && $state != "offline" ]] && return 0
  echo "dori: no systemd user session; Dori runs its services as user units and cannot start without one" >&2
  return 1
}
