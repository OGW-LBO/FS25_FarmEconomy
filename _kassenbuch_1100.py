"""Texte zum Kassenbuch mit Blaettern (1.1.0.0): neue Schluessel, ersetzte
Hilfeseiten, die alten Zeitraum-Texte raus, Absatz in der Beschreibung.
Laeuft mehrfach ohne Schaden."""
import io
import os
import re

BASIS = os.path.dirname(os.path.abspath(__file__))
PFAD = os.path.join(BASIS, "modDesc.xml")

# (schluessel, de, en, fr, einfuegen_nach)
TEXTE = [
    ("ao_buch_ansicht", "Ansicht", "View", "Affichage", "ao_buch_zeitraum"),
    ("ao_buch_vonBis", "%s bis %s", "%s to %s", "%s à %s", "ao_buch_ansicht"),
    ("ao_buch_ansMonat", "Monat", "Month", "Mois", "ao_buch_ansicht"),
    ("ao_buch_ansJahr", "Jahr", "Year", "Année", "ao_buch_ansMonat"),
    ("ao_buch_vglMonat",
     "Gegenüber %s: %s.",
     "Compared with %s: %s.",
     "Par rapport à %s : %s.",
     "ao_buch_ansJahr"),
    ("ao_buch_vglJahr",
     "Gegenüber denselben Monaten im %s: %s.",
     "Compared with the same months of %s: %s.",
     "Par rapport aux mêmes mois de l'%s : %s.",
     "ao_buch_vglMonat"),
    ("ao_buch_vglEin", "Einnahmen %s", "income %s", "revenus %s", "ao_buch_vglJahr"),
    ("ao_buch_vglAus", "Ausgaben %s", "expenses %s", "dépenses %s", "ao_buch_vglEin"),
    ("ao_buch_fussDatei",
     "Die Buchungen dieses und des vorigen Spieljahres liegen mit Diagrammen auch als Datei im Ordner des Spielstands.",
     "This year's and last year's bookings are also saved as a file with charts in the savegame folder.",
     "Les opérations de cette année et de l'année précédente sont aussi enregistrées, avec graphiques, dans un fichier du dossier de sauvegarde.",
     "ao_buch_vglAus"),

    ("ao_help_buchFenster",
     "Keine Lust, im Spielstand-Ordner nach der Datei zu suchen? Strg+K öffnet das Kassenbuch direkt im Spiel. "
     "In der ersten Zeile wählst du, ob du Monate oder Jahre sehen willst, in der zweiten blätterst du mit den Pfeilen "
     "zurück, bis zum Anfang des vorigen Spieljahres. Oben stehen Einnahmen, Ausgaben, Investitionen und der Saldo für "
     "den gewählten Zeitraum. Links darunter zeigt eine Rangliste mit Balken, wofür das Geld weggeht. Der größte Posten "
     "steht oben, Investitionen sind grün, laufende Kosten orange. Rechts stehen die letzten Buchungen mit Uhrzeit, Gruppe "
     "und Betrag, Grundsteuer und Fuhrpark-Steuer unter ihrem eigenen Namen. Die Zeile ganz unten vergleicht mit dem Monat "
     "davor, beim laufenden Jahr mit denselben Monaten des Vorjahres. Im Mehrspieler bekommt jeder die Zahlen seines eigenen "
     "Hofes zu sehen. Gerechnet wird auf dem Server, der Client fragt beim Öffnen dort nach. Die Taste kannst du in den "
     "Spieleinstellungen umlegen.",
     "Ctrl+K brings up the cash book in the game, so there's no need to dig through the savegame folder. The first row "
     "switches between months and years, the second lets you page back with the arrows, as far as the start of last game "
     "year. At the top you see income, expenses, investments and the balance for that period. Bottom left is a bar ranking "
     "of where your money goes, biggest item first, with investments in green and running costs in orange. On the right you "
     "get the latest bookings with time, group and amount, and property tax and fleet tax show up under their own names. "
     "The line at the very bottom compares with the month before, or for the current year with the same months of last "
     "year. In multiplayer each player sees their own farm's figures. The server does the maths and the client asks for "
     "them when the window opens. You can rebind the key in the game settings.",
     "Pas besoin de connaître le dossier de sauvegarde : Ctrl+K ouvre le livre de caisse en plein jeu. La première ligne "
     "choisit entre mois et années, la seconde permet de remonter avec les flèches jusqu'au début de l'année de jeu "
     "précédente. En haut figurent les revenus, les dépenses, les investissements et le solde de la période choisie. En bas "
     "à gauche, un classement en barres montre où part l'argent, le poste le plus lourd en premier ; les investissements "
     "sont en vert, les frais courants en orange. La partie droite liste les dernières opérations avec l'heure, le groupe et "
     "le montant, l'impôt foncier et la taxe de flotte sous leur propre nom. Tout en bas, la fenêtre compare avec le mois "
     "précédent, ou pour l'année en cours avec les mêmes mois de l'année d'avant. En multijoueur, chacun ne voit que les "
     "chiffres de sa propre exploitation : le serveur fait le calcul et le client le lui demande à l'ouverture. La touche "
     "se change dans les réglages du jeu.",
     None),

    ("ao_help_buchDatei",
     "Die Dateien liegen im Ordner des Spielstands neben der farms.xml, auf einem Server holst du sie also per FTP. Es sind "
     "drei, alle heißen FS25_FarmEconomy_Kassenbuch und enthalten die Buchungen des laufenden und des vorigen Spieljahres, "
     "höchstens 2000. Was älter ist, fällt beim Jahreswechsel heraus. Die .html ist eine fertige Seite mit Diagrammen, ein "
     "Doppelklick öffnet sie im Browser. Die .csv ist dieselbe Liste für Excel oder LibreOffice, mit Semikolon als "
     "Trennzeichen und Komma als Dezimalzeichen. Die .xml ist für die Mod selbst, daraus holt sie beim Laden ihren Stand "
     "zurück. Geschrieben wird eine Minute nach einer neuen Buchung, beim Tageswechsel und bei jedem Speichern. Sofort geht "
     "es mit aoKassenbuch in der Konsole, der Befehl nennt auch beide Pfade.",
     "Look in the savegame folder, right next to farms.xml; on a server you can grab the files by FTP. There are three of "
     "them, all called FS25_FarmEconomy_Kassenbuch and holding the bookings of this game year and the one before, up to "
     "2000. Anything older is dropped when the year changes. Double-click the .html and your browser shows a finished page "
     "with charts. The .csv has the same list for Excel or LibreOffice, with semicolons as separators and a comma as the "
     "decimal mark. The .xml is for the mod itself, it reads its state back from there on load. They get written a minute "
     "after a new booking, at every change of day and whenever you save. The console command aoKassenbuch writes them "
     "right away and names both paths.",
     "Trois fichiers, tous nommés FS25_FarmEconomy_Kassenbuch, se trouvent dans le dossier de la sauvegarde, à côté de "
     "farms.xml. Sur un serveur, vous les récupérez donc par FTP. Ils contiennent les opérations de l'année de jeu en cours "
     "et de la précédente, 2000 au plus ; ce qui est plus ancien disparaît au changement d'année. Le .html est une page "
     "toute prête avec graphiques, qu'un double clic ouvre dans le navigateur. Le .csv reprend la même liste pour Excel ou "
     "LibreOffice, avec le point-virgule comme séparateur et la virgule pour les décimales. Quant au .xml, c'est là que le "
     "mod retrouve son état au chargement. L'écriture a lieu une minute après une nouvelle opération, à chaque changement "
     "de jour et à chaque sauvegarde. Pressé ? La commande console aoKassenbuch écrit tout de suite et indique les deux "
     "chemins.",
     None),
]

# Aeltere Meldungen und Tooltips, die noch mit " - " gebaut waren
TEXTE += [
    ("hl_keineHelferFest",
     "Kein Helfer für '%s' zu %s, gefordert sind etwa %s.",
     "No helper for '%s' at %s, they want about %s.",
     "Aucun ouvrier pour '%s' à %s, il en demande environ %s.",
     None),
    ("hl_abgebrochen",
     "Auftrag abgebrochen, es ist kein Lohn fällig.",
     "Job cancelled, no wage is due.",
     "Mission interrompue, aucun salaire n'est dû.",
     None),
    ("ao_ui_karenzMonate_t",
     "So viele Spielmonate bleibt ein frisch gekauftes Fahrzeug steuerfrei. Das entlastet Käufe auf Kredit.",
     "How many in-game months a newly bought vehicle stays tax free. Helps when you buy on credit.",
     "Nombre de mois de jeu pendant lesquels un véhicule neuf reste exonéré. Cela soulage les achats à crédit.",
     None),
    ("ao_ui_gsAktiv_t",
     "Laufende Kosten auf gekauftes Land. Als einziger Posten wächst er mit der Fläche.",
     "Recurring costs on owned land. It is the only item that grows with acreage.",
     "Coûts récurrents sur les terres achetées. C'est le seul poste qui croît avec la surface.",
     None),
    ("ao_ui_vNurEigene_t",
     "Auftrags- und Leihmaschinen behalten den Originalverbrauch, sonst bleibt nachgekauftes Material bei der Rückgabe in der Maschine.",
     "Contract and leased machines keep the original usage, otherwise material you buy stays in the machine when it is returned.",
     "Les machines de mission et en leasing gardent la consommation d'origine, sinon le matériel acheté reste dans la machine au retour.",
     None),
    ("ao_msg_autoZuWenig",
     "Jahresbilanz: zu wenig Feldfläche oder Verkäufe, die Faktoren bleiben, wie sie sind.",
     "Yearly result: not enough field area or sales, so the factors stay as they are.",
     "Bilan annuel : pas assez de surface ou de ventes, les facteurs restent inchangés.",
     None),
    ("ao_rep_secStandOhne",
     "Stand des Betriebs (Vergleich ab dem nächsten Spieljahr)",
     "Farm position (comparison from next in-game year)",
     "Situation de l'exploitation (comparaison dès l'année de jeu suivante)",
     None),
]

ENTFERNEN = ["ao_buch_zrMonat", "ao_buch_zrJahr", "ao_buch_zrAlles", "ao_buch_fussFenster"]

# Absatz zum Kassenbuch in der Store-Beschreibung: (alt, neu)
BESCHREIBUNG = [
    ("mit einer Rangliste der größten Posten und den letzten Buchungen. Jede Buchung landet mit Spielmonat",
     "mit einer Rangliste der größten Posten und den letzten Buchungen, Monat für Monat und Jahr für Jahr. "
     "Die Buchungen dieses und des vorigen Spieljahres landen mit Spielmonat"),
    ("with a ranking of the largest items and the latest bookings. Every booking is written to a file",
     "with a ranking of the largest items and the latest bookings, month by month or year by year. "
     "This year's and last year's bookings are written to a file"),
    ("avec un classement des plus gros postes et les dernières opérations. Chaque opération est écrite dans un fichier",
     "avec un classement des plus gros postes et les dernières opérations, mois par mois ou année par année. "
     "Les opérations de l'année de jeu en cours et de la précédente sont écrites dans un fichier"),
]


def block(schluessel, de, en, fr, nl):
    return nl.join([
        '        <text name="%s">' % schluessel,
        "            <de>%s</de>" % de,
        "            <en>%s</en>" % en,
        "            <fr>%s</fr>" % fr,
        "        </text>",
    ])


t = io.open(PFAD, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in t else "\n"

for schluessel, de, en, fr, nach in TEXTE:
    for sp, wert in (("de", de), ("en", en), ("fr", fr)):
        assert "&" not in wert and "<" not in wert, (schluessel, sp)
        assert " - " not in wert and "—" not in wert and "–" not in wert, (schluessel, sp)
    neu = block(schluessel, de, en, fr, nl)
    muster = re.compile(r'[ \t]*<text name="%s">.*?</text>' % re.escape(schluessel), re.S)
    treffer = muster.findall(t)
    if len(treffer) == 1:
        t = muster.sub(lambda m: neu, t)
        print("ersetzt   ", schluessel)
        continue
    assert len(treffer) == 0, schluessel
    vor = re.compile(r'[ \t]*<text name="%s">.*?</text>' % re.escape(nach), re.S)
    m = vor.search(t)
    assert m is not None, nach
    t = t[:m.end()] + nl + neu + t[m.end():]
    print("angelegt  ", schluessel)

for schluessel in ENTFERNEN:
    muster = re.compile(r'[ \t]*<text name="%s">.*?</text>\r?\n' % re.escape(schluessel), re.S)
    t, n = muster.subn("", t)
    print("entfernt  " if n else "fehlte    ", schluessel)

for alt, neu in BESCHREIBUNG:
    if neu in t:
        print("Beschreibung schon neu:", neu[:40])
        continue
    assert t.count(alt) == 1, alt[:40]
    t = t.replace(alt, neu)
    print("Beschreibung geaendert:", neu[:40])

io.open(PFAD, "w", encoding="utf-8", newline="").write(t)
