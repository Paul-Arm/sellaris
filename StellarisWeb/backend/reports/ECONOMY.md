# Monatliche Wirtschaft

Die Wirtschaft verwendet einen gemeinsamen Spielkalender: zwölf Monate mit jeweils 30 Tagen, Start 2200.01.01. Tag 30 ist 2200.02.01. Ressourcen, Datensynthese, Forschungsfortschritt und Bevölkerungswachstum werden an diesen Monatsgrenzen gebucht. Baukosten, Erstattungen, Handel und andere direkte Aktionen werden sofort verbucht. Bauaufträge, Reisen und Kämpfe behalten ihre eigenen Zeitabläufe.

## Monatsabschluss

- Der Zustand beim Monatsabschluss bestimmt den Ertrag. Ein zwischenzeitlich gebauter oder stillgelegter Distrikt beeinflusst die nächste Monatsbuchung. Es gibt keine anteiligen täglichen Erträge.
- Neue Kolonien nehmen an der nächsten gemeinsamen Monatsgrenze teil.
- Der persistierte Monatsanker verhindert doppelte Buchungen bei wiederholten Befehlen oder einem Reconnect. Aufrufe innerhalb desselben Monats verlassen die Buchung vor den Kolonie- und Anlagenscans.
- Das Backend verarbeitet ausstehende Monate nacheinander; die Bevölkerungsgruppen wachsen nach der Ressourcenproduktion. Forschung wird ebenfalls monatlich fortgeschrieben. Die normalen Tagesaufrufe berechnen zwischen Monatsgrenzen keinen Forschungsfortschritt.
- Der Hover zeigt eine Prognose mit der aktuellen Besetzung, Regierung, Technologie und Lage. Künftige Fertigstellungen, manuelle Änderungen oder Wetterwechsel können den tatsächlichen nächsten Abschluss verändern.
- Erträge und Ausgaben sind getrennte Bilanzposten. Produktionsboni und Krisen verändern den Gebäudeunterhalt nicht. Negative Nettosalden bleiben sichtbar; Lagerbestände werden nicht stillschweigend auf null gekappt.

## Compute und Einigkeit

Das Rechenbudget wird im Forschungsfenster zwischen Datensynthese, Produktionsoptimierung, Klimasimulation und dem verbleibenden Forschungsanteil verteilt. Reservierungen dürfen zusammen höchstens 100 % betragen. Nicht beschäftigte Forschungskapazität erzeugt Daten. Reservierte Klimasimulation bleibt auch ohne aktives Projekt gebunden.

Produktionsoptimierung erhöht Energie und Mineralien aus Arbeitsplätzen, orbitalem Bergbau und Anlagen. Bei `C` eingesetzten Compute beträgt der Bonus `0,5 × C / (20 + C)`; 20 Compute ergeben +25 %, der Grenzwert ist +50 %. Grundversorgung, Unterhalt, Daten und Compute bleiben davon unberührt. Bilanzposten zeigen den Bonus auch für Nebenwelten und Anlagen.

Terraforming teilt die reservierte Kapazität gleichmäßig unter laufenden Projekten. Pro Projekt gilt `Tempo = 1 + C / (10 + C)`: 10 Compute ergeben +50 % Tempo. Änderungen an Budget, Kapazität oder Projektzahl erhalten geleistete Arbeit und berechnen die Restdauer neu. Fortschritt, Tempo und Zeitanker werden gespeichert.

Einigkeit entsteht ausschließlich aus Bevölkerung und Regierung: jeder Pop liefert 0,5 Einigkeit pro Monat. Regierungseffekte verändern diesen Ertrag, beispielsweise Demokratie +10 %, synaptischer Nexus +15 % und Spiritualismus +10 % je Ethikstufe. Compute produziert und verstärkt keine Einigkeit. Regierungsreformen kosten 100 Energie und 150 Einigkeit. Einigkeit ist nicht handelbar.

Neue Partien verwenden die zusätzlichen Ressourcen- und Terraforming-Felder sowie das erweiterte Forschungsprogramm. Alte Partien werden nicht migriert.

## Erweiterungspunkte

`shared/resources.ts` enthält IDs, Namen, Farben, Icons und Grundversorgung. `RESOURCE_IDS`, `resourceAmounts` und `addResources` steuern die generische Ressourcenarithmetik. Inhaltsdefinitionen dürfen Ressourcen mit Wert null weglassen. `spacetimedb/src/resource-schema.ts` erzeugt die Ressourcenfelder für Speicherung und Transport aus dem Katalog.

Eine weitere Ressource wird im Katalog registriert, beispielsweise:

```ts
credits: { name: 'Credits', color: '#ecc878', icon: 'Diamond', base: 0 },
```

Anschließend wird sie in den gewünschten Job-, Anlagen-, Kosten- oder Belohnungsdefinitionen verwendet. Backend und TypeScript-Bindings mit `npm run backend:build` neu erzeugen und eine neue Partie starten. Alte Galaxien werden nicht migriert.

`shared/economy.ts` enthält Kategorien, Selektoren, Modifikatorarithmetik und Bilanzposten. `shared/planetaryEconomy.ts` berechnet Arbeitsplätze und planetare Posten. `shared/empireEconomy.ts` vereint Grundversorgung, Haupt- und Nebenplaneten, Bergbau, Systemanlagen und Datensynthese. `facilityLedger` teilt die Anlagenberechnung zwischen Backend und Anzeige.

## Modifikatoren und Spezies

Reiche, Planeten und lebende Spezies können `economyModifiers` enthalten. Diese Daten sind serverseitiger Spielzustand und werden nicht aus frei gesendeten Spielerbefehlen übernommen. Jeder Eintrag benötigt eine stabile ID und einen lesbaren Namen. Selektoren `category`, `resource`, `job` und `speciesId` müssen jeweils übereinstimmen; fehlende Selektoren begrenzen den Geltungsbereich nicht.

```ts
{ id: 'mining-specialists', name: 'Bergbauspezialisten',
  category: 'jobs', resource: 'minerals', job: 'foundry', percent: 0.2 }
{ id: 'maintenance-crisis', name: 'Wartungskrise',
  category: 'upkeep', resource: 'energy', percent: 0.3 }
```

Berechnung: `max(0, Basis + Summe(flat)) × max(0, 1 + Summe(percent)) × Produkt(factor)`. Prozentwerte sind Brüche: `0.2` bedeutet +20 %, `-0.2` bedeutet −20 %. Ein positiver Unterhaltsmodifikator erhöht die Ausgaben. Flache Produktionsboni gelten pro besetztem Job. Jeder Bilanzposten enthält Basis, Endbetrag und die rechnerischen Beiträge seiner Modifikatoren.

Die Besetzung reserviert zunächst Jobs nach Versorgung, Verteidigung und gewähltem Produktionsschwerpunkt. Danach werden Speziesgruppen deterministisch nach ihrer Eignung auf diese Kontingente verteilt. Merkmale und Bewohnbarkeit werden auf die tatsächlich besetzende Spezies angewendet. Es gibt keine Schleife über einzelne Pops; Aufwand und Speicher hängen von Distrikten und Speziesgruppen ab. Die Zuordnung ist eine priorisierte, deterministische Zuteilung, keine globale kombinatorische Optimierung.

## Prüfung

- `npm test`: gemeinsame Simulation, Kosten, Monatsgrenzen, Speziesverteilung, Modifikatorarithmetik und Bilanzsummen.
- `npm run backend:build`: Backend inklusive generierter Bindings.
- `node --import tsx --test backend/tests/economy.test.ts`: echte lokale Datenbank, monatliche Buchung gegen Prognose, sofortige Kosten, Wiederholung, Reconnect und Privatsphäre. Die Testdatenbank wird anschließend entfernt.
- Browserprüfung: neue Galaxie, pausierte Simulation, Ressourcenbilanz und aufklappbare Job-/Modifikatorposten.

## Vollständige Umstellung

Der frühere Vier-Tage-Takt ist auch im Lastsimulator entfernt. Kolonieerträge werden dort und im Spiel als `monthlyProduction` mit Feldern aus dem Ressourcenkatalog gespeichert; Handelsrouten führen `monthlyEnergy`. Die generierten Client-Bindings verwenden ausschließlich dieses Schema.

`Player.planetIncome`, `installationIncome` und `synthesisIncome` sowie deren Ersatzpfade sind entfernt. Topbar, Reichsübersicht und Systembilanz verwenden dieselben Bilanzposten. Auch Anlagenvorschauen berücksichtigen die aktuellen Wirtschaftsmodifikatoren. Neue Reiche verwenden immer vollständige Vorlagenregeln; es gibt weder einen Legacy-Schalter noch eine Spielstand-Nachrüstung.
