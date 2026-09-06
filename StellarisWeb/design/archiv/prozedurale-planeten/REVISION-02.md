# Revision 02 — Landschaft zuerst

Nutzerfeedback: zu viel Text; Planeten müssen prozedural entstehen und unterschiedlich aussehen. `procedural-mockup.html` ersetzt den ersten Entwurf als aktuelle Gesprächsvorschau. Weiterhin ausschließlich Mockup im selben Worktree.

- Karte dominiert. Keine Textseitenleiste, keine dauerhaft sichtbaren Regionsnamen, keine separate Bevölkerungsseite. Symbole und belegte Jobs stehen direkt an Siedlungen.
- Drei Weltprofile mit unterschiedlichen Seeds, Geländefrequenzen, Meeresspiegeln, Biomen, Kratern und regionalen Merkmalen. „Weitere Welt“ generiert wirklich neue Geometrie des ausgewählten Typs, nicht nur andere Farben.
- Deterministisches Value-Noise mit Domain-Warp und mehreren Frequenzen erzeugt Höhen. Relief, Küsten und Vegetation folgen daraus. Vulkanwelten erhalten zusätzliche prozedurale Krater.
- Bauorte werden auf geeignetem Land mit Abstandssampling gewählt; ihre Voronoi-Einzugsgebiete werden an Landflächen beschnitten. Bauplätze und Vorkommen werden aus Weltprofil, Höhen und Seed abgeleitet.
- Pop-Demo: 18 Pops werden automatisch auf Distriktjobs verteilt. Jeder Distrikt bietet 2 Jobs, unbesetzte Jobs produzieren nichts. Platzieren und Entfernen aktualisiert Erträge und sichtbare Siedlungsgrundrisse.

Noch keine echte Planeten-/Kolonieintegration, Baugeld, Bauzeit, Versorgung oder KI. Regionengeometrie ist für die Vorschau: bei späterer Umsetzung zusammenhängende geologische Regionen statt möglicherweise unverbundener Voronoi-Inseln und eine nahtlose planetare Projektion verwenden. Pop-Verteilung der Demo folgt deterministisch der Regionsreihenfolge, noch keinem Gouverneurmodell. Generierte Merkmalsboni sind Beispielwerte.
