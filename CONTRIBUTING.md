# Contributing to Dori

Bug reports and small, tested patches are both welcome. Dori is a bash + QML
plugin for the Omarchy bar, so there is no build step and no dependency tree:
clone it, link it, use it.

## Getting it running

```bash
git clone https://github.com/infiniV/omarchy-dori.git
cd omarchy-dori
bin/dori-setup          # loads v4l2loopback and checks the host packages
```

Point Omarchy at the clone rather than the installed copy, restart the bar, and
the panel will load from your working tree.

Everything the panel does, the scripts in `bin/` also do from a terminal. When
something misbehaves, run the script directly first — the shell is the shorter
path to the actual error.

```bash
bin/dori-status         # one JSON blob describing the phone and every running piece
journalctl --user -u 'dori-*' -f
```

## House rules for the scripts

These are not style preferences; getting them wrong has broken Dori before.

- **Every long-running process is a named systemd user unit.** Never a bare
  background job, never a `pkill` that pattern-matches a process name. If Dori
  did not start it, Dori does not stop it.
- **No shared `/tmp` paths.** Anything Dori writes goes somewhere only this
  user can write.
- **Nothing the phone sends is trusted as shell input.** Device output goes
  into arrays and quoted expansions, never into a string that a shell parses.
- **`shellcheck bin/dori-*` is clean** before you open a pull request.
- Settings keys in `manifest.json` must match the keys the scripts and
  `Panel.qml` actually read. CI checks the manifest parses; matching keys is on
  you.

## Pull requests

- Branch off `master`. `master` is protected: changes land through a pull
  request, and CI plus a review have to pass.
- One change per pull request.
- Say which phone and Android version you tested against. "Works on mine" with
  the model named is worth more than a clean diff.
- CodeRabbit reviews every pull request automatically. It is a reviewer, not a
  gate — disagree with it in the thread if it is wrong.
- Commit messages: one line, present tense, describing the change from the
  user's side. Look at `git log` for the tone.

## Reporting bugs

Use the bug report template and include the `dori-status` output. A phone that
is plugged in but not authorised looks exactly like a working one from the
outside, and that output is what tells the two apart.
