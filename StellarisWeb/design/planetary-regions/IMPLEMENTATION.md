# Planetenverwaltung – integriert

Stand: 6. September 2026. Entwicklung im Worktree `.worktrees/planetary-regions`, Branch `codex/planetary-regions-mockups`.

Die freigegebene abstrakte Ansicht ist jetzt echte Spieloberfläche. Einstieg über **Kolonien** oder **Kolonie verwalten** am Heimatplaneten. Sie übernimmt dunkle Flächen, dezente Konturlinien und die Licht-/Randfarben der Systemansicht.

- Jede Kolonie erhält dauerhaft gespeicherte Sektoren aus Galaxie, System und Planetenslot. Lage, Anzahl, Bauplätze und Standortboni unterscheiden sich; Neuladen und Terraforming würfeln die Geografie nicht neu.
- Habitat, Biosphäre, Kraftwerk, Förderdistrikt, Forschungscampus und Schildbastion sind platzierbar, bis Stufe 3 ausbaubar, stilllegbar und abreißbar.
- Pops besetzen reale Arbeitsplätze. Versorgung hat Vorrang, danach Wachposten und der gewählte Wirtschaftsschwerpunkt. Leere Arbeitsplätze produzieren nichts. Aktive Distrikte kosten Unterhalt.
- Wohnraum und Versorgung begrenzen Wachstum. Spezies, Bewohnbarkeit, Reichsmodifikatoren, Technologie und Krisen fließen in die Wirtschaft ein.
- Ein Bauauftrag pro Kolonie; echte Kosten und Spieltage, Baugeschwindigkeit des Reichs, Pause und 50-%-Erstattung bei Abbruch. Eigentum und Revisionsnummer werden serverseitig geprüft.
- Bevölkerung, Sektoren und Bauaufträge werden in SpacetimeDB gespeichert; Wiederverbindungen rekonstruieren denselben Zustand. Die KI nutzt dieselben Regeln.

Die jetzige Spielstruktur bleibt eine Hauptkolonie pro Sternsystem (Planetenslot 1). Weitere Körper nutzen die bestehende orbitale Anlagenverwaltung. Die Kugel zeigt eine administrative Projektion aller Sektoren auf die sichtbare Halbkugel.

**Neue Partien erforderlich.** Das frühere Kolonieschema wird nicht migriert. Reichs- und Speziesvorlagen bleiben eigenständig.

## Dateien

- `src/ColonyManager.tsx`, `src/PlanetSurface.tsx`, `src/planet-manager.css`: Bedienung und abstrakte Oberfläche.
- `shared/planetaryEconomy.ts`, Export über `shared/colonies.ts`: Generator, Pops, Wirtschaft und Befehle.
- `spacetimedb/src/game-*.ts`: echte Produktion, Wachstum, Bauaufträge und KI.
- `abstract-planet.html`: freigegebener interaktiver Entwurf vor der Implementierung.

## Prüfung

TypeScript für Frontend und Backend, Produktionsbuild, gesamte lokale Testsuite sowie echte Backend-Tests für Kolonien, Spielabläufe, KI, orbitale Anlagen, Terraforming und Ereignisse. Im Browser: Gründung, Sektorauswahl, Baukosten, pausierter Bau, Fertigstellung, Pop-/Jobanzeige und Schwerpunktwechsel; Ansicht bei 1280 × 720 und 390 × 844 geprüft, keine Browserfehler. Die große Canvas-Oberfläche zeichnet bei laufenden Wirtschaftsaktualisierungen nicht neu.
