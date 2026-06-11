# Army Icons

Teil der Icon-Familie (siehe `assets/icons/fleet/README.md` für die gemeinsame
Design-Sprache). Armeen sind am **Wappenschild-Rahmen** erkennbar
(Flotte = Kreis, Station = Sechseck, Planet = neutraler Kreis, Armee = Schild).
Power-Level wie gewohnt: 1–3 gefüllte Rauten von 3 Slots plus zunehmende
Rahmenstärke.

## Namensschema

`army_<typ>_p<level>.svg` — Level 1 (schwach) bis 3 (stark).

## Typen

| Typ | Glyphe | Farbe | Bedeutung |
|---|---|---|---|
| `infantry` | Drei Rang-Chevrons | Oliv `#9aa84f` | Standard-Sturmtruppen |
| `garrison` | Bunker (Kuppel mit Sehschlitz auf Sockel) | Schieferblau `#7287b8` | Verteidigungsarmee / Garnison |
| `armor` | Panzer (Wanne, Turm, Rohr, Kette) | Khaki `#c2a35c` | Gepanzerte Verbände |
| `artillery` | Angewinkeltes Rohr, Flugbahn, Einschlagstern | Orangebraun `#e0793d` | Artillerie / Belagerung |
| `mech` | Kampfläufer (Torso, Visier, Schulterwaffen, Beine) | Himbeerrot `#d84a6a` | Schwere Mechs / Elite |

## Technische Hinweise

- Schild-Rahmen: `M9 8 H55 V36 C55 49 45 57 32 61 C19 57 9 49 9 36 Z`,
  Rahmenstärke 1.5 / 2.5 / 3.5 je Power-Level.
- Glyphenbereich y 12–44, Power-Rauten bei x = 21/32/43, y = 47 (wie überall).
