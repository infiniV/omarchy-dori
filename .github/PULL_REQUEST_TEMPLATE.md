## What this changes

<!-- One or two sentences. What is different for someone using Dori? -->

## Why

<!-- The problem. Link the issue if there is one: Fixes #123 -->

## How it was tested

<!-- Dori talks to real hardware; say what you ran it against. -->

- [ ] Phone model / Android version:
- [ ] Tested over USB
- [ ] Tested over Wi-Fi
- [ ] Ran the affected `bin/dori-*` script directly from a terminal
- [ ] Opened the panel and used the affected control

## Checklist

- [ ] `shellcheck bin/dori-*` is clean
- [ ] No new long-running process that is not a named systemd user unit
- [ ] Nothing Dori did not start gets killed
- [ ] `manifest.json` settings keys match what the code reads
- [ ] README updated if behaviour visible to a user changed
