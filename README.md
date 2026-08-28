# Power settings

Omarchy Quattro bar plugin for idle and power-profile settings, with separate policies when plugged in vs on battery.

Plugin id: `io.github.rustyoz.power-idle`

It sits beside the built-in Power panel (`omarchy.power`). It does not replace it.

## Install

```sh
omarchy plugin add https://github.com/rustyoz/omarchy-power-idle.git --enable
```

The widget lands in the right side of the bar. Move it with:

```sh
omarchy bar move io.github.rustyoz.power-idle --section right
```

## Usage

Click the bar icon to open the panel.

- **Stay awake** — same switch as `Super + Ctrl + I` (`omarchy toggle idle`). While on, screensaver, screen-off, lock, and suspend are skipped.
- **Plugged in / On battery** — each column has a power profile plus timeouts for screensaver, turn off screen, lock, and suspend (`Never` or 1–60 minutes).
- Escape closes the panel.

Saving a timeout writes `~/.config/omarchy/power-idle.json`. The plugin then copies the *active source* screensaver and lock values into `~/.config/omarchy/shell.json` `idle` so first-party `omarchy.idle` still runs those two. Turn-off-screen (`hyprctl dispatch dpms off`) and suspend (`systemctl suspend`) are handled by this plugin’s service, because stock idle does not.

Desktop machines without a battery show a single column.

## Remove

```sh
omarchy plugin remove io.github.rustyoz.power-idle
```

Removal disables the plugin and deletes the checkout. It does not revert `shell.json` idle values or delete `~/.config/omarchy/power-idle.json`. Remove that file yourself if you want a clean slate:

```sh
rm -f ~/.config/omarchy/power-idle.json
```

## External commands

Used only when you change a setting or when an idle timeout you chose fires:

- `omarchy toggle idle`
- `omarchy-powerprofiles-set` (falls back to `omarchy powerprofiles set`)
- `omarchy-powerprofiles-list`
- `omarchy-shell shell reloadConfig`
- `hyprctl dispatch dpms off|on`
- `omarchy-system-wake`
- `systemctl suspend`

No installer, no sudo, no network.

## Develop on Omarchy

```sh
plugin_id=io.github.rustyoz.power-idle
mkdir -p ~/.config/omarchy/plugins
ln -s "$PWD" ~/.config/omarchy/plugins/$plugin_id
omarchy plugin validate "$PWD"
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Service.qml
omarchy-shell shell rescanPlugins
omarchy plugin enable "$plugin_id"
```

## License

MIT. See [LICENSE](LICENSE).
