# Doubao Voice Toggle

A tiny macOS helper that lets `F8` toggle Doubao IME voice input without opening SuperCmd or pausing media.

## Behavior

First `F8` press:

- remembers the current input source
- remembers whether system output audio was muted
- mutes system output without pausing playback
- switches to Doubao IME
- taps right Option to start Doubao voice input

Second `F8` press:

- taps right Option to stop Doubao voice input
- waits briefly for text commit
- restores the previous input source
- restores the previous mute state

## Requirements

- macOS 13 or newer
- Swift toolchain
- Doubao IME installed at `/Library/Input Methods/DoubaoIme.app`
- Doubao input source ID: `com.bytedance.inputmethod.doubaoime.pinyin`
- Doubao voice shortcut configured as right Option

## Install

```sh
./scripts/install.sh
```

The installer builds release binaries, copies them to:

```text
~/Library/Application Support/DoubaoVoiceToggle/bin/
```

and loads a user LaunchAgent:

```text
~/Library/LaunchAgents/com.yuhanli.doubao-voice-toggle.plist
```

## Permissions

macOS may block the event tap and synthetic right Option event until permissions are granted.

Grant Input Monitoring and Accessibility permission to:

```text
~/Library/Application Support/DoubaoVoiceToggle/bin/doubao-voice-hotkey
~/Library/Application Support/DoubaoVoiceToggle/bin/doubao-voice-toggle
```

Then restart the LaunchAgent:

```sh
./scripts/restart.sh
```

To request the permission prompts explicitly:

```sh
./scripts/request-permissions.sh
```

Doubao itself owns microphone permission.

## Commands

```sh
swift run doubao-voice-toggle --status
swift run doubao-voice-toggle --reset
swift run doubao-voice-toggle --reset --muted false
```

Run the toggle once manually:

```sh
swift run doubao-voice-toggle
```

Run the hotkey listener in a terminal for permission debugging:

```sh
swift run doubao-voice-hotkey
```

## Uninstall

```sh
./scripts/uninstall.sh
```

Remove logs and state too:

```sh
./scripts/uninstall.sh --purge
```
