# Ereignisse und Resonanzkaskade

Geprüft am 05.09.2026. Die normale Partie verwendet ausschließlich SpacetimeDB; diese Erweiterung fügt dauerhafte Entscheidungen und eine erste galaktische Krise hinzu.

## Spielbarer Umfang

- Die erste Untersuchung einer noch unberührten stellaren Anomalie eröffnet ein privates Archiv-Ereignis. Nur das zuerst entdeckende Reich erhält diesen Fund. Die normale Untersuchungsprämie bleibt erhalten.
- Die erste neue Außenkolonie eines Reiches eröffnet eine Entscheidung über gefundene Speicher. Weitere Kolonien duplizieren dieses Ereignis nicht.
- Entscheidungen enthalten Kosten, Erträge, Quelle, Frist und gespeichertes Ergebnis. Archive und Koloniefunde haben 90 Spielsekunden Frist, die erste Krisenreaktion 120. Ein Ablauf wählt jeweils die kostenlose Standardoption.
- Die Resonanzkaskade startet nach 180 Spielsekunden Vorlauf oder früher durch Untersuchung ihres Risses. Auf die Vorwarnung folgen nach jeweils 120 Spielsekunden Produktionsverluste von 25 und 50 Prozent. Betroffen ist die ungeschützte Kolonieproduktion; die Grundversorgung bleibt bestehen.
- Eigene Abschirmung kostet 120 Energie und gilt auch für später gegründete eigene Kolonien. Ein gemeinsamer Beitrag kostet 60 Energie und 30 Forschung. Das Ziel wird bei der Vorwarnung auf `3 + ceil(Imperienzahl / 2)` festgelegt. Nachfinanzierung durch spätere Beitritte ist möglich, ohne das Ziel zu vergrößern.
- Eindämmung beendet die Krise dauerhaft, stellt die Produktion wieder her und verteilt einmalig 40 Forschung pro Beitrag. Noch offene Krisenreaktionen werden geschlossen; bereits gewählte Entscheidungen bleiben erhalten.
- Das Lagezentrum bietet Fundort-Navigation, Phasenanzeige, Beiträge und Beschlussverlauf. Die Seitenleiste zeigt einen kompakten Hinweis. Es gibt keinen zusätzlichen individuellen Gefechtsstrom.

## Automatisierte Nachweise

`npm test`: **62 bestanden**. `npm run backend:test`: **27 bestanden**. `npm run backend:build`, `npm run check` und `npm run build`: erfolgreich. Vite meldet einen Größenhinweis für das Hauptbundle knapp über 500 kB; dies ist kein Buildfehler.

`backend/tests/stories.test.ts` prüft mit unabhängigen Identitäten und echten Reducer-Transaktionen:

- Besitzschutz und private Abonnements; nur ein Fund bei konkurrierender Erstuntersuchung.
- Ablehnung unbekannter Optionen, fremder Entscheidungen und unzureichender Mittel ohne Nebenwirkungen.
- Korrekte Ressourcenänderungen und Ablehnung einer wiederholten abgeschlossenen Entscheidung.
- Idempotente Initialisierung, pausierte Fristen und Wiederverbindung mit derselben Identität.
- Warnung, aktive Welle und Kaskade; Abschirmung nur des bezahlenden Reiches.
- Übereinstimmung von Client-Erträgen, gespeicherten Kolonieraten und tatsächlich gutgeschriebenen Ressourcen.
- Kostenlose Standardreaktion bei Ablauf, spätere Beitritte und unverändertes Finanzierungsziel.
- Gemeinsame Eindämmung, private Beitragsstände, einmalige Vergütung und Schließen noch offener Reaktionen.

Der bestehende isolierte Absturztest auf Port 3110 wurde um eine laufende Produktionskrise, eine offene Entscheidung und einen bezahlten Beitrag erweitert. Nach erzwungenem Prozessende sind Identität, Wirtschaft, Reisen, Entscheidungen, Krisenphase, Fristen und Beiträge identisch wiederhergestellt. Die Uhr wird vor dem Absturz für einen exakten Vergleich pausiert. Die normale Instanz auf Port 3100 wird dabei nicht beendet.

## Browserprüfung und bestehende Galaxien

Im isolierten Testsektor **665EBA** auf Port 52305 wurde mit dem gebauten Browserclient geprüft:

1. Reich aus der Bibliothek wählen und eine native Galaxie mit 1.000 Systemen gründen.
2. Lagezentrum öffnen, zum goldenen Riss navigieren, Forschungsschiff entsenden und die reguläre Untersuchung abschließen.
3. Simulation pausieren und über die Ereignisentscheidung die eigenen Kolonien abschirmen.
4. Einen Beitrag leisten, Seite neu laden und erhaltene Frist, Abschirmung, Beitrag und Beschlussverlauf kontrollieren.
5. Drei weitere Beiträge leisten und die Eindämmung mit 160 Forschung Gesamtvergütung im Browser nachvollziehen.

Das Layout wurde bei 1280 × 720 visuell geprüft, einschließlich des scrollbar erreichbaren Entscheidungsbereichs. Browserfehler/-warnungen: keine. Der Testsektor bleibt pausiert; sein eigener Gateway wird nach der Prüfung beendet.

`npm run backend:update-games` hat **C5A092** und **7FC03D** ohne Datenreset aktualisiert. Vorhandene Spieluhren werden für die Veröffentlichung pausiert und danach wiederhergestellt. Fehlende Krisendaten erhalten einen neuen Vorlauf ab der aktuellen Spielzeit. Die vorhandene Sitzung in **7FC03D** wurde im Browser wieder aufgenommen und das Lagezentrum geöffnet; keine zusätzlichen Testspieler oder Testentscheidungen wurden dort erzeugt.

## Grenzen und nächste Schritte

Dies ist ein versionierter Katalog mit drei Ereignissen und einer Krise. Mehrstufige Geschichten, weitere Krisentypen, Diplomatie rund um Beiträge und weitergehende Krisenstrategien der KI sind offen. Die KI wählt derzeit die erste bezahlbare Ereignisoption nach denselben Regeln. Historische Lastmessungen gelten weiterhin als Messpunkte des jeweiligen damaligen Stands; für diese Erweiterung wurde keine neue Lastprobe mit 75.000 Schiffen durchgeführt.
