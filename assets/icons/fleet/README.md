# Fleet Icons

Abstrakte SVG-Icons zur Flotten-Auswahl. Einheitliche Design-Sprache: dunkle Scheibe,
rollenspezifische Glyphe + Farbe, Power-Level als gefüllte Rauten (1–3 von 3 Slots)
am unteren Rand plus zunehmender Ringstärke.

## Namensschema

`fleet_<rolle>_p<level>.svg` — Level 1 (schwach) bis 3 (stark).

## Rollen

| Rolle | Glyphe | Farbe | Passende `ai_role` |
|---|---|---|---|
| `attack` | Pfeilspitze / Delta | Rot `#e85050` | `combat_patrol` |
| `guard` | Schild | Blau `#4f8fe6` | `system_guard` |
| `raider` | Krallenhiebe | Orange `#ff8c3a` | `raider` |
| `scout` | Radar-Wellen | Cyan `#3fd2c7` | `science_scout` |
| `construction` | Sechskantmutter | Gelb `#f2c14e` | `construction` |
| `transport` | Verschnürte Frachtkiste | Grün `#62c462` | (Reserve, z. B. Logistik/Kolonie) |
| `anomaly` | Geglitchter Ring mit versetztem Segment + entweichendem Partikel | Violett `#b25ce6` | (Anomalie-Untersuchung / mysteriöse Flotten) |
| `void` | Schwarzes Loch (schwarzer Kern, Akkretionsring, Verzerrungsbögen) | Blasses Indigo `#a9b4ff` | (Void-Kreaturen / Leere) |
| `flak` | Geschützturm mit drei Flak-Detonationen | Stahlgrau `#9db4c9` | (Flak-/Point-Defense-Schiffe) |

## Attack-Spezialstufen (jenseits p3)

Für „über der Skala"-Flotten gibt es eine eigene Eskalations-Sprache: Doppelring
(dicker Außenring + dünner Innenring), weißglühender Akzent `#ffd9cc` und bei den
Superwaffen ein zentraler Stern statt der Power-Rauten („off the scale").

| Datei | Glyphe | Bedeutung |
|---|---|---|
| `fleet_attack_elite.svg` | Drei gestaffelte Deltas, oberstes weißglühend; 3/3 Rauten + Doppelring | Elite-Kampfflotte, Stufe 4 |
| `fleet_attack_super.svg` | Strahl spaltet einen Planeten (Planet Cracker); Stern-Pip | Superwaffe |
| `fleet_attack_apex.svg` | Delta mit weißglühendem Kern und Strahlenkranz; Stern-Pip | Apex — stärkste Ausbaustufe |

## Sonder-Icons

| Datei | Glyphe | Bedeutung |
|---|---|---|
| `fleet_main.svg` | Großes weißes Delta, flankiert von zwei gedimmten Eskorten-Deltas; goldener Stern-Pip + Doppelring, Weiß/Platin `#f2f5fa` | Die Hauptflotte (einmalig, daher ohne Power-Stufen) |

## Technische Hinweise

- viewBox `0 0 64 64`, nur einfache Pfade/Kreise/Rechtecke — kompatibel mit dem
  Godot-SVG-Import (ThorVG), keine Filter oder Gradienten.
- Hintergrundscheibe `#0d1520`, leere Power-Slots `#3a4a60`.
- Neue Rollen: Template kopieren, Glyphe im Bereich y 10–44 zentriert um (32, 27)
  halten, Power-Rauten bei x = 21/32/43, y = 47 nicht verändern.
