"""Neue und geaenderte l10n-Texte fuer 1.1.0.0 (Bremse anteilig, Kosten-Auswahl).
Laeuft mehrfach ohne Schaden: vorhandene Schluessel werden ersetzt, fehlende angelegt."""
import io
import os
import re

BASIS = os.path.dirname(os.path.abspath(__file__))
PFAD = os.path.join(BASIS, "modDesc.xml")

# (schluessel, de, en, fr, einfuegen_nach)
TEXTE = [
    ("ao_ui_prodKosten",
     "Laufende Kosten",
     "Running costs",
     "Frais de fonctionnement",
     None),
    ("ao_ui_prodKosten_t",
     "Was eine schnellere Produktion pro Stunde kostet. Voll mit: Kosten je Stück bleiben gleich. Wurzel: bei x4 doppelte Kosten, schneller wird also günstiger je Stück. Gleich bleibend: Kosten pro Stunde wie im Spiel.",
     "What a faster production costs per hour. Full: the cost per unit stays the same. Square root: x4 speed costs twice as much, so speeding up makes each unit cheaper. Unchanged: hourly costs as in the base game.",
     "Ce que coûte une production accélérée par heure. Plein : le coût par unité ne bouge pas. Racine : à x4, les frais doublent seulement, chaque unité revient donc moins cher. Inchangés : frais horaires du jeu de base.",
     None),
    ("ao_opt_kostenGleich",
     "gleich bleibend",
     "unchanged",
     "inchangés",
     "ao_ui_prodKosten_t"),
    ("ao_opt_kostenWurzel",
     "Wurzel des Faktors",
     "square root",
     "racine du facteur",
     "ao_opt_kostenGleich"),
    ("ao_opt_kostenVoll",
     "voll mit",
     "full",
     "plein",
     "ao_opt_kostenWurzel"),
    ("ao_msg_bremseDeckel",
     "Sicherheitsbremse: %s erlassen, das Tagesbudget war aufgebraucht",
     "Safety brake: %s waived, today's budget was used up",
     "Frein de sécurité : %s non prélevés, le budget du jour était épuisé",
     "ao_msg_grundsteuer"),
    ("ao_msg_bremseKonto",
     "Sicherheitsbremse: %s erlassen, das Konto steht an der Untergrenze",
     "Safety brake: %s waived, your balance is at the minimum",
     "Frein de sécurité : %s non prélevés, le solde est au minimum",
     "ao_msg_bremseDeckel"),
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
    muster = re.compile(r'        <text name="%s">.*?</text>' % re.escape(schluessel), re.S)
    treffer = muster.findall(t)
    if len(treffer) == 1:
        t = muster.sub(lambda m: neu, t)
        print("ersetzt   ", schluessel)
        continue
    assert len(treffer) == 0, schluessel
    anker = re.compile(r'(        <text name="%s">.*?</text>)' % re.escape(nach), re.S)
    assert len(anker.findall(t)) == 1, nach
    t = anker.sub(lambda m: m.group(1) + nl + neu, t)
    print("angelegt  ", schluessel)

io.open(PFAD, "w", encoding="utf-8", newline="").write(t)
