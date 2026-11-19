"""Version 1.1.0.0: Changelog an die Store-Beschreibung haengen (DE/EN/FR) und
modhub_vorbereitet aus der modDesc neu schreiben. Die Beschreibung selbst wird
aus der modDesc gelesen und bleibt, wie sie ist. Laeuft mehrfach ohne Schaden,
ein vorhandener Changelog-Block wird ersetzt."""
import io
import os
import re

BASIS = os.path.dirname(os.path.abspath(__file__))
PFAD = os.path.join(BASIS, "modDesc.xml")
VERSION = "1.1.0.0"

CHANGELOG = {
    "de": """Changelog 1.1.0.0:
- Kassenbuch: Strg+K zeigt im Spiel, wofür das Geld weggeht, als Rangliste mit Balken und mit den letzten Buchungen. Monate und Jahre lassen sich bis zum Anfang des vorigen Spieljahres zurückblättern, unten steht der Vergleich mit dem Monat davor oder dem Vorjahr. Grundsteuer und Fuhrpark-Steuer stehen als eigene Buchung drin. Im Spielstand-Ordner liegen dazu eine CSV-Tabelle und eine HTML-Seite mit Diagrammen. Der Konsolenbefehl aoKassenbuch schreibt sie sofort.
- Sicherheitsbremse: Wenn Grundsteuer und Fuhrpark-Steuer am selben Tag fällig sind und das Budget nicht für beide reicht, werden beide um denselben Anteil gekürzt. Bisher bekam der Posten, der als zweiter abgerechnet wurde, oft gar nichts mehr ab. Eine Kürzung meldet die Mod jetzt oben rechts, aoStatus zeigt die letzte je Hof.
- Produktionsgeschwindigkeit: Die laufenden Kosten haben drei Stufen statt an/aus: voll mit, Wurzel des Faktors oder gleich bleibend. Wer vorher an hatte, landet bei voll mit, aus wird zu gleich bleibend.
- Hilfeseiten und Beschreibung sind überarbeitet.""",
    "en": """Changelog 1.1.0.0:
- Cash book: press Ctrl+K to see where your money goes, as a ranking with bars plus the latest bookings. You can page back through months and years as far as the start of last game year, and the bottom line compares with the month before or with last year. Property tax and fleet tax appear as bookings of their own. The savegame folder also gets a CSV table and an HTML page with charts; the console command aoKassenbuch writes them right away.
- Safety brake: when property tax and fleet tax fall on the same day and the daily budget cannot cover both, they are now cut by the same share. Before, whichever was billed second often got nothing at all. A cut now shows up as a notification in the top right, and aoStatus lists the last one per farm.
- Production speed: running costs have three options instead of on/off: full, square root or unchanged. If you had it on, you get full; off becomes unchanged.
- Help pages and store text reworked.""",
    "fr": """Changelog 1.1.0.0 :
- Livre de caisse : Ctrl+K montre dans le jeu où part l'argent, avec un classement en barres et les dernières opérations. On remonte mois par mois ou année par année jusqu'au début de l'année de jeu précédente, et la ligne du bas compare avec le mois d'avant ou avec l'année précédente. L'impôt foncier et la taxe de flotte apparaissent comme des opérations à part. Le dossier de sauvegarde reçoit aussi un tableau CSV et une page HTML avec graphiques ; la commande aoKassenbuch les écrit tout de suite.
- Frein de sécurité : quand l'impôt foncier et la taxe de flotte tombent le même jour et que le budget ne suffit pas, les deux sont réduits dans la même proportion. Avant, celui qui passait en second n'obtenait souvent plus rien. Une réduction s'affiche désormais en haut à droite, et aoStatus indique la dernière par exploitation.
- Vitesse de production : les frais de fonctionnement proposent trois choix au lieu de oui/non : plein, racine du facteur ou inchangés. Activé devient plein, désactivé devient inchangés.
- Pages d'aide et description retravaillées.""",
}

TITEL = {"de": "TITEL: Agrar-Ökonomie", "en": "TITLE: Farm Economy", "fr": "TITRE: Économie Agricole"}

for sp, text in CHANGELOG.items():
    assert "—" not in text and "–" not in text and " - " not in text, "Gedankenstrich in " + sp

t = io.open(PFAD, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in t else "\n"

alt = re.compile(r"<version>[^<]*</version>")
assert len(alt.findall(t)) == 1
t = alt.sub("<version>%s</version>" % VERSION, t)

beschreibung = {}
for sp, log in CHANGELOG.items():
    muster = re.compile(r"(<description>.*?<%s><!\[CDATA\[)(.*?)(\]\]></%s>)" % (sp, sp), re.S)
    treffer = muster.findall(t)
    assert len(treffer) == 1, sp
    text = treffer[0][1].replace("\r\n", "\n")
    text = re.split(r"\n\nChangelog ", text)[0].rstrip()
    text = text + "\n\n" + log
    beschreibung[sp] = text
    t = muster.sub(lambda m: m.group(1) + text.replace("\n", nl) + m.group(3), t)

io.open(PFAD, "w", encoding="utf-8", newline="").write(t)

ordner = os.path.join(BASIS, "modhub_vorbereitet")
for sp, datei in (("de", "DE"), ("en", "EN"), ("fr", "FR")):
    ziel = os.path.join(ordner, "beschreibung_%s.txt" % datei)
    io.open(ziel, "w", encoding="utf-8", newline="\r\n").write(TITEL[sp] + "\n\n" + beschreibung[sp] + "\n")
    print("%s: %d Zeichen" % (sp, len(beschreibung[sp])))
print("Version", VERSION)
