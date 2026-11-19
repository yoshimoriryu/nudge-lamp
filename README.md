# Agent Lamp

Agent Lamp is a macOS menu bar app that shows whether your Claude Code sessions are working, waiting for you, or idle. I built it because I kept switching to a browser while an agent ran, and only noticed much later that it had stopped on a permission prompt.

## What the icon means

| Icon | Color | Meaning |
| --- | --- | --- |
| Exclamation mark | Red | A session stopped mid-turn on a permission prompt, a question or another dialog. |
| Check mark | Orange | A session finished its turn and you have not looked at it yet. |
| Half circle, animated | Green | A session is running a turn or a shell command. |
| Empty ring | Grey | Nothing is running and nothing is waiting. |

The most urgent session decides the icon. A number next to the icon counts the sessions that need you. The menu lists every session with its state, how long it has been in that state, and its folder.

## How it works

Claude Code writes one JSON file per running session to `~/.claude/sessions/<pid>.json`. The file holds a `status` field (`busy`, `shell`, `idle` or `waiting`), a `waitingFor` reason, and the time of the last change. Agent Lamp reads these files once a second. It checks each PID against the process table, so it ignores files left behind by a crashed session.

Claude Code reports `idle` both for a turn that ended a minute ago and for a session nobody has touched since yesterday. Agent Lamp tells them apart by remembering whether it saw the session working since you last looked at it. A finished session turns grey again when you focus its iTerm2 tab, click it in the menu, or choose Mark All as Seen.

When a session starts waiting for you, Agent Lamp waits 1.5 seconds to skip short flickers. Then it plays a sound and posts a banner. It stays quiet when that session's iTerm2 tab is already in front of you. Clicking a banner or a menu row brings the session's iTerm2 window, tab and split pane to the front. Agent Lamp finds the tab by matching the session's terminal device (tty) against each iTerm2 session.

The session file format is internal to Claude Code and not documented. I read it from Claude Code 2.1.328 in November 2026. A later release could rename the fields, and the lamp would then show every session as idle. Run `AgentLamp --print` to see what the app reads.

## Install

You need macOS 15 or later and Swift 6 from Xcode or the Xcode command line tools.

```sh
git clone https://github.com/yoshimoriryu/agent-lamp.git
cd agent-lamp
make install
```

`make install` builds `Agent Lamp.app`, copies it to `~/Applications` and opens it. Choose Open at Login in the menu to start it with your Mac.

On first launch macOS asks two questions. Allow notifications to get banners. Allow Agent Lamp to control iTerm2 so it can tell which tab is in front and switch tabs for you. The app has an ad hoc signature, so macOS asks about iTerm2 again after each rebuild.

## Commands

| Command | What it does |
| --- | --- |
| `make test` | Runs the unit tests for the state logic. |
| `make run` | Builds the app and opens it from `build/` without installing it. |
| `make uninstall` | Quits the app and removes it from `~/Applications`. |
| `"build/Agent Lamp.app/Contents/MacOS/AgentLamp" --print` | Prints every session with its lamp state, raw status and tty, then exits. |

## Limits

Agent Lamp tracks Claude Code sessions only. Tab switching and focus detection work with iTerm2 only. In other terminals the icon, banners and sounds still work, but clicking a session only brings iTerm2 forward.

With four sessions open on my Mac, `ps` reported 0.1% CPU and about 70 MB of memory for the app.

## Code layout

`Sources/AgentLampCore` has no UI. It holds the session file reader, the process lookup and the state tracker, and the tests in `Tests/AgentLampCoreTests` cover it. `Sources/AgentLamp` is the menu bar app: icon, menu, banners and the iTerm2 AppleScript.

## License

MIT
