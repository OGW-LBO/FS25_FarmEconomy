"""Malt den Monitor fuer den Hof-PC und speichert ihn als images/hofpc.dds.
Masse in Fenster-Pixeln (1600 x 900), gerechnet wird doppelt so fein und
danach verkleinert. Die Lage von Bildschirm, Titel- und Programmleiste muss
zu _hofpc_xml.py passen."""
import os

from PIL import Image, ImageDraw, ImageFilter

BASIS = os.path.dirname(os.path.abspath(__file__))
ZIEL = os.path.join(BASIS, "images", "hofpc.dds")
VORSCHAU = os.path.join(BASIS, "_hofpc_vorschau.png")

B, H = 1600, 900
S = 2

GEHAEUSE = (0, 0, 1600, 800)
SCHIRM = (26, 26, 1574, 754)
TITEL_UNTEN = 66
LEISTE_UNTEN = 114


def k(*werte):
    return tuple(int(round(w * S)) for w in werte)


def verlauf(breite, hoehe, oben, unten):
    bild = Image.new("RGBA", (breite, hoehe))
    zeichner = ImageDraw.Draw(bild)
    for y in range(hoehe):
        t = y / max(1, hoehe - 1)
        farbe = tuple(int(oben[i] + (unten[i] - oben[i]) * t) for i in range(4))
        zeichner.line([(0, y), (breite, y)], fill=farbe)
    return bild


def maske_rund(breite, hoehe, radius):
    m = Image.new("L", (breite, hoehe), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, breite - 1, hoehe - 1], radius=radius, fill=255)
    return m


def einsetzen(bild, teil, x, y, maske=None):
    bild.alpha_composite(teil if maske is None else Image.composite(teil, Image.new("RGBA", teil.size), maske),
                         (x, y))


def main():
    bild = Image.new("RGBA", (B * S, H * S), (0, 0, 0, 0))

    schatten = Image.new("RGBA", bild.size, (0, 0, 0, 0))
    ImageDraw.Draw(schatten).rounded_rectangle(k(14, 18, 1586, 808), radius=30 * S, fill=(0, 0, 0, 150))
    ImageDraw.Draw(schatten).ellipse(k(520, 868, 1080, 900), fill=(0, 0, 0, 120))
    bild.alpha_composite(schatten.filter(ImageFilter.GaussianBlur(14 * S)))

    fuss = verlauf(*k(460, 26), (58, 63, 70, 255), (28, 31, 35, 255))
    einsetzen(bild, fuss, *k(570, 864), maske_rund(*k(460, 26), 13 * S))
    hals = Image.new("RGBA", k(120, 70), (0, 0, 0, 0))
    ImageDraw.Draw(hals).polygon([k(10, 0), k(110, 0), k(120, 70), k(0, 70)], fill=(40, 44, 49, 255))
    einsetzen(bild, hals, *k(740, 796))
    ImageDraw.Draw(bild).line([k(752, 800), k(744, 864)], fill=(70, 76, 84, 255), width=2 * S)

    x0, y0, x1, y1 = GEHAEUSE
    gehaeuse = verlauf(*k(x1 - x0, y1 - y0), (46, 51, 58, 255), (24, 27, 31, 255))
    einsetzen(bild, gehaeuse, *k(x0, y0), maske_rund(*k(x1 - x0, y1 - y0), 26 * S))
    z = ImageDraw.Draw(bild)
    z.rounded_rectangle(k(x0, y0, x1 - 1, y1 - 1), radius=26 * S, outline=(12, 13, 15, 255), width=2 * S)
    z.rounded_rectangle(k(x0 + 3, y0 + 3, x1 - 4, y1 - 4), radius=24 * S, outline=(74, 80, 88, 255), width=1 * S)

    sx0, sy0, sx1, sy1 = SCHIRM
    z.rounded_rectangle(k(sx0 - 3, sy0 - 3, sx1 + 3, sy1 + 3), radius=8 * S, fill=(6, 7, 8, 255))
    schirm = verlauf(*k(sx1 - sx0, sy1 - sy0), (24, 40, 58, 255), (13, 22, 33, 255))
    zs = ImageDraw.Draw(schirm)
    zs.rectangle(k(0, 0, sx1 - sx0, TITEL_UNTEN - sy0), fill=(10, 18, 28, 255))
    zs.rectangle(k(0, TITEL_UNTEN - sy0, sx1 - sx0, TITEL_UNTEN - sy0 + 1), fill=(96, 168, 74, 255))
    zs.rectangle(k(0, TITEL_UNTEN - sy0 + 2, sx1 - sx0, LEISTE_UNTEN - sy0), fill=(17, 30, 44, 255))
    zs.rectangle(k(0, LEISTE_UNTEN - sy0, sx1 - sx0, LEISTE_UNTEN - sy0 + 1), fill=(38, 58, 80, 255))
    zs.ellipse(k(14, 9, 36, 31), fill=(96, 168, 74, 255))
    zs.polygon([k(19, 25), k(25, 13), k(31, 25)], fill=(10, 18, 28, 255))

    glanz = Image.new("RGBA", schirm.size, (0, 0, 0, 0))
    ImageDraw.Draw(glanz).polygon([k(0, 0), k(620, 0), k(260, sy1 - sy0), k(0, sy1 - sy0)],
                                  fill=(255, 255, 255, 9))
    schirm.alpha_composite(glanz.filter(ImageFilter.GaussianBlur(40 * S)))
    einsetzen(bild, schirm, *k(sx0, sy0), maske_rund(*k(sx1 - sx0, sy1 - sy0), 6 * S))

    z = ImageDraw.Draw(bild)
    z.ellipse(k(1536, 772, 1546, 782), fill=(90, 200, 90, 255))
    z.ellipse(k(1533, 769, 1549, 785), outline=(20, 60, 20, 255), width=1 * S)
    for i, x in enumerate((1490, 1462, 1434)):
        z.ellipse(k(x, 772, x + 10, 782), fill=(34, 37, 41, 255), outline=(70, 76, 84, 255), width=1 * S)
    z.rounded_rectangle(k(760, 772, 840, 782), radius=5 * S, fill=(34, 37, 41, 255))

    klein = bild.resize((B, H), Image.LANCZOS)
    klein.save(VORSCHAU)
    textur = klein.resize((2048, 1024), Image.LANCZOS)
    textur.save(ZIEL, pixel_format="DXT5")
    print("geschrieben:", ZIEL, os.path.getsize(ZIEL), "Bytes")


if __name__ == "__main__":
    main()
