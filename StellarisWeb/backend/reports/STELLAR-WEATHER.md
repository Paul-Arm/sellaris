# Natürliche Sternenstürme

Erste natürliche Sternereignisse sind spielbar. Bei der abgeschlossenen Erkundung eines ausgewählten Riesensterns wird ein bevorstehender Ausbruch entdeckt. Die Auswahl ist reproduzierbar: ein Viertel der Systemkennungen qualifiziert sich, zusätzlich muss der aktive Zentralkörper ein Riesenstern sein. Pro System gibt es derzeit einen Zyklus.

## Ablauf und Wirkung

- 120 Spieltage Vorwarnung, danach 60 Spieltage Sturm und automatische Erholung.
- Sonnenkollektoren und Dyson-Anlagen liefern während des Sturms 25 % ihres Energieertrags. Der Faktor multipliziert sich mit einer bestehenden Resonanzkrise.
- Andere Anlagen, Kolonien, Bauprojekte, Schiffe und Körperbestände werden durch dieses Ereignis nicht beschädigt. Der Materiedekompressor ist nicht betroffen.
- Ein zweites Reich kann denselben Zyklus entdecken; Erkundung startet weder Fristen noch Ereignisse erneut.
- Ein kontrollierter Sternkollaps beendet den Zyklus. Seine eigene Regel für den Verlust solarer Anlagen gilt weiterhin.

## Dauerhafter Zustand und Abrechnung

`gameStellarWeather` speichert den Sternbezug, Entdeckungszeit, feste Anfangs-/Endzeit, Phase und den indizierten nächsten Übergang. Es gibt keinen Spielerbefehl zum Erzeugen, Verlängern oder Abbrechen von Stürmen. Der vorhandene autoritative Erkundungsabschluss erzeugt die Vorhersage; die Spieluhr steuert alle Fristen einschließlich Pause und Geschwindigkeit.

Die Mitglieds-View liefert Vorhersagen nur für selbst untersuchte oder eigene Systeme. Unangemeldete Verbindungen erhalten keine Zeilen. Meldungen gehen an die betroffenen informierten Reiche. Ein neuer Besitzer sieht den bestehenden Zustand.

Die Rohstoffabrechnung zählt die betroffenen Vier-Tage-Auszahlungen anhand des Intervalls `[Beginn, Ende)`. Auch eine verzögerte Abrechnung über beide Grenzen hinweg berechnet den richtigen Verlust. Vergangene Ereignisse bleiben als Abrechnungshistorie gespeichert. Der Browser verwendet dieselbe Zeitfensterregel für Anlagen-, System- und Reichserträge.

## Oberfläche

Lagezentrum und Inspektor des Sterns beziehungsweise seiner Dyson-Anlage zeigen Warnung, aktive Phase, Resttage, Pause und Erholung. Das Lagezentrum verlinkt den Fundort. Eine aktive Warnung erreicht auch die kompakte Lageanzeige. Die Sturmkarte hat eine eigene CSS-Datei und funktioniert ohne zuvor geöffnete Systemansicht.

## Geprüft

- 136 Regeltests bestanden, darunter Zielauswahl, Zeitgrenzen, Dyson-/Krisenfaktoren sowie verzögerte und aufgeteilte Auszahlungen.
- Nativer Datenbanktest: tatsächlicher Erkundungsabschluss, private Sichtbarkeit, zweite Entdeckung, Pause, Wiederverbindung, gebauter Sonnenkollektor, exakt gebuchte reduzierte Energie, einmalige Erholung und unveränderte Körper-IDs.
- Bestehender nativer Dyson-/Sternkollaps-Test bestanden.
- TypeScript für Frontend und Modul sowie Produktionsbuild bestanden.
- Browser-Darstellungsprüfung der tatsächlichen Komponenten mit isolierten Beispieldaten für Vorwarnung, Sturm und Erholung sowie Fundort-Link; keine Browserfehler. Diese Darstellungsprüfung ersetzt keine vollständige Browserpartie.

Supernovae, dauerhafte natürliche Sternumwandlungen, zerstörte Elternkörper und aktive Gegenmaßnahmen bleiben weitere Ausbauschritte.
