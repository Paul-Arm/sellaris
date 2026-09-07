# Erste Megastruktur: Dyson-Anlage

Stand: 7. September 2026.

Forschung „Megakonstruktion“ kostet 500 Forschung und benötigt 100 Spieltage vor Reichsmodifikatoren. Danach kann der Spieler an einem eigenen untersuchten Hauptreihenstern oder Riesen eine Dyson-Anlage planen. Schwarze Löcher, Neutronensterne, Planeten und gewöhnliche Raumstationen sind keine gültigen Bauziele.

Der Einstieg erfolgt per Rechtsklick am Stern oder über dessen Detailansicht. Ein eigenes Schiff übernimmt den Bauauftrag in seiner Warteschlange und fliegt zum Stern. Erst innerhalb der serverseitig geprüften Baureichweite entstehen Baustelle und Kosten. Der Ausbau verwendet dieselbe Anflugregel.

| Etappe | Energie | Mineralien | Spieltage | Gesamtertrag Energie / 4 Tage |
| --- | ---: | ---: | ---: | ---: |
| Orbitalgerüst | 300 | 500 | 60 | 0 |
| Kollektorschwarm | 800 | 1.200 | 100 | 30 |
| Vollständiger Dyson-Schwarm | 1.600 | 2.400 | 160 | 90 |

Die Anlage ist ein eigenes persistentes Systemobjekt mit Elternbezug zum Stern und einer normalen dauerhaften Anlagenzeile. Der Anlagenplatz des Sterns bleibt zusätzlich nutzbar. Ein Stern erlaubt eine Dyson-Anlage. Ein Ausbau behält Objekt-ID und bisherigen Ertrag; Kosten und Ertrag sind bewusst nicht linear je Stufe. Die Resonanzkrise beeinflusst die tatsächliche Produktion wie bei anderen Orbitalanlagen.

Abbruch erstattet einmalig 50 Prozent der aktuellen Baukosten. Beim ersten Gerüst entfernt er die Baustelle; entfernte Objekt-IDs werden nicht wiederverwendet. Bei späteren Etappen bleibt die vorherige Ausbaustufe erhalten. Am Bauende werden Besitz und aktiver geeigneter Elternstern erneut geprüft. Regeln für Sternzerstörung und deren Folgen auf bereits fertige Anlagen sind ein späterer Ausbauschritt.

Die Szene zeigt zunächst ein Baugerüst, anschließend einen Kollektorschwarm in zwei Größen. Das Objekt erzeugt keine zusätzliche Gravitationsmulde. Die neue Planetenverwaltung mit Sektoren und Pops bleibt eigenständig.

## Prüfung

- `npm test`: 129 Regeltests bestanden, einschließlich Sternvoraussetzungen, Anlagenzuordnung, Etappenkosten, Erträgen und Modellgrößen.
- `npm run backend:build` und `npm run build`: erfolgreich.
- `backend/tests/megastructures.test.ts`: echte SpacetimeDB-Partie mit Forschung, unzulässigen Zielen und fremden Spielern, paralleler Sternenbasis, allen drei Etappen, Baustellenabbruch, Ausbauabbruch mit Erstattung, Wiederverbindung nach jeder Etappe, stabilen IDs, Maximalstufe und tatsächlich gebuchter Energie. Krisenabschläge werden berücksichtigt.
- Bestehende native Tests für Navigation und Anlagenbau bestanden: Flugketten, Erkundungsanflüge, freie Stationen, Produktionsbuchungen, Ausbau und Erstattung.
- Browserprüfung in einer isolierten neuen Partie: Forschung, Rechtsklick am Stern, Planungsansicht, gespeicherte Baustelle und Abschluss des Orbitalgerüsts. Die nächste Etappe bleibt bei Rohstoffmangel gesperrt. Die neue Planetenverwaltung ist weiterhin erreichbar; keine Browserwarnungen oder -fehler. Alle drei Etappen werden zusätzlich durch den nativen Integrationstest geprüft.

Der nachfolgende [kontrollierte Sternkollaps](STELLAR-PROJECTS.md) ergänzt die erste Sternveränderung und den Verbrauch fertiger Dyson-Anlagen. Weitere Megastrukturarten, mehrere Hauptkolonien je System und eine eigene strategische Megastrukturplanung der KI sind noch offen. Für diese Etappe wurde keine Migration und kein Kompatibilitätspfad ergänzt.
