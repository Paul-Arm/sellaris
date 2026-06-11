# Planet Icons

Teil der Icon-Familie (siehe `assets/icons/fleet/README.md` für die gemeinsame
Design-Sprache). Planeten haben **keinen farbigen Rahmen und keine Power-Rauten** —
der Ring ist neutral grau (`#3a4a60`), die Identität kommt von der zentralen
Planetenkugel selbst. So sind sie auf einen Blick von Flotten (farbiger Kreisring)
und Stationen (Sechseck) unterscheidbar.

## Namensschema

`planet_<kind>.svg` — die Kinds entsprechen den `planet_visual.kind`-Werten
aus den Celestial-Visual-Tests.

## Typen

| Kind | Darstellung |
|---|---|
| `landmass` | Blauer Ozean mit grünen Kontinent-Blobs (kontinental/terran) |
| `dry_terran` | Sandfarbene Kugel mit dunklen Dünen-Bändern (Wüste) |
| `no_atmosphere` | Graue Kugel mit Kratern (Barren) |
| `ice_world` | Helle Eiskugel mit blauen Rissen |
| `lava_world` | Dunkles Gestein mit glühenden Lava-Adern |
| `gas_planet` | Gebänderte Gaskugel mit Saturn-Ring (rotierte Ellipse) |
| `asteroid_belt` | Diagonal verstreute Gesteinsbrocken (kein Planet, aber scanbarer Körper) |

## Technische Hinweise

- Planetenkugel: r = 16 zentriert auf (32, 32) — größer als Flotten-Glyphen,
  da keine Power-Rauten Platz brauchen. Gasplanet: r = 13 wegen des Rings.
- Der Saturn-Ring nutzt `transform="rotate(...)"` — wird vom Godot-SVG-Import
  (ThorVG) unterstützt.
