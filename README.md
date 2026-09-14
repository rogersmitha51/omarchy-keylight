# Keylight

Keylight gives keyboard backlights Apple-style inactivity behavior in Omarchy. It turns a lit keyboard off after the configured idle period and restores the exact previous level on the next keyboard, pointer, or touchpad activity. Manual off remains off.

The plugin works with any keyboard backlight exposed by Linux under `/sys/class/leds/` with `kbd_backlight` in its device name.

## Requirements

- Omarchy Quattro with shell plugins
- `brightnessctl` (included with Omarchy)
- A compatible keyboard-backlight LED device

Keylight uses Quickshell's Wayland `IdleMonitor`; it does not read raw input devices, run another Quickshell process, request elevated privileges, or access the network.

## Install

```sh
omarchy plugin add https://github.com/rogersmitha51/omarchy-keylight.git --enable
```

## Controls

| Input | Action |
|---|---|
| Left click | Cycle brightness and off |
| Scroll | Increase or decrease brightness |
| Middle click | Toggle off or restore the last manual level |
| Right click | Turn off and keep it off |

By default, Keylight turns off a lit keyboard after five seconds without user input. Activity restores it only when Keylight performed the automatic shutdown.

## Configure

```sh
omarchy bar set io.github.rogersmitha51.keylight idleBlanking true
omarchy bar set io.github.rogersmitha51.keylight idleTimeout 5
omarchy bar set io.github.rogersmitha51.keylight device kbd_backlight
```

The device setting is optional. With no explicit device, Keylight selects the first `*kbd_backlight*` device.

## State and permissions

Keylight writes only through `brightnessctl` with normal user permissions. Its remembered manual and same-boot idle state is stored in:

```text
${XDG_STATE_HOME:-~/.local/state}/keylight/
```

The directory and files are restricted to the current user. Automatic restoration markers include the kernel boot ID and are ignored after reboot.

## Development

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Service.qml BarWidget.qml
python3 -m unittest discover -s tests -v
```

## Remove

```sh
omarchy plugin remove io.github.rogersmitha51.keylight
```
