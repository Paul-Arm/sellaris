# Station Icons

Teil der Icon-Familie (siehe `assets/icons/fleet/README.md` für die gemeinsame
Design-Sprache). Stationen sind am **Sechseck-Rahmen** erkennbar (Flotten = Kreis,
Planeten = Kreis mit neutralem Ring). Power-Level wie bei den Flotten: 1–3 gefüllte
Rauten von 3 Slots plus zunehmende Rahmenstärke.

## Namensschema

`station_<typ>_p<level>.svg` — Level 1 (Basis) bis 3 (Endausbau).

## Typen

| Typ | Glyphe | Farbe | Passender Build-Tag / Klasse |
|---|---|---|---|
| `orbital` | Ring mit Kern und vier Andockspeichen | Hellblau `#7ec8e3` | `orbital_station` / Basic Station |
| `stellar` | Sonne mit Strahlenkranz und angedockter Stations-Raute | Solar-Gold `#f5a623` | `stellar_station` / Stellar Station |
| `mining` | Asteroid mit Abbau-Kerbe und hellen Erz-Adern | Bronze `#c98847` | `mining_station` / Sammelstation |
| `research` | Atom (drei Orbitale, Kern, heller Elektron-Punkt) | Mint `#56d6a9` | `research_station` |
| `shipyard` | Schiffs-Delta zwischen zwei Baugerüst-Klammern | Magenta `#e873b0` | `shipyard`-Tag |

## Technische Hinweise

- Sechseck-Rahmen: `M32 3 L57.1 17.5 V46.5 L32 61 L6.9 46.5 V17.5 Z`,
  Rahmenstärke 1.5 / 2.5 / 3.5 je Power-Level.
- Glyphenbereich und Power-Rauten identisch zu den Flotten-Icons
  (Glyphe y 10–44 um (32, 27), Rauten bei x = 21/32/43, y = 47).
