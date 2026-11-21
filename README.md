# Agrar-Ökonomie

Wirtschaftssimulation: Steuern, Reparaturen, Löhne, Spritverbrauch, Preise.

Im Grundspiel spielt Geld nach ein paar Ernten keine Rolle mehr. Die Erlöse sind hoch, und ein bezahlter Traktor kostet danach nur noch Diesel. Farm Economy dreht an beiden Enden.

Feldfrüchte und Erzeugnisse aus Produktionen bringen weniger ein. Milch, Tiere, Holz, Ballen und Aufträge bleiben, wie sie sind. Wie stark gekürzt wird, kann eine Automatik übernehmen: Einmal im Spieljahr schaut sie, was dein Hof pro Hektar verdient hat, und stellt nach, bis es zur gewählten Schwierigkeit passt.

Bei den Kosten zahlst du laufend für jedes eigene Fahrzeug und Gerät. Was im Abrechnungszeitraum nur herumstand oder in der Halle parkt, kommt günstiger weg. Reparaturen werden mit den Betriebsstunden teurer. Helfer gibt es in Lohnstufen, bei zu knappem Angebot sagen sie auch mal ab, und beim Festpreis zahlst du nur für fertige Arbeit. Pressen und Wickler brauchen mehr Garn, Netz und Folie. Wer mag, schaltet noch eine Grundsteuer auf gekauftes Land dazu.

Ab Werk aus, aber dabei: Spritverbrauch stufenlos statt Wenig/Normal/Hoch, getrennt für Feld und Straße, auf Wunsch aus der Motorleistung gerechnet und im Tacho angezeigt. Guthabenzinsen auf Kontostand minus Kredit, gestaffelt, damit ein volles Konto nicht von allein wächst. Und eine Produktionsgeschwindigkeit für alle Produktionen oder einzelne Gebäude.

Damit kein Spielstand kaputtgeht, gibt es eine Bremse. Die Mod darf pro Tag nur einen Teil der üblichen Einnahmen abbuchen, und unter einem Mindestkontostand zieht sie gar nichts mehr ab.

Wohin das Geld fließt, zeigt der Hof-PC: Strg+K schaltet ihn ein, zu Fuß wie im Fahrzeug. Das Kassenbuch darin hat eine Rangliste der größten Posten und die letzten Buchungen, Monat für Monat und Jahr für Jahr. Der Fuhrpark führt für jede Maschine ein eigenes Konto mit Wertverlust, Reparaturen, Diesel und Steuer, dazu Kosten je Betriebsstunde. Unter Abgaben & Helfer stehen Steuern, Zinsen, Helferlöhne und wie viel Luft die Bremse noch lässt. Die Buchungen dieses und des vorigen Spieljahres landen mit Spielmonat, Gruppe und Betrag in einer Datei im Ordner des Spielstands: als Tabelle für die Tabellenkalkulation und als fertige Seite mit Diagrammen, die sich im Browser öffnen lässt. Posten, die im Sekundentakt anfallen, etwa Sprit und laufende Kosten, stehen als Tagessumme darin, sonst wäre die Datei nach einer Stunde nicht mehr lesbar.

Eingestellt wird im ESC-Menü unter Einstellungen, Reiter Agrar-Ökonomie, im Multiplayer nur von Admins. Die Hilfe im Spiel erklärt jeden Teil. Läuft auf jeder Karte, auch mit Früchten, die das Grundspiel nicht kennt. Zusammen mit der Mod Betriebsübersicht (Farm Overview) bekommst du außerdem einen Jahresvergleich deiner Finanzen, und deren Übersicht über Felder, Tiere und Lager steht dann auch im Hof-PC.

Nur PC/Mac.

Changelog 1.2.0.0:
- Hof-PC: Strg+K öffnet jetzt statt des Kassenbuch-Fensters einen Hof-PC, auch im Fahrzeug. Darauf laufen Start, Kassenbuch, Fuhrpark, Abgaben & Helfer und, wenn Farm Overview geladen ist, die Betriebsübersicht. Lange Listen blättern mit dem Mausrad oder über die Pfeile am Rand.
- Fuhrpark: Jede Maschine führt ein eigenes Konto mit Wertverlust, Reparaturen, Diesel, Fuhrpark-Steuer und Unterhalt, für das laufende Spieljahr und seit dem Kauf. Die Liste lässt sich nach Kosten sortieren und zeigt die Kosten je Betriebsstunde. Für Maschinen, die schon vor dem Update auf dem Hof standen, rechnet die Mod Betriebsstunden und Wertverlust seit dem Kauf nach. Die Maschinenkonten lassen sich in den Einstellungen abschalten.
- Diesel, den ein Helfer verfährt, landet beim richtigen Fahrzeug. Guthabenzinsen stehen im Kassenbuch als eigener Posten.
- Kassenbuch: Kleinstbeträge unter 10 € stehen nicht mehr in der Liste der letzten Buchungen. In der Datei im Spielstand bleiben sie erhalten.
- Einzelspieler: Kassenbuch und Jahresvergleich werden immer dem eigenen Hof zugeordnet.

## Installation

Die ZIP aus den [Releases](../../releases) herunterladen und in den
Mods-Ordner legen:

    Dokumente\My Games\FarmingSimulator2025\mods

Auf einem Dedicated Server gehoert sie in dessen Mods-Ordner.

## Stand

Version 1.2.0.0, gebaut gegen descVersion 116.

## Lizenz

Alle Rechte vorbehalten, Einzelheiten in LICENSE.txt. Der Quelltext liegt
offen, damit man sieht, was die Mod tut - eine Freigabe zur
Weiterverwendung ist das nicht.
