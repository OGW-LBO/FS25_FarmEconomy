"""Nimmt die Reiter anderer Mods (Waypoints, Yield Factor, Barn Capacity)
aus dem Einstellungs-Screenshot. GIANTS-Pruefung vom 12.11.2026.
Der Farm-Economy-Reiter rueckt direkt hinter DEVICES, so wie es ohne
die anderen Mods im Spiel aussieht."""
import sys
from PIL import Image

QUELLE = r"C:\Users\Admin\Downloads\ModHub\FS25_FarmEconomy\screenshots\02_einstellungen_1.png"
ZIEL = sys.argv[1]

bild = Image.open(QUELLE).convert("RGB")
OBEN, UNTEN = 160, 214

# Grenzen des gruenen Reiters in der Zeile y=180, nur im Bereich um 1300
def gruen(p):
    return p[1] > 120 and p[0] < 140 and p[2] < 100

x = 1300
while gruen(bild.getpixel((x - 1, 180))):
    x -= 1
links = x
x = 1300
while gruen(bild.getpixel((x + 1, 180))):
    x += 1
rechts = x
print("Reiter", links, rechts)

reiter = bild.crop((links, OBEN, rechts + 1, UNTEN))
mit_linie = bild.crop((600, OBEN, 601, UNTEN))     # Spalte mit Trennlinie
ohne_linie = bild.crop((1530, OBEN, 1531, UNTEN))  # Spalte ohne Linie und Text

# Linienende ermitteln (letzte Spalte, in der y=211 gruen ist, rechts vom Reiter)
ende = rechts
while ende < 1540 and gruen(bild.getpixel((ende + 1, 211))):
    ende += 1
print("Linie endet bei", ende)

# alles ab WAYPOINTS bis vor den rechten Pfeil leeren
for spalte in range(975, 1545):
    bild.paste(mit_linie if spalte <= ende else ohne_linie, (spalte, OBEN))

# Reiter so setzen, dass der Text bei x=991 beginnt wie zuvor WAYPOINTS
# Textbeginn im Reiter: dunkle Schrift auf Gruen
text_links = None
for spalte in range(reiter.width):
    if any(sum(reiter.getpixel((spalte, y - OBEN))) < 250 for y in range(180, 197)):
        text_links = spalte
        break
neu_x = 991 - text_links
bild.paste(reiter, (neu_x, OBEN))
print("Reiter neu bei", neu_x, "Textabstand", text_links)
bild.save(ZIEL)
