# Security

Dori runs on your desktop with your user's privileges and talks to an attached
Android phone over adb. A bug here can mean a process you did not start being
killed, a file another user can read, or something the phone sent being run as a
command. Those are worth reporting privately.

## Reporting a vulnerability

Use GitHub's private reporting:
[**Report a vulnerability**](https://github.com/infiniV/omarchy-dori/security/advisories/new).

Please do not open a public issue for anything in the categories below.

Include what you would put in a bug report — phone, Android version, connection,
and the exact commands — plus what an attacker gets out of it.

I will acknowledge within a week. Dori is a personal project maintained in spare
time; there is no paid support and no bounty, but real issues get fixed and
credited.

## In scope

- Command injection through device output, filenames, or plugin settings
- Files written to paths other local users can read or replace
- Killing or signalling processes Dori did not start
- Privilege escalation through `bin/dori-setup` or the v4l2loopback setup
- Secrets or clipboard contents leaking to disk in a readable place

## Out of scope

- Anything that requires the attacker to already have your user's shell
- adb itself, scrcpy, and v4l2loopback — report those upstream
- A phone with USB debugging enabled being usable by whoever holds the phone
