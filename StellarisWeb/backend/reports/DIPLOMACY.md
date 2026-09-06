# Diplomatie und Ablösung des Node-Spielservers

Stand: 5. September 2026. Lokale Windows-Umgebung, SpacetimeDB 2.10.0, TypeScript, React und Three.js.

## Entfernt

- Node-Spielschleife, periodische Welt-Snapshots und `sectors.json`-Speicherung.
- Alte WebSocket-Spielbefehle und alte Sitzungs-Wiederaufnahme im Server und Browser.
- Automatischer Legacy-Import, eingefrorene Importdateien als Gateway-Datenquelle und der veraltete Node-only-Containerstart.

Die vorherigen Quelldateien wurden einmalig nach `data/archive/node-backend-2026-09-05/` verschoben. Die nativen Galaxien `C5A092` und `7FC03D`, ihre Zuordnungen und die private Vorlagenbibliothek bleiben erhalten. Ein ausdrücklich administrativer Snapshot-Bootstrap bleibt für Wiederherstellung und reproduzierbare Tests bestehen. Gemeinsame reine Regelbausteine bleiben ebenfalls erhalten; kein Node-Prozess simuliert damit eine Partie.

## Spielregeln

- Standardbeziehung Frieden. Nur explizite Kriegsgegner kämpfen, belagern oder blockieren zivile Missionen. Unabhängige Wächter bleiben feindlich.
- Friedensangebot muss vom anderen Reich angenommen werden. Alle gemeinsamen Gefechte enden sofort ohne Sieger; Schiffe und bereits erfasster Schaden bleiben erhalten. Anschließend gelten 120 Spielsekunden Waffenstillstand.
- Rohstofftausch: Energie, Mineralien und Forschung, ganzzahlige Mengen bis 10.000 je Rohstoff. Angebot für 60 Spielsekunden; Absenderbetrag wird sofort reserviert. Annahme prüft die Ressourcen des Empfängers und überträgt beide Seiten atomar.
- Ablehnung, Rücknahme, Krieg oder Ablauf erstatten reservierte Rohstoffe genau einmal. Pause hält Fristen an. Ein offenes Angebot je Paar/Art und acht ausgehende Angebote je Reich begrenzen die offenen Vorgänge; bis zu 200 abgeschlossene Vorgänge bleiben als Historie erhalten.
- Beziehungen sind öffentlich. Vertragsbedingungen sehen ausschließlich die beiden beteiligten Reiche. Diplomatie erweitert keine taktischen Schiffsabonnements.
- KI nimmt Frieden an und akzeptiert bezahlbare, mindestens gleichwertige Tauschangebote (Werte: Energie 1, Mineralien 1,2, Forschung 2). Selbständige Kriegserklärung und differenzierte Außenpolitik sind noch offen.

## Prüfung

- `npm test`: 62 Tests bestanden.
- `npm run backend:test`: 25 Tests bestanden, einschließlich drei neuer Diplomatie-Szenarien.
- Produktions-Test gezielt nach Ergänzung der 3×-Zeitsteuerung erneut bestanden.
- `npm run backend:build` und `npm run build` bestanden.
- Reale private Identitäten: unbefugte Annahme/Rücknahme, ungültige Mengen, Überziehung, doppelte Angebote und doppelte Annahme werden abgewiesen. Fehlgeschlagene Annahme verändert keine Ressourcen.
- Wiederverbindung rekonstruiert offene Angebote und reservierte Ressourcen. Der isolierte Prozessabsturz auf Port 3110 erhält Angebot, Frist und Guthaben; Rückerstattung funktioniert nach Neustart genau einmal.
- Friedliche Koexistenz, ausbleibende Belagerung, zivile Untersuchung, expliziter Kampfbeginn und Frieden während eines laufenden Gefechts geprüft. Keine versteckten taktischen Daten in der Galaxieansicht.
- Browserprüfung über getrennten Test-Gateway auf Port 52304: zwei Menschen gründen/beitreten, 50 Energie gegen 40 Mineralien anbieten und nach Modulupdate annehmen, Krieg erklären, Frieden anbieten/annehmen. Beide Oberflächen zeigen angenommenen Frieden und den geschützten Waffenstillstand. Keine Warnungen/Fehler im geprüften Konsolenprotokoll. Dialog visuell bei 1280 × 720 geprüft; keine Aussage über eine vollständige mobile Prüfung.
- Beide registrierten Spielgalaxien lokal ohne Datenreset aktualisiert. Update-Werkzeug pausiert vor Veröffentlichung, übernimmt bestehende aktive Gefechte als Krieg und stellt den vorherigen Zeitmodus wieder her. Labordatenbanken bleiben davon unabhängig.
- Bestehende Browser-Sitzung `7FC03D` nach Neuladen erfolgreich wiederaufgenommen, Diplomatie geöffnet und Browserprotokoll ohne Warnungen/Fehler geprüft. Beide Testtabs geschlossen und der eigene Test-Gateway beendet; normaler Server und SpacetimeDB laufen weiter.

Weiterer Ausbau: dauerhafte Handelsrouten/-abkommen, Bündnisse, diplomatische KI, Ereignisentscheidungen und Krisen. Dieser Stand enthält direkten Rohstofftausch, keine vollständige Handelssimulation.
