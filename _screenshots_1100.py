"""Schneidet die 32:9-Aufnahmen auf ModHub-Format 1600x900 zu."""
import os
from PIL import Image

QUELLE = r"C:\Users\Admin\Videos\Farming Simulator 25"
ZIEL = r"C:\Users\Admin\Downloads\ModHub\FS25_FarmEconomy\screenshots_1100"

# Datei, Mittelpunkt x/y im Original (5120x1440), Ausschnittbreite, Zielname
BILDER = [
    ("Farming Simulator 25 Screenshot 2026.11.03 - 12.19.43.85.png", 2551, 703, 1920, "07_cashbook.png"),
    ("Farming Simulator 25 Screenshot 2026.11.02 - 18.44.11.17.png", 2217, 850, 1900, "08_settings_cashbook_running_costs.png"),
]

os.makedirs(ZIEL, exist_ok=True)
for datei, mx, my, breite, name in BILDER:
    if not os.path.exists(os.path.join(QUELLE, datei)):
        print(name, "uebersprungen, Aufnahme nicht mehr da")
        continue
    bild = Image.open(os.path.join(QUELLE, datei)).convert("RGB")
    hoehe = breite * 9 // 16
    links = max(0, min(bild.width - breite, mx - breite // 2))
    oben = max(0, min(bild.height - hoehe, my - hoehe // 2))
    aus = bild.crop((links, oben, links + breite, oben + hoehe)).resize((1600, 900), Image.LANCZOS)
    aus.save(os.path.join(ZIEL, name))
    print(name, aus.size)
