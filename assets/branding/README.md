# Branding: FlightSim Aide

The icon is the **Flight Director** mark: a white aircraft symbol under magenta command bars on navy. It was designed for this project and is covered by the repository's MIT licence (see `THIRD_PARTY_NOTICES.md`).

## Palette

| Hex | Role |
|---|---|
| `#0E2338` | Night navy. Icon ground on dark; aircraft symbol and text on light |
| `#E845B8` | Guidance magenta, command bars on dark |
| `#C0219A` | Guidance magenta, deepened for light grounds |
| `#F4F8FB` | Neutral. Aircraft symbol and text on dark |
| `#EDF2F6` | Paper. Icon ground on light |

Magenta and cyan are avionics colours, kept apart from the app's red, amber and green status colours.

## Files

- `svg/icon_master_dark.svg`, `svg/icon_master_light.svg`: the mark only, on a 1024 grid.
- `svg/icon_small_dark.svg`, `svg/icon_small_light.svg`: thicker bars and a wider gap, for 16 to 48 px.
- `svg/icon_foreground.svg`: the mark on a transparent ground, scaled to 80 percent about the centre, for the Android adaptive icon (the navy background comes from `pubspec.yaml`).
- `svg/icon_with_text_dark.svg`, `svg/icon_with_text_light.svg`: **draft** logo with text under the mark. The text still reads "FS Aide", not the product name "FlightSim Aide", and it is live `<text>` (a font without weight 300 shows regular). Redraw the wording and convert the text to outlines before using it in a store listing or on the website.
- `icon.png` (1024 x 1024, RGB, no alpha, as the App Store requires), `icon_foreground.png` (1024 x 1024, RGBA) and `icon_small.png`: the PNGs rendered from the SVGs above. They are the inputs of the launcher-icon tool.

## Changing the icon

Edit the SVGs, render them to 1024 x 1024 PNGs (a browser, Inkscape or any SVG tool), replace `icon.png` and `icon_foreground.png`, and run:

```
dart run flutter_launcher_icons
```

The settings are in the `flutter_launcher_icons:` block of `pubspec.yaml`. It writes the Android, iOS, Windows and macOS icons.
