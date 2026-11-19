"""Uebernimmt umgeschriebene Hilfetexte (JSON: {schluessel: {de, en, fr}}) in die modDesc.

Vorher wird je Schluessel und Sprache geprueft, dass Zahlen, Konsolenbefehle,
Tasten und Einstellungsnamen des alten Textes auch im neuen stehen. Fehlt etwas,
wird nichts geschrieben.

Aufruf:  py _hilfe_1100.py [--schreiben] datei.json [datei.json ...]
"""
import io
import json
import os
import re
import sys

BASIS = os.path.dirname(os.path.abspath(__file__))
PFAD = os.path.join(BASIS, "modDesc.xml")
SPRACHEN = ("de", "en", "fr")

# Hier aendert sich der Inhalt mit 1.1.0.0, fehlende Begriffe sind dort gewollt
ERLAUBT_FEHLEND = {
    "ao_help_prod": {"de": set(), "en": set(), "fr": set()},
}

ZAHL = re.compile(r"\d+(?:[.,   ]\d+)*")
WORT = re.compile(r"\b(?:[a-z]+[A-Z][A-Za-z]*|ao[A-Z]\w*|hl[A-Z]\w*|fs[A-Z]\w*|ro[A-Z]\w*)\b")
TASTE = re.compile(r"\b(?:Alt|Strg|Ctrl)\+[A-Z]\b")
DATEI = re.compile(r"[\w/]+\.(?:xml|csv|html)\b|\.(?:xml|csv|html)\b")


def merkmale(text):
    zahlen = {re.sub(r"[.,   ]", "", z) for z in ZAHL.findall(text)}
    return zahlen | set(WORT.findall(text)) | set(TASTE.findall(text)) | set(DATEI.findall(text))


def alter_text(t, schluessel, sp):
    m = re.search(r'<text name="%s">(.*?)</text>' % re.escape(schluessel), t, re.S)
    assert m is not None, schluessel
    s = re.search(r"<%s>(.*?)</%s>" % (sp, sp), m.group(1), re.S)
    assert s is not None, (schluessel, sp)
    return s.group(1)


schreiben = "--schreiben" in sys.argv
dateien = [a for a in sys.argv[1:] if a != "--schreiben"]
neu = {}
for d in dateien:
    neu.update(json.load(io.open(d, encoding="utf-8")))

t = io.open(PFAD, encoding="utf-8", newline="").read()
probleme = 0
for schluessel, texte in sorted(neu.items()):
    for sp in SPRACHEN:
        wert = texte.get(sp)
        if not wert:
            print("FEHLT     %s/%s" % (schluessel, sp))
            probleme += 1
            continue
        for zeichen in ("&", "<", " - ", "—", "–"):
            if zeichen in wert:
                print("ZEICHEN   %s/%s enthaelt %r" % (schluessel, sp, zeichen))
                probleme += 1
        alt = alter_text(t, schluessel, sp)
        fehlend = merkmale(alt) - merkmale(wert)
        fehlend -= ERLAUBT_FEHLEND.get(schluessel, {}).get(sp, set())
        if fehlend:
            print("INHALT    %s/%s fehlt: %s" % (schluessel, sp, ", ".join(sorted(fehlend))))
            probleme += 1
        laenge = len(wert) / max(1, len(alt))
        if laenge < 0.6 or laenge > 1.5:
            print("LAENGE    %s/%s %d -> %d Zeichen" % (schluessel, sp, len(alt), len(wert)))

print("%d Schluessel, %d Probleme" % (len(neu), probleme))
if probleme or not schreiben:
    sys.exit(1 if probleme else 0)

for schluessel, texte in neu.items():
    block = re.compile(r'(<text name="%s">)(.*?)(</text>)' % re.escape(schluessel), re.S)
    m = block.search(t)
    inhalt = m.group(2)
    for sp in SPRACHEN:
        inhalt = re.sub(r"(<%s>).*?(</%s>)" % (sp, sp),
                        lambda x, w=texte[sp]: x.group(1) + w + x.group(2), inhalt, count=1, flags=re.S)
    t = t[:m.start(2)] + inhalt + t[m.end(2):]

io.open(PFAD, "w", encoding="utf-8", newline="").write(t)
print("geschrieben:", PFAD)
