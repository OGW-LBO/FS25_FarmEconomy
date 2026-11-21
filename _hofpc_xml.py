"""Erzeugt gui/AOHofPC.xml, das Fenster des Hof-PCs.
Alle Lagen in Fenster-Pixeln (1600 x 900) von oben links, wie in
_hofpc_bild.py. Mit anchorTopLeft ist y die Oberkante des Elements, nach
unten negativ."""
import os
import xml.dom.minidom

BASIS = os.path.dirname(os.path.abspath(__file__))
ZIEL = os.path.join(BASIS, "gui", "AOHofPC.xml")

GRAU = "0.62 0.62 0.62 1"
HELL = "0.88 0.92 0.96 1"
FLAECHE = "1 1 1 0.045"
STREIFEN = "1 1 1 0.03"

SEITEN = 5
TAB_X, TAB_TOP, TAB_B, TAB_H, TAB_SCHRITT = 40, 72, 236, 38, 246

zeilen = []
flaechen = [0]
ids = set()


def merke(i):
    if i is None:
        return ""
    if i in ids:
        raise SystemExit("doppelte id " + i)
    ids.add(i)
    return ' id="%s"' % i


def lage(x, top, b, h):
    return 'position="%dpx %dpx" size="%dpx %dpx"' % (x, -top, b, h)


def text(x, top, b, h, groesse=15, id=None, l10n=None, rechts=False, mitte=False, fett=False,
         farbe=None, zeilen_max=None):
    a = ['<Text profile="aoPcText"', merke(id), " ", lage(x, top, b, h), ' textSize="%dpx"' % groesse]
    if rechts:
        a.append(' textAlignment="right"')
    if mitte:
        a.append(' textAlignment="center"')
    if fett:
        a.append(' textBold="true"')
    if farbe:
        a.append(' textColor="%s"' % farbe)
    if zeilen_max:
        a.append(' textMaxNumLines="%d"' % zeilen_max)
    if l10n:
        a.append(' text="$l10n_%s"' % l10n)
    a.append(" />")
    zeilen.append("".join(a))


def flaeche(x, top, b, h, farbe=FLAECHE, id=None):
    if id is None:
        flaechen[0] += 1
        id = "fl%d" % flaechen[0]
    zeilen.append('<Bitmap profile="aoPcFlaeche"%s %s imageColor="%s" />' % (merke(id), lage(x, top, b, h), farbe))


def bild(x, top, b, h, id):
    zeilen.append('<Bitmap profile="aoPcBild"%s %s />' % (merke(id), lage(x, top, b, h)))


def knopf(x, top, b, h, id, klick, l10n=None, profil="aoPcZeile"):
    t = ' text="$l10n_%s"' % l10n if l10n else ""
    zeilen.append('<Button profile="%s"%s %s onClick="%s"%s />' % (profil, merke(id), lage(x, top, b, h), klick, t))


def rollleiste(praefix, x, top, unten):
    zeilen.append('<Bitmap profile="aoPcFlaeche"%s %s imageColor="1 1 1 0.06" />'
                  % (merke(praefix + "Bahn"), lage(x + 3, top + 16, 6, unten - top - 32)))
    zeilen.append('<Bitmap profile="aoPcFlaeche"%s %s imageColor="0.376 0.659 0.290 1" />'
                  % (merke(praefix + "Griff"), lage(x + 3, top + 16, 6, unten - top - 32)))
    zeilen.append('<Bitmap profile="aoPcPfeilHoch"%s %s imageColor="0.75 0.8 0.85 1" />'
                  % (merke(praefix + "Hoch"), lage(x, top, 12, 12)))
    zeilen.append('<Bitmap profile="aoPcPfeilRunter"%s %s imageColor="0.75 0.8 0.85 1" />'
                  % (merke(praefix + "Runter"), lage(x, unten - 12, 12, 12)))
    knopf(x - 4, top - 4, 20, 20, praefix + "KnopfHoch", "onClickRollHoch")
    knopf(x - 4, unten - 16, 20, 20, praefix + "KnopfRunter", "onClickRollRunter")


def auswahl(x, top, id, klick, l10n):
    zeilen.append('<GuiElement profile="aoPcOptZeile" position="%dpx %dpx">' % (x, -top))
    zeilen.append('    <MultiTextOption profile="fs25_settingsMultiTextOption" onClick="%s"%s />' % (klick, merke(id)))
    zeilen.append('    <Text profile="fs25_settingsMultiTextOptionTitle" text="$l10n_%s" />' % l10n)
    zeilen.append("</GuiElement>")


def karte(x0, top, x1, unten, titel=None):
    flaeche(x0, top, x1 - x0, unten - top)
    if titel:
        text(x0 + 16, top + 8, x1 - x0 - 32, 24, 17, l10n=titel, fett=True)


def seite_auf(nr):
    zeilen.append('<GuiElement profile="aoPcSeite"%s position="0px 0px" size="1600px 900px">' % merke("seite%d" % nr))


def seite_zu():
    zeilen.append("</GuiElement>")


def start():
    seite_auf(1)
    for i in range(1, 5):
        x = 44 + (i - 1) * 380
        flaeche(x, 132, 364, 86)
        text(x + 16, 140, 332, 20, 15, id="stLab%d" % i, farbe=GRAU)
        text(x + 16, 162, 332, 32, 26, id="stWert%d" % i, fett=True)
        text(x + 16, 196, 332, 18, 13, id="stSub%d" % i, farbe=GRAU)

    karte(44, 234, 790, 520, "ao_pc_stVermoegen")
    for i in range(1, 6):
        top = 282 + (i - 1) * 44
        text(60, top, 200, 30, 15, id="stVLab%d" % i)
        flaeche(270, top + 7, 330, 16, "1 1 1 0.06")
        flaeche(270, top + 7, 330, 16, "0.165 0.471 0.839 1", id="stVBalken%d" % i)
        text(610, top, 165, 30, 15, id="stVWert%d" % i, rechts=True)

    karte(806, 234, 1556, 520, "ao_pc_stBlick")
    for i in range(1, 9):
        top = 278 + (i - 1) * 30
        text(822, top, 380, 26, 15, id="stBLab%d" % i, farbe=GRAU)
        text(1206, top, 335, 26, 15, id="stBWert%d" % i, rechts=True)

    karte(44, 536, 1556, 744, "ao_pc_stVerlauf")
    flaeche(1180, 550, 14, 14, "0.165 0.471 0.839 1")
    text(1200, 545, 150, 24, 13, l10n="ao_buch_ein", farbe=GRAU)
    flaeche(1360, 550, 14, 14, "0.922 0.408 0.204 1")
    text(1380, 545, 160, 24, 13, l10n="ao_buch_aus", farbe=GRAU)
    flaeche(60, 712, 1480, 1, "1 1 1 0.12")
    for k in range(1, 7):
        x0 = 70 + (k - 1) * 248
        flaeche(x0 + 64, 582, 50, 130, "0.165 0.471 0.839 1", id="stEin%d" % k)
        flaeche(x0 + 120, 582, 50, 130, "0.922 0.408 0.204 1", id="stAus%d" % k)
        text(x0, 716, 234, 24, 14, id="stMon%d" % k, mitte=True)
    seite_zu()


def kasse():
    seite_auf(2)
    auswahl(44, 126, "kbOptAnsicht", "onClickKbAnsicht", "ao_buch_ansicht")
    auswahl(700, 126, "kbOptZeitraum", "onClickKbZeitraum", "ao_buch_zeitraum")
    for i in range(1, 5):
        x = 44 + (i - 1) * 380
        flaeche(x, 172, 364, 76)
        text(x + 16, 180, 332, 20, 15, id="kbLab%d" % i, farbe=GRAU)
        text(x + 16, 204, 332, 32, 26, id="kbWert%d" % i, fett=True)

    karte(44, 262, 790, 690, "ao_buch_weg")
    for i in range(1, 9):
        top = 306 + (i - 1) * 46
        text(60, top, 240, 30, 15, id="kbRangLab%d" % i, rechts=True)
        flaeche(312, top + 6, 300, 18, "0.165 0.471 0.839 1", id="kbRangBalken%d" % i)
        text(620, top, 155, 30, 15, id="kbRangWert%d" % i, rechts=True)

    karte(806, 262, 1556, 690, "ao_buch_letzte")
    for i in range(1, 13):
        top = 302 + (i - 1) * 32
        if i % 2 == 0:
            flaeche(814, top, 734, 26, STREIFEN)
        text(822, top, 190, 26, 14, id="kbZeit%d" % i, farbe=GRAU)
        text(1016, top, 330, 26, 14, id="kbText%d" % i)
        text(1340, top, 190, 26, 14, id="kbBetrag%d" % i, rechts=True)

    rollleiste("kbRoll", 1540, 302, 680)
    text(44, 702, 1512, 30, 14, id="kbFuss", farbe=GRAU)
    seite_zu()


def fuhrpark():
    seite_auf(3)
    auswahl(44, 122, "fpOptZeitraum", "onClickFpZeitraum", "ao_mk_zeitraum")
    auswahl(700, 122, "fpOptSort", "onClickFpSort", "ao_mk_sortieren")
    auswahl(44, 158, "fpOptZeigen", "onClickFpZeigen", "ao_mk_zeigen")
    auswahl(700, 158, "fpOptSeite", "onClickFpSeite", "ao_mk_seite")

    for i in range(1, 6):
        x = 44 + (i - 1) * 303
        flaeche(x, 200, 290, 70)
        text(x + 14, 206, 262, 18, 14, id="fpKLab%d" % i, farbe=GRAU)
        text(x + 14, 224, 262, 28, 22, id="fpKWert%d" % i, fett=True)
        text(x + 14, 252, 262, 16, 12, id="fpKSub%d" % i, farbe=GRAU)

    karte(44, 282, 1082, 744)
    text(100, 288, 240, 22, 13, l10n="ao_mk_hName", farbe=GRAU)
    text(350, 288, 70, 22, 13, l10n="ao_mk_hStd", farbe=GRAU, rechts=True)
    text(432, 288, 300, 22, 13, l10n="ao_mk_hKosten", farbe=GRAU)
    text(740, 288, 110, 22, 13, l10n="ao_mk_hSumme", farbe=GRAU, rechts=True)
    text(855, 288, 90, 22, 13, l10n="ao_mk_hEh", farbe=GRAU, rechts=True)
    text(965, 288, 105, 22, 13, l10n="ao_mk_hZustand", farbe=GRAU)
    for i in range(1, 11):
        top = 314 + (i - 1) * 36
        if i % 2 == 0:
            flaeche(48, top, 1030, 34, STREIFEN)
        flaeche(48, top, 5, 34, "0.376 0.659 0.290 1", id="fpMarke%d" % i)
        bild(58, top, 34, 34, "fpBild%d" % i)
        text(100, top, 245, 34, 15, id="fpName%d" % i)
        text(350, top, 70, 34, 15, id="fpStd%d" % i, rechts=True)
        for s in range(1, 6):
            flaeche(432, top + 10, 300, 14, "1 1 1 1", id="fpSeg%d_%d" % (i, s))
        text(740, top, 110, 34, 15, id="fpSumme%d" % i, rechts=True)
        text(855, top, 90, 34, 15, id="fpEh%d" % i, rechts=True)
        flaeche(965, top + 12, 100, 10, "1 1 1 0.12", id="fpZustGrund%d" % i)
        flaeche(965, top + 12, 100, 10, "0.4 0.8 0.3 1", id="fpZust%d" % i)
        knopf(44, top, 1020, 34, "fpZeile%d" % i, "onClickFpZeile")
    rollleiste("fpRoll", 1066, 314, 672)

    farben = ["0.545 0.361 0.839 1", "0.922 0.533 0.204 1", "0.165 0.471 0.839 1",
              "0.141 0.651 0.620 1", "0.851 0.678 0.161 1"]
    for k in range(1, 6):
        x = 60 + (k - 1) * 200
        flaeche(x, 696, 14, 14, farben[k - 1], id="fpLegF%d" % k)
        text(x + 20, 692, 170, 22, 13, id="fpLegT%d" % k, farbe=GRAU)
    text(60, 716, 1010, 24, 13, id="fpFuss", farbe=GRAU)

    karte(1098, 282, 1556, 744)
    bild(1112, 294, 110, 110, "fpDBild")
    text(1234, 296, 310, 26, 18, id="fpDName", fett=True)
    text(1234, 326, 310, 22, 14, id="fpDStatus", farbe=GRAU)
    text(1234, 350, 310, 44, 13, id="fpDSub", farbe=GRAU, zeilen_max=2)
    for k in range(1, 14):
        top = 416 + (k - 1) * 24
        text(1112, top, 220, 22, 14, id="fpDLab%d" % k, farbe=GRAU)
        text(1330, top, 214, 22, 14, id="fpDWert%d" % k, rechts=True)
    seite_zu()


def abgaben():
    seite_auf(4)
    karte(44, 126, 900, 744, "ao_pc_abTitel")
    text(60, 170, 300, 22, 13, l10n="ao_pc_abPosten", farbe=GRAU)
    text(370, 170, 170, 22, 13, l10n="ao_pc_abNaechste", farbe=GRAU, rechts=True)
    text(550, 170, 160, 22, 13, l10n="ao_pc_abJahr", farbe=GRAU, rechts=True)
    text(720, 170, 160, 22, 13, l10n="ao_pc_abVorjahr", farbe=GRAU, rechts=True)
    for r in range(1, 8):
        top = 198 + (r - 1) * 32
        if r % 2 == 0:
            flaeche(52, top, 840, 28, STREIFEN)
        text(60, top, 300, 28, 15, id="abP%d" % r)
        text(370, top, 170, 28, 15, id="abN%d" % r, rechts=True)
        text(550, top, 160, 28, 15, id="abJ%d" % r, rechts=True)
        text(720, top, 160, 28, 15, id="abV%d" % r, rechts=True)
    text(60, 436, 820, 24, 15, l10n="ao_pc_abGrundlagen", fett=True)
    for k in range(1, 9):
        top = 464 + (k - 1) * 30
        text(60, top, 330, 26, 14, id="abIL%d" % k, farbe=GRAU)
        text(400, top, 480, 26, 14, id="abIW%d" % k, rechts=True)
    text(60, 712, 830, 26, 13, id="abFuss", farbe=GRAU)

    karte(916, 126, 1556, 744, "ao_pc_abHelfer")
    for k in range(1, 8):
        top = 168 + (k - 1) * 30
        text(932, top, 300, 26, 14, id="abHL%d" % k, farbe=GRAU)
        text(1236, top, 305, 26, 14, id="abHW%d" % k, rechts=True)
    text(932, 392, 610, 24, 17, l10n="ao_pc_abBremse", fett=True)
    for k in range(8, 16):
        top = 426 + (k - 8) * 30
        text(932, top, 300, 26, 14, id="abHL%d" % k, farbe=GRAU)
        text(1236, top, 305, 26, 14, id="abHW%d" % k, rechts=True)
    flaeche(932, 680, 610, 14, "1 1 1 0.12", id="abBremseGrund")
    flaeche(932, 680, 610, 14, "0.165 0.471 0.839 1", id="abBremse")
    text(932, 700, 610, 30, 13, id="abBremseText", farbe=GRAU)
    seite_zu()


def overview():
    seite_auf(5)
    auswahl(44, 124, "foOptBereich", "onClickFoBereich", "ao_pc_foBereich")
    auswahl(700, 124, "foOptSeite", "onClickFoSeite", "ao_mk_seite")
    karte(44, 168, 1556, 744)
    spalten = [(60, 450, False), (515, 150, True), (680, 150, True), (850, 280, False),
               (1140, 250, False), (1400, 140, False)]
    for n, (x, b, r) in enumerate(spalten, 1):
        text(x, 174, b, 24, 13, id="foH%d" % n, rechts=r, farbe=GRAU)
    for j in range(1, 17):
        top = 202 + (j - 1) * 30
        if j % 2 == 0:
            flaeche(52, top, 1496, 28, STREIFEN)
        for n, (x, b, r) in enumerate(spalten, 1):
            text(x, top, b, 28, 15, id="fo%s%d" % ("ABCDEF"[n - 1], j), rechts=r)
        text(60, top, 1480, 28, 15, id="foS%d" % j, fett=True)
        knopf(52, top, 1480, 28, "foZeile%d" % j, "onClickFoZeile")
        knopf(1400, top, 132, 28, "foOeffnen%d" % j, "onClickFoOeffnen")
    rollleiste("foRoll", 1540, 202, 680)
    text(60, 400, 1480, 30, 16, id="foLeer", mitte=True, farbe=GRAU)
    text(60, 690, 1480, 44, 13, id="foFuss", farbe=GRAU, zeilen_max=2)
    seite_zu()


def main():
    zeilen.append('<Bitmap profile="aoPcBild" id="pcBild" position="0px 0px" size="1600px 900px" />')
    ids.add("pcBild")
    text(74, 28, 140, 36, 19, id="pcTitel", fett=True, l10n="ao_pc_titel")
    text(214, 28, 700, 36, 15, id="pcHof", farbe=GRAU)
    text(960, 28, 600, 36, 15, id="pcUhr", rechts=True, farbe=HELL)
    for i in range(1, SEITEN + 1):
        x = TAB_X + (i - 1) * TAB_SCHRITT
        flaeche(x, TAB_TOP, TAB_B, TAB_H, "1 1 1 0.05", id="tabBg%d" % i)
        flaeche(x, TAB_TOP + TAB_H - 3, TAB_B, 3, "0.376 0.659 0.290 1", id="tabStrich%d" % i)
        knopf(x, TAB_TOP, TAB_B, TAB_H, "tab%d" % i, "onClickTab", "ao_pc_tab%d" % i, profil="aoPcTab")

    start()
    kasse()
    fuhrpark()
    abgaben()
    overview()

    innen = "\n".join("            " + z for z in zeilen)
    gesamt = KOPF.replace("@@INHALT@@", innen)
    with open(ZIEL, "w", encoding="utf-8", newline="\n") as f:
        f.write(gesamt)
    xml.dom.minidom.parse(ZIEL)
    print("geschrieben:", ZIEL, len(ids), "ids,", flaechen[0], "Flaechen")


KOPF = """<?xml version="1.0" encoding="utf-8" standalone="no" ?>
<GUI name="AOHofPCUI" onOpen="onOpen" onClose="onClose">
    <GuiElement profile="newLayer" />
    <Bitmap profile="dialogFullscreenBg" id="dialogBg" />

    <GuiElement profile="fs25_dialogBg" id="dialogElement" size="1600px 900px">
@@INHALT@@

        <BoxLayout profile="aoPcKnoepfe" position="1130px -838px" size="440px 56px">
            <Button profile="buttonBack" onClick="onClickBack" id="closeButton" />
        </BoxLayout>
    </GuiElement>

    <GUIProfiles>
        <Profile name="aoPcSeite" extends="emptyPanel" with="anchorTopLeft" />

        <Profile name="aoPcFlaeche" extends="baseReference" with="anchorTopLeft">
            <size value="10px 10px" />
            <imageUVs value="0 0 1 1" />
            <imageColor value="1 1 1 1" />
            <imageSliceId value="noSlice" />
        </Profile>
        <Profile name="aoPcBild" extends="aoPcFlaeche" />
        <Profile name="aoPcPfeilHoch" extends="aoPcFlaeche" />
        <Profile name="aoPcPfeilRunter" extends="aoPcFlaeche" />

        <Profile name="aoPcText" extends="fs25_textDefault" with="anchorTopLeft">
            <textSize value="15px" />
            <textColor value="1 1 1 1" />
        </Profile>

        <Profile name="aoPcOptZeile" extends="emptyPanel" with="anchorTopLeft pivotTopLeft">
            <size value="620px 34px" />
        </Profile>

        <Profile name="aoPcTab" extends="emptyPanel" with="anchorTopLeft">
            <focusOnHighlight value="true" />
            <textSize value="16px" />
            <textBold value="true" />
            <textAlignment value="center" />
            <textColor value="0.88 0.92 0.96 1" />
            <textHighlightedColor value="$preset_fs25_colorMainHighlight" />
            <textFocusedColor value="$preset_fs25_colorMainHighlight" />
            <textPressedColor value="$preset_fs25_colorMainHighlight" />
            <textSelectedColor value="1 1 1 1" />
        </Profile>

        <Profile name="aoPcZeile" extends="emptyPanel" with="anchorTopLeft" />

        <Profile name="aoPcKnoepfe" extends="fs25_dialogButtonBox" with="anchorTopLeft" />
    </GUIProfiles>
</GUI>
"""

if __name__ == "__main__":
    main()
