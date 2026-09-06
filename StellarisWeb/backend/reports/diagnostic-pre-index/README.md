# Diagnoseläufe, nicht der abschließende Vergleich

Diese frühen Messungen zeigten rund eine Sekunde zusätzlichen Aufwand beim Beitritt zur kompakten Gefechtsansicht. Die Ursache war die Integritätsprüfung im Lastclient: `index.find()` des SDK 2.10 durchsucht den lokalen Cache vollständig, wodurch die Prüfung der drei Teilansichten quadratisch wurde. Der Serverrückstand stieg dabei nicht entsprechend an.

Die Prüfung verwendet jetzt einmal aufgebaute Maps. Der Renderer pflegt seine Zuordnung ebenfalls über Änderungsereignisse, damit keine quadratische Suche pro Frame entsteht. Alle abschließenden Vergleichsläufe im übergeordneten Verzeichnis wurden mit derselben korrigierten Clientversion wiederholt. Während des frühen unkomprimierten Kompaktlaufs wurde zusätzlich ein Frontendbuild ausgeführt; auch deshalb zählt dieser Lauf nicht als abschließender Vergleich.
