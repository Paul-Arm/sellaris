# Bereinigung alter Daten- und API-Pfade

Die Laufzeit akzeptiert ausschließlich die aktuellen Modelle. Entfernt sind:

- `visible_battles`, `battle_participants` und der alte Detailmodus in Lastclients. Alle Verbraucher verwenden `focused_battle`, `battle_roster`, `battle_motion` und `battle_vitals`; Übersichten lesen `visible_battle_summaries`.
- Nachrüst-Reducer und Hilfsskripte für Kampfberichte, Diplomatie und Ereignisse. Berichte entstehen vollständig bei Gefechtsbeginn; es gibt keine ungezeichneten historischen Berichte oder nachträgliche Rekonstruktion.
- Die alte Millitag-Kodierung für Fristen. Gespeicherte Deadline-Indizes verwenden ganze Spieltage.
- Automatische Flaggen- und Schiffsdesign-Ergänzungen in Vorlagen und Projektionen. Fabriken erzeugen vollständige aktuelle Daten; unvollständige Eingaben werden abgewiesen.
- Das doppelte Emblemfeld in Reichsvorlagen; die vollständige Flagge ist die einzige Quelle.
- Alte Produktionsfelder und feste Ressourcenlisten im Admin-Panel. Abfrage, Transport, Anzeige und Buchungen verwenden den Ressourcenkatalog und monatliche Produktion.
- Die nachträgliche Sternklassen-Umschreibung anhand alter Atlas-IDs. Der Generator legt die Klasse fest, Darstellung und Systemobjekte lesen den gespeicherten Wert.
- Der separate `legacy.*`-Regelkatalog. Reichs- und Speziesregeln verwenden denselben Kernkatalog wie die anderen Regelquellen, einschließlich des Unterhaltseffekts von „Verschwenderisch“.
- Fehlende Status-/Galaxieparameter im gespeicherten Gatewayregister werden nicht mehr ergänzt. Der Idempotenzschlüssel für Neuanlagen heißt `creationKey`.

Drei gespeicherten Reichsvorlagen wurde ihre bisherige automatisch angezeigte Flagge einmal ausdrücklich hinzugefügt. Individuelle Vorlagen und Spezies wurden nicht gelöscht. Dieser einmalige Datenabgleich ist kein verbleibender Lade- oder Migrationspfad.

Aktuelle Neuanlagen, Wiederverbindungen, idempotente Gründung und Wiederherstellung nach Prozessneustart bleiben reguläre Funktionen. Browserfähigkeitsprüfungen, WebGL-Ausweichdarstellung, neutrale Stationsmodelle und automatische Ereignisentscheidungen sind keine Unterstützung alter Spielstände. Historische Messberichte bleiben als solche erhalten; neue Netzwerkvergleiche schreiben `NETWORK-CURRENT.md`.

## Prüfung

- 160 Unit-Tests bestanden. Frontend-Build, Backend-Build inklusive neu erzeugter Bindings und beide TypeScript-Prüfungen erfolgreich.
- Der vollständige native Lauf umfasst 39 Tests. Vier zunächst fehlgeschlagene Fälle wurden korrigiert und erfolgreich erneut geprüft: Monatsabschluss vor Erstattungsvergleich, monatliche Forschungsdauer in KI-/Dyson-Testdaten sowie die verbliebene alte Admin-Abfrage. Alle 39 Fälle sind damit abgedeckt, einschließlich Serverneustart und Wiederverbindung.
- Die lokale Vorlagenbibliothek lädt mit drei Profilen, neun Reichs- und neun Speziesvorlagen vollständig unter dem aktuellen Modell.
- Die Quellsuche findet keine aktiven Aufrufer der entfernten APIs oder Produktionsfelder; historische Messberichte sind ausdrücklich ausgenommen.
