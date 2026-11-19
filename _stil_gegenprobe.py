"""Gegenprobe fuer die Kommentar-Ueberarbeitung.

Vergleicht je Lua-Datei die ausfuehrbaren Zeilen zwischen dem getesteten Stand
(Codex\\AgrarOekonomie) und dieser Arbeitskopie. Kommentare und Leerzeilen
fallen heraus, alles andere muss zeichengleich sein (ausser Leerraum am
Zeilenende). Aufruf:  py _stil_gegenprobe.py [Datei.lua ...]
"""
import glob
import io
import os
import sys

ALT = r"C:\Users\Admin\Downloads\Codex\AgrarOekonomie"
NEU = os.path.dirname(os.path.abspath(__file__))


def code_zeilen(text):
    if "--[[" in text or "--[=" in text:
        raise SystemExit("Blockkommentar gefunden - bitte nur Zeilenkommentare verwenden")
    zeilen = []
    for zeile in text.splitlines():
        rein = []
        i, n = 0, len(zeile)
        quote = None
        while i < n:
            c = zeile[i]
            if quote:
                rein.append(c)
                if c == "\\" and i + 1 < n:
                    rein.append(zeile[i + 1])
                    i += 2
                    continue
                if c == quote:
                    quote = None
            else:
                if c in "\"'":
                    quote = c
                    rein.append(c)
                elif zeile.startswith("--", i):
                    break
                else:
                    rein.append(c)
            i += 1
        code = "".join(rein).rstrip()
        if code.strip():
            zeilen.append(code)
    return zeilen


dateien = sys.argv[1:] or sorted(os.path.basename(p) for p in glob.glob(os.path.join(ALT, "*.lua")))
fehler = 0
for name in dateien:
    a = code_zeilen(io.open(os.path.join(ALT, name), encoding="utf-8").read())
    b = code_zeilen(io.open(os.path.join(NEU, name), encoding="utf-8").read())
    if a == b:
        print("OK      %-34s %5d Codezeilen" % (name, len(a)))
        continue
    fehler += 1
    print("ABWEICHUNG %s (%d -> %d Codezeilen)" % (name, len(a), len(b)))
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else "<fehlt>"
        y = b[i] if i < len(b) else "<fehlt>"
        if x != y:
            print("   alt: %s\n   neu: %s" % (x.strip()[:140], y.strip()[:140]))
            break
print("%d Datei(en) mit Abweichung" % fehler)
sys.exit(1 if fehler else 0)
