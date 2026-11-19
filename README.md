# Nudge Lamp

![Nudge Lamp critter in each mood](docs/showcase.gif)

Nudge Lamp is a macOS menu bar app that shows whether your Claude Code sessions are working, waiting for you, or idle. I built it because I kept switching to a browser while an agent ran, and only noticed much later that it had stopped on a permission prompt.

## The critter

A small pixel light bulb sits in the menu bar and acts out what your sessions are doing. Its glass glows in the color of the most urgent state. The most urgent session decides its mood. A number next to it counts the sessions that need you, and the menu lists every session with its state, how long it has been in that state, and its folder.

| Mood | When | What it does |
| --- | --- | --- |
| ![blocked](docs/blocked.gif) | A session stopped mid-turn on a permission prompt, a question or another dialog. | Flashes red and jumps, waves or shakes next to a red exclamation mark. |
| ![finished](docs/finished.gif) | A session finished its turn and you have not looked at it yet. | Glows amber and cheers, taps its foot or looks around next to a sparkle. |
| ![working](docs/working.gif) | A session is running a turn or a shell command. | Glows green and walks, types or thinks with a row of dots. |
| ![idle](docs/idle.gif) | Nothing is running and nothing is waiting. | Switches off, dims and sleeps, blinks or daydreams. |

Each mood has three animations. The critter switches to another one every 8 to 16 seconds, and switches right away when the mood changes. The critter is drawn at 1.5 points per sprite pixel on a notched display and at 1 point elsewhere, so it stays sharp at either menu bar height.

Turn off Animated Critter in the menu to get a plain status icon instead: a red exclamation mark, an orange check mark, a green half circle or a grey ring.

## How it works

Nudge Lamp reads session state with `claude agents --json`. The Claude Code docs call this command "the supported way to read session state from outside Claude Code, for example from a status bar". For each live session it reports a `status` of `busy`, `waiting` or `idle`, and a `waitingFor` reason such as `permission prompt`.

The command reads local state only. It sends no requests to Anthropic and uses no tokens. I checked this by pointing every proxy variable at a closed local port: the command still listed all sessions, with exit code 0, in 0.16 seconds.

The command costs about 0.17 seconds of CPU per run, too much to run every second. Claude Code keeps one small file per running session in `~/.claude/sessions`. Nudge Lamp checks only the modification times of those files once a second, which costs almost nothing, and runs the command when a time changes. It also runs the command once a minute in case a change slips past. In a 4 minute test with five sessions open, all 5 status changes came with a file time change, so none slipped past. Nudge Lamp never reads the contents of those files.

Claude Code reports `idle` both for a turn that ended a minute ago and for a session nobody has touched since yesterday. Nudge Lamp tells them apart by remembering whether it saw the session working since you last looked at it. A finished session turns grey again when you focus its iTerm2 tab, click it in the menu, or choose Mark All as Seen.

When a session starts waiting for you, Nudge Lamp waits 1.5 seconds to skip short flickers. Then it plays a sound and posts a banner. Pick the sounds under Sound When Waiting and Sound When Finished in the menu. The lists show the macOS system sounds and any sound files you put in `~/Library/Sounds`, and picking one plays it once. It stays quiet when that session's iTerm2 tab is already in front of you. Clicking a banner or a menu row brings the session's iTerm2 window, tab and split pane to the front. Nudge Lamp finds the tab by matching the session's terminal device (tty) against each iTerm2 session.

Nudge Lamp was tested against Claude Code 2.1.328 in November 2026. Run `NudgeLamp --print` to see what the app reads.

## Install

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/yoshimoriryu/nudge-lamp/main/install.sh | bash
```

The script downloads the latest release into `~/Applications`, starts it and adds it to your login items. It needs macOS 15 or later and no developer tools. The release runs on Apple silicon and Intel Macs. Run the same command again to update.

The script takes options after `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/yoshimoriryu/nudge-lamp/main/install.sh | bash -s -- --no-login     # skip the login item
curl -fsSL https://raw.githubusercontent.com/yoshimoriryu/nudge-lamp/main/install.sh | bash -s -- --from-source  # build with Swift 6
curl -fsSL https://raw.githubusercontent.com/yoshimoriryu/nudge-lamp/main/install.sh | bash -s -- --uninstall
```

On first launch macOS asks whether Nudge Lamp may send notifications. The first time iTerm2 is in front, macOS also asks whether Nudge Lamp may control iTerm2, which it needs to see which tab you are on and to switch tabs. If you said no to either one, click the critter. A Setup section at the top of the menu opens the right page in System Settings.

The app has an ad hoc signature and is not notarized. The install script downloads it with curl, which does not mark files as quarantined, so Gatekeeper does not stop it. If you download the zip from the releases page with a browser instead, macOS blocks the first launch. To allow it, open System Settings > Privacy & Security and click Open Anyway.

## Commands

| Command | What it does |
| --- | --- |
| `make test` | Runs the unit tests for the state logic. |
| `make install` | Builds from your checkout and installs it with `install.sh --from-source`. |
| `make doctor` | Prints the app version, where it found `claude`, the session count and the state of each macOS permission. |
| `make release` | Builds a universal app, zips it and publishes a GitHub release for `install.sh`. |
| `make run` | Builds the app and opens it from `build/` without installing it. |
| `make uninstall` | Quits the app and removes it from `~/Applications`. |
| `"build/Nudge Lamp.app/Contents/MacOS/NudgeLamp" --print` | Prints every session with its lamp state, raw status and tty, then exits. |
| `"build/Nudge Lamp.app/Contents/MacOS/NudgeLamp" --render docs` | Writes one GIF per mood and a contact sheet of every animation. |

## Limits

Nudge Lamp tracks live Claude Code sessions only. Background sessions without a running process are left out. Tab switching and focus detection work with iTerm2 only. In other terminals the icon, banners and sounds still work, but clicking a session only brings iTerm2 forward.

With five sessions open, four of them working and iTerm2 in front, `top` reported 0.6% CPU and about 26 MB of memory for the app while the critter animated. Each `claude agents --json` run costs another 0.17 seconds of CPU. At the rate measured in the trigger test, about two runs a minute, that adds roughly 0.6% (inferred from those two measurements).

## Code layout

`Sources/NudgeLampCore` has no UI. It holds the `claude agents --json` reader, the session folder watcher, the process lookup and the state tracker, and the tests in `Tests/NudgeLampCoreTests` cover it. The critter's poses are defined in `Sources/NudgeLampCore/Critter.swift`, so the tests check them too. `Sources/NudgeLamp` is the menu bar app: the critter renderer, the menu, banners and the iTerm2 AppleScript.

## License

MIT. Nudge Lamp is an independent project. It is not affiliated with or endorsed by Anthropic. Claude Code is a product of Anthropic.
