"""Pfeile fuer die Scrollleisten im Hof-PC (images/pfeil_hoch.dds, pfeil_runter.dds)."""
import os
from PIL import Image, ImageDraw

BASIS = os.path.dirname(os.path.abspath(__file__))
GROESSE = 64
FAKTOR = 4


def pfeil(nach_oben):
    gross = GROESSE * FAKTOR
    bild = Image.new("RGBA", (gross, gross), (255, 255, 255, 0))
    zeichnen = ImageDraw.Draw(bild)
    rand = 12 * FAKTOR
    if nach_oben:
        punkte = [(gross / 2, rand), (gross - rand, gross - rand * 1.6), (rand, gross - rand * 1.6)]
    else:
        punkte = [(gross / 2, gross - rand), (gross - rand, rand * 1.6), (rand, rand * 1.6)]
    zeichnen.polygon(punkte, fill=(255, 255, 255, 255))
    return bild.resize((GROESSE, GROESSE), Image.LANCZOS)


def main():
    for name, oben in (("pfeil_hoch", True), ("pfeil_runter", False)):
        ziel = os.path.join(BASIS, "images", name + ".dds")
        pfeil(oben).save(ziel, pixel_format="DXT5")
        print("geschrieben:", ziel)


if __name__ == "__main__":
    main()
