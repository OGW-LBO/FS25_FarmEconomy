#!/usr/bin/env python3
"""Baut FS25_FarmEconomy.zip.

Die Reihenfolge der Lua-Dateien entspricht der in der modDesc.xml und ist
bewusst so gewaehlt: AgrarOekonomie.lua (Namensraum und CFG) und AOSettings.lua
(inklusive der Rueckwaerts-Shims) muessen vor den uebernommenen Modul-Kernen
geladen werden.

Die ZIP wird NUR hier im Codex-Ordner erzeugt und nicht in den Mods-Ordner
kopiert - das macht der Nutzer bzw. der Server-Upload selbst.
"""
import os
import zipfile

NAME = "FS25_FarmEconomy.zip"

DATEIEN = [
    "modDesc.xml",
    "icon_mod.dds",
    # GUI des Helfer-Dialogs (ALT+H). Fehlt sie, laedt der Dialog nicht.
    "gui/HelferLohnDialog.xml",
    # GUI des eigenen Einstellungs-Tabs.
    "gui/AOMenu.xml",
    # Kern und gemeinsame Infrastruktur
    "AgrarOekonomie.lua",
    "AOSettings.lua",
    "AOSettingsEvent.lua",
    "AOProduktionEvent.lua",
    "AONotifyEvent.lua",
    # Meldungs-Events der uebernommenen Module
    "FuhrparkSteuerNotifyEvent.lua",
    "HelferLohnNotifyEvent.lua",
    # Uebernommene Modul-Kerne
    "FuhrparkSteuer.lua",
    # Diese beiden werden ueber <specializations> geladen, nicht ueber
    # extraSourceFiles - sie muessen aber trotzdem in die ZIP.
    "FuhrparkSteuerInfo.lua",
    "ReparaturOekonomie.lua",
    "ReparaturOekonomieMain.lua",
    "ReparaturOekonomieWorkshop.lua",
    "HelferLohn.lua",
    "HelferLohnDialog.lua",
    "BindegarnFolieVerbrauch.lua",
    "DieselVerbrauch.lua",
    # Neue Module
    "AOGrundsteuer.lua",
    "AOZins.lua",
    "AOProduktion.lua",
    "AOAutomatik.lua",
    "AOBericht.lua",
    "AOBerichtEvent.lua",
    "gui/AOKassenbuchDialog.xml",
    "images/white.dds",
    "AOKassenbuchEvent.lua",
    "AOKassenbuchSeite.lua",
    "AOKassenbuch.lua",
    "AOKassenbuchDialog.lua",
    # Bedienung
    "AOUIHelper.lua",
    "AOSettingsPage.lua",
    "AOMenuPage.lua",
    "AOMod.lua",
]

fehlend = [f for f in DATEIEN if not os.path.exists(f)]
if fehlend:
    raise SystemExit("FEHLEND: " + ", ".join(fehlend))

if os.path.exists(NAME):
    os.remove(NAME)

with zipfile.ZipFile(NAME, "w", zipfile.ZIP_DEFLATED) as z:
    for f in DATEIEN:
        z.write(f, f)

print("ZIP:", NAME, round(os.path.getsize(NAME) / 1024, 1), "KB")
with zipfile.ZipFile(NAME) as z:
    for i in z.namelist():
        print("  ", i)
