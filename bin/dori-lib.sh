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
  mkdir -p -m 700 "$dir" 2>/dev/null
  if [[ -L $dir || ! -d $dir ]] || [[ "$(stat -c %u "$dir" 2>/dev/null)" != "$uid" ]]; then
    echo "dori: $dir is not a directory this user owns; refusing to use it" >&2
    return 1
  fi
  chmod 700 "$dir" 2>/dev/null
  printf '%s\n' "$dir"
}

# Field 22 of /proc/<pid>/stat: the moment the process started, in clock ticks
# since boot. Together with the pid it names one process for good — a recycled
# pid cannot match it. The comm field is parenthesised and may itself contain
# spaces or brackets, so strip up to the last ") " before counting fields.
dori_proc_starttime() {
  local stat
  { stat=$(</proc/"$1"/stat); } 2>/dev/null || return 1
  stat=${stat##*") "}
  awk '{print $20}' <<<"$stat"
}

# Remember the recording Dori just started: pid, start time, output file.
dori_record_write() {
  local rundir=$1 pid=$2 file=$3 start
  start=$(dori_proc_starttime "$pid") || return 1
  printf '%s %s %s\n' "$pid" "$start" "$file" >"$rundir/record.pid"
}

dori_record_forget() {
  rm -f "$1/record.pid"
}

# The recording Dori owns, as "<pid> <file>", or nothing at all.
#
# A scrcpy command line containing --record= is not proof of anything: another
# scrcpy recording on this login belongs to whoever started it, and stopping it
# would cost them their video. So the only recording Dori will report on or
# stop is the process it started itself, still alive, still scrcpy, still with
# the start time it had when it was written down.
dori_record_live() {
  local pidfile="$1/record.pid" pid start file
  [[ -r $pidfile ]] || return 1
  read -r pid start file <"$pidfile" || return 1
  [[ $pid =~ ^[0-9]+$ && -n $start && -n $file ]] || return 1
  [[ -d /proc/$pid ]] || return 1
  [[ "$(stat -c %u "/proc/$pid" 2>/dev/null)" == "$(id -u)" ]] || return 1
  [[ "$(cat /proc/"$pid"/comm 2>/dev/null)" == "scrcpy" ]] || return 1
  [[ "$(dori_proc_starttime "$pid")" == "$start" ]] || return 1
  printf '%s %s\n' "$pid" "$file"
}

dori_record_pid() {
  local live
  live=$(dori_record_live "$1") || return 1
  printf '%s\n' "${live%% *}"
}

dori_record_file() {
  local live
  live=$(dori_record_live "$1") || return 1
  printf '%s\n' "${live#* }"
}
