# Planetenmenü — abstrakte Sektoren

Aktueller Alternativentwurf nach Archivierung der naturalistischen Landschaft. Stand 06.09.2026; nur Mockup, keine Spielintegration.

## Tatsächlich betrachtete Referenzen

- Gespeicherte Ansichten: `artifacts/galaxy-refined.png`, `artifacts/system-final.png` aus dem Hauptprojekt. Sie zeigen die bestehende visuelle Sprache, sind aber ältere Screenshots.
- Aktuelle Quellen: `src/GalaxyMap.tsx`, `src/SystemView.tsx`, `src/system-view.css`, `src/styles.css`, `src/system-shaders.ts`.
- Der aktuelle Planetenshader beschreibt ausdrücklich sparsame leuchtende Breitengradkonturen statt fotografischer Oberflächen. Der neue Mockup übersetzt seine Grundbeleuchtung und Randaufhellung in Canvas.

## Neues Menü

Eine dritte Zoomstufe nach Galaxie und System: dunkler Raum, eine ruhige Planetenkugel, abstrakte Sektoren auf ihrer Oberfläche. Dünne violette Grenzen markieren die Verwaltung. Kreise zeigen Siedlungen, Symbole den Hauptdistrikt, kleine Brüche die tatsächlich besetzten Jobs. Nur die Auswahl erhält einen Namen auf der Kugel.

Rechts steht ein kompakter Inspektor im Stil der Systemansicht: Merkmal, zwei bis drei Distriktplätze, Pop-Belegung und Bauen. Die Bevölkerung lässt sich im gleichen Inspektor anzeigen. Keine Landschaftstexturen, Erzähltexte oder große Verwaltungsseite.

## Prozedurale Unterschiede

Seed und Planetentyp bestimmen Anzahl, Positionen, Merkmale und Baukapazität der Sektoren. Erde, Ares und Neris unterscheiden sich in Kugelfarbe und Sektoraufteilung. Über die optionalen Designregler kann man weitere Seed-Varianten ansehen. Die Kugel bleibt als visuelles Bindeglied erhalten.

Für diesen Mockup liegen alle auswählbaren Sektoren auf der sichtbaren Halbkugel. Das ist eine Verwaltungsprojektion, noch kein geografisch vollständiges Kugelmodell. Bei Umsetzung entscheiden: bewusst abstrakte Projektion beibehalten oder vollständige Kugel mit Rotation und Auswahlhilfen.

## Pop-Demo und Grenzen

18 Pops werden automatisch auf Distriktjobs verteilt. Ein leerer Job produziert nichts. Gebäudeunterhalt und Merkmalsbonus sind als Beispielwerte enthalten. Forschungspriorität zieht bei Arbeitskräftemangel Pops in Labore. Habitatjobs repräsentieren Versorgung, erzeugen in dieser Vorschau aber nur Wohnraum; echte Versorgung, Spezieseignung, Wachstum, Baukosten, Wartezeiten, KI und Backend fehlen bewusst.

`abstract-planet.html` ist der bearbeitbare, interaktive Quelltext. Die archivierte prozedurale Landschaft bleibt unverändert im Hauptprojekt unter `design/archiv/prozedurale-planeten` erhalten.
