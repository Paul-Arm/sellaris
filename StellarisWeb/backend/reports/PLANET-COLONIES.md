# Mehrere Kolonien im System

Eigene untersuchte Systeme können mehrere besiedelte Planeten haben. Im Kontextmenü eines unbesiedelten Nebenplaneten startet „Planeten besiedeln“ einen Auftrag für ein Kolonieschiff. Der Auftrag lässt sich an bestehende Flugbefehle anhängen. Das Schiff fliegt den bewegten Planeten an; erst innerhalb der Baureichweite werden 80 Energie und 80 Mineralien gebucht. Die Gründung dauert zwölf Spieltage und verbraucht das Kolonieschiff.

Jede zusätzliche Welt hat eigene Pops und Speziesgruppen, erzeugte Sektoren, Distrikte, Schwerpunkt, Wachstum und einen unabhängigen Bauauftrag. Orbitalanlagen können daneben weiter betrieben werden. Aktive Schildbastionen tragen zur gemeinsamen Systemverteidigung und Schiffsreparatur bei. Die Hauptkolonie bleibt Sitz der Raumwerft und des Systembesitzes. Für das Siegziel zählen weiterhin acht Systeme, nicht acht Planeten im selben System. Monde ohne bewohnbare Klimaklasse bleiben Anlagenplätze.

## Persistenz und Regeln

- `game_planet_colony` adressiert eine zusätzliche Welt über die dauerhafte Objekt-ID. Bauaufträge referenzieren diese ID; Befehle enthalten System und unveränderlichen Körperplatz. Revisionen schützen die unabhängigen Koloniezustände.
- Die private Sicht `my_planet_colonies` liefert nur eigene Bevölkerung und Infrastruktur. Sie verbindet die Welt mit dem aktuellen Körpernamen und Klima, auch wenn ihre Systemdetails gerade nicht geöffnet sind.
- Produktion und Wachstum verwenden dieselben Kolonieregeln wie die Hauptwelt. Jede Gründung setzt eigene Zeitanker; Terraforming, Regierungsreformen, Forschung und Sternkollaps rechnen zuvor den alten Zustand ab.
- Speziesmodifikation kann einzelne Nebenwelten auswählen. Das Wirtschaftsfenster und die Reichsbevölkerung berücksichtigen alle eigenen Welten. Die KI kann Nebenwelten besiedeln und entwickeln.
- Abbruch der bezahlten Gründung erstattet die Gründungskosten einmalig. Abbruch eines planetaren Ausbaus erstattet 50 %. Ungültig gewordene Anflüge werden übersprungen. Systemverlust entfernt dessen Kolonien und beendet ihre Ausbauaufträge; eine spätere Neubesiedlung beginnt neu.
- Keine Migration alter Galaxien oder eingefrorene Generatorfassung. Die neue Tabelle ergänzt das aktive Spielmodell.

## Nachweise

`backend/tests/planet-colonies.test.ts` verwendet eine eigene temporäre SpacetimeDB-Partie mit zwei Identitäten. Geprüft werden Besitz und private Sichtbarkeit, tatsächlicher Anflug, Pause, Kosten und Erstattung, Verbrauch des Schiffs, paralleler Ausbau auf zwei Welten, veraltete Revisionen, gezielter Bauabbruch, Wiederverbindung, reale Erträge, Terraforming, Umbenennung, Speziesmodifikation, Bastionen und Systemverlust.

Browserprüfung in der separaten Testpartie `82AD0D`: Rechtsklick auf den Nebenplaneten, Anflug, Gründung, Kontextmenü „Kolonie verwalten“, Distriktbau und Wechsel zur unveränderten Hauptkolonie. Keine Konsolenfehler. Der Nutzersektor `5C69F4` wurde für diese Prüfungen nicht bespielt.
