# Keylight

Keylight gives Omarchy the familiar Apple MacBook keyboard-backlight behavior.

After 5 seconds without input, the light turns off. Start typing or move the pointer and Keylight restores the previous brightness. If you turn the light off yourself, it stays off.

The keyboard icon is green while the light is on and uses the normal bar color while it is off.

## Install

```sh
omarchy plugin add https://github.com/rogersmitha51/omarchy-keylight.git --enable
```

## Controls

- **Left click:** Cycle brightness
- **Scroll/swipe up:** Increase brightness
- **Scroll/swipe down:** Decrease brightness
- **Middle click:** Toggle on or off
- **Right click:** Turn off

## Settings

Change settings with `omarchy bar set io.github.rogersmitha51.keylight KEY VALUE`.

```sh
# Turn off after 30 seconds of inactivity
omarchy bar set io.github.rogersmitha51.keylight idleTimeout 30

# Disable automatic inactivity blanking
omarchy bar set io.github.rogersmitha51.keylight idleBlanking false

# Use a specific device from brightnessctl --list
omarchy bar set io.github.rogersmitha51.keylight device DEVICE_NAME

# Poll hardware brightness every 5 seconds
omarchy bar set io.github.rogersmitha51.keylight refreshInterval 5000
```

`idleTimeout` accepts 5–3600 seconds. `refreshInterval` accepts 500–60000 milliseconds. Leave `device` empty to select the first `*kbd_backlight*` device automatically.

## Compatibility

Keylight works with keyboard backlights exposed by Linux as a `*kbd_backlight*` device.

Check your hardware:

```sh
brightnessctl --list
```

`brightnessctl` is included with Omarchy. Keylight runs as your normal user and does not need root access.

## Remove

```sh
omarchy plugin remove io.github.rogersmitha51.keylight
```

## Development

```sh
omarchy plugin validate .
python3 -m unittest discover -s tests -v
```
