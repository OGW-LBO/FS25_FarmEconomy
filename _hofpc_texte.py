"""Texte und Quelldateien fuer den Hof-PC in die modDesc.xml eintragen.
Laeuft mehrfach ohne Schaden: vorhandene Schluessel werden ersetzt."""
import os
import re
import xml.dom.minidom

BASIS = os.path.dirname(os.path.abspath(__file__))
PFAD = os.path.join(BASIS, "modDesc.xml")

QUELLEN_ALT = '        <sourceFile filename="AOKassenbuchDialog.lua"/>\n'
QUELLEN_NEU = [
    "AOMaschinenEvent.lua", "AOAbgaben.lua", "AOAbgabenEvent.lua",
    "AOHofPC.lua", "AOHofPCKasse.lua", "AOHofPCFuhrpark.lua", "AOHofPCAbgaben.lua",
]

TEXTE = [
    ("input_AO_BUCH", "Hof-PC öffnen", "Open farm PC", "Ouvrir le PC de la ferme"),

    ("ao_pc_titel", "Hof-PC", "Farm PC", "PC de la ferme"),
    ("ao_pc_tab1", "Start", "Home", "Accueil"),
    ("ao_pc_tab2", "Kassenbuch", "Cash book", "Livre de caisse"),
    ("ao_pc_tab3", "Fuhrpark", "Fleet", "Parc"),
    ("ao_pc_tab4", "Abgaben & Helfer", "Charges & helpers", "Charges et ouvriers"),
    ("ao_pc_tab5", "Betriebsübersicht", "Farm Overview", "Aperçu Exploitation"),
    ("ao_pc_uhr", "%s. %s, Jahr %s, %s Uhr", "%s %s, year %s, %s", "%s %s, année %s, %s"),
    ("ao_pc_laedt", "Zahlen werden geholt …", "Fetching figures …", "Récupération des chiffres …"),
    ("ao_pc_an", "an", "on", "activé"),
    ("ao_pc_aus", "aus", "off", "désactivé"),
    ("ao_pc_heuteNacht", "heute Nacht", "tonight", "cette nuit"),
    ("ao_pc_morgenNacht", "morgen Nacht", "tomorrow night", "demain soir"),
    ("ao_pc_inTagen", "in %s Tagen", "in %s days", "dans %s jours"),
    ("ao_pc_monate", "%s Monate", "%s months", "%s mois"),
    ("ao_pc_monatlich", "monatlich", "monthly", "mensuelle"),
    ("ao_pc_jaehrlichIn", "jährlich, nächste in %s Monaten", "yearly, next in %s months",
     "annuelle, prochaine dans %s mois"),

    ("ao_pc_stKonto", "Kontostand", "Balance", "Solde"),
    ("ao_pc_stKredit", "Kredit: %s", "Loan: %s", "Prêt : %s"),
    ("ao_pc_stNetto", "Vermögen", "Net worth", "Patrimoine"),
    ("ao_pc_stNettoSub", "Geld, Maschinen, Gebäude und Land, abzüglich Kredit",
     "Cash, machines, buildings and land, minus loan",
     "Argent, machines, bâtiments et terrains, moins le prêt"),
    ("ao_pc_stVorjahr", "%s zum Vorjahr", "%s on last year", "%s par rapport à l'an dernier"),
    ("ao_pc_stMonat", "Ergebnis dieser Monat", "Result this month", "Résultat ce mois-ci"),
    ("ao_pc_stJahr", "Ergebnis dieses Jahr", "Result this year", "Résultat cette année"),
    ("ao_pc_stEinAus", "Einnahmen %s, Ausgaben %s", "Income %s, expenses %s", "Revenus %s, dépenses %s"),
    ("ao_pc_stInvest", "dazu Investitionen %s", "plus investments of %s", "plus %s d'investissements"),
    ("ao_pc_stVermoegen", "Was der Hof wert ist", "What the farm is worth", "Ce que vaut la ferme"),
    ("ao_pc_stGeld", "Geld", "Cash", "Argent"),
    ("ao_pc_stFahrzeuge", "Fahrzeuge", "Vehicles", "Véhicules"),
    ("ao_pc_stGebaeude", "Gebäude", "Buildings", "Bâtiments"),
    ("ao_pc_stLand", "Land", "Land", "Terrains"),
    ("ao_pc_stKreditPosten", "Kredit", "Loan", "Prêt"),
    ("ao_pc_stBlick", "Auf einen Blick", "At a glance", "En un coup d'œil"),
    ("ao_pc_stFelder", "Fläche", "Area", "Surface"),
    ("ao_pc_stFelderWert", "%s ha Feld, %s ha Land", "%s ha fields, %s ha land", "%s ha de champs, %s ha de terrain"),
    ("ao_pc_stMaschinen", "Fahrzeuge und Geräte", "Vehicles and tools", "Véhicules et outils"),
    ("ao_pc_stMaschinenWert", "%s, davon %s geleast", "%s, %s of them leased", "%s, dont %s en leasing"),
    ("ao_pc_stMkJahr", "Maschinenkosten dieses Jahr", "Machine costs this year", "Coûts machines cette année"),
    ("ao_pc_stTeuer", "Teuerste je Stunde", "Most expensive per hour", "La plus chère par heure"),
    ("ao_pc_stTeuerWert", "%s, %s/h", "%s, %s/h", "%s, %s/h"),
    ("ao_pc_stAbgaben", "Abgaben nächster Monat", "Charges next month", "Charges le mois prochain"),
    ("ao_pc_stWechsel", "Nächster Monatswechsel", "Next month change", "Prochain changement de mois"),
    ("ao_pc_stHelfer", "Helfer gerade im Einsatz", "Helpers working now", "Ouvriers au travail"),
    ("ao_pc_stLohn", "Helferlöhne dieses Jahr", "Helper wages this year", "Salaires des ouvriers cette année"),
    ("ao_pc_stVerlauf", "Die letzten sechs Monate", "The last six months", "Les six derniers mois"),

    ("ao_pc_abTitel", "Abgaben und Zinsen", "Charges and interest", "Charges et intérêts"),
    ("ao_pc_abPosten", "Posten", "Item", "Poste"),
    ("ao_pc_abNaechste", "Nächste Abrechnung", "Next billing", "Prochaine facture"),
    ("ao_pc_abJahr", "Dieses Jahr", "This year", "Cette année"),
    ("ao_pc_abVorjahr", "Vorjahr", "Last year", "Année dernière"),
    ("ao_pc_abFs", "Fuhrpark-Steuer", "Fleet tax", "Taxe de flotte"),
    ("ao_pc_abGs", "Grundsteuer", "Property tax", "Impôt foncier"),
    ("ao_pc_abKredit", "Kreditzinsen", "Loan interest", "Intérêts du prêt"),
    ("ao_pc_abLohn", "Helferlöhne", "Helper wages", "Salaires des ouvriers"),
    ("ao_pc_abZins", "Guthabenzins (Gutschrift)", "Interest on savings (credit)", "Intérêts créditeurs (crédit)"),
    ("ao_pc_abSumme", "Kosten zusammen", "Total costs", "Total des coûts"),
    ("ao_pc_abStrich", "Unterm Strich, nach Zins", "Bottom line after interest", "Bilan après intérêts"),
    ("ao_pc_abGrundlagen", "Womit gerechnet wird", "What it is based on", "Sur quoi repose le calcul"),
    ("ao_pc_abFsInfo", "Fuhrpark", "Fleet", "Parc"),
    ("ao_pc_abFsInfoWert", "%s besteuert, %s ruhend, %s unter Dach", "%s taxed, %s idle, %s under a roof",
     "%s taxés, %s à l'arrêt, %s à l'abri"),
    ("ao_pc_abFsAbrechnung", "Abrechnung Fuhrpark-Steuer", "Fleet tax billing", "Facturation de la taxe de flotte"),
    ("ao_pc_abKarenz", "Neufahrzeuge steuerfrei", "New vehicles tax free for", "Véhicules neufs exonérés"),
    ("ao_pc_abGsInfo", "Grundsteuer", "Property tax", "Impôt foncier"),
    ("ao_pc_abGsInfoWert", "Landwert %s, %s ha, %s im Jahr", "land value %s, %s ha, %s a year",
     "valeur %s, %s ha, %s par an"),
    ("ao_pc_abZiInfo", "Guthabenzins", "Interest on savings", "Intérêts créditeurs"),
    ("ao_pc_abZiInfoWert", "auf %s, %s im Jahr", "on %s, %s a year", "sur %s, %s par an"),
    ("ao_pc_abZiLetzte", "Letzte Zinsgutschrift", "Last interest credit", "Dernier crédit d'intérêts"),
    ("ao_pc_abKreditStand", "Kredit offen", "Loan outstanding", "Prêt restant"),
    ("ao_pc_abFuss",
     "Die nächste Abrechnung ist eine Schätzung mit dem heutigen Stand. Die Bremse kann sie noch kürzen.",
     "The next billing is an estimate based on today. The safety brake may still reduce it.",
     "La prochaine facture est une estimation à partir de la situation actuelle. Le frein peut encore la réduire."),
    ("ao_pc_abHelfer", "Helfer", "Helpers", "Ouvriers"),
    ("ao_pc_hlModul", "Helferlohn", "Helper wages", "Salaire des ouvriers"),
    ("ao_pc_hlModus", "Bezahlung", "Payment", "Paiement"),
    ("ao_pc_hlStunde", "Stundenlohn", "Hourly wage", "Salaire horaire"),
    ("ao_pc_hlFest", "Festpreis je Auftrag", "Fixed price per job", "Prix fixe par mission"),
    ("ao_pc_hlStufe", "Lohn", "Wage", "Salaire"),
    ("ao_pc_hlStufeWert", "%s, Faktor %s", "%s, factor %s", "%s, facteur %s"),
    ("ao_pc_hlFestWert", "je nach Aufgabe, siehe Helferfenster", "depends on the task, see helper window",
     "selon la tâche, voir la fenêtre des ouvriers"),
    ("ao_pc_hlZufall", "Verfügbarkeit", "Availability", "Disponibilité"),
    ("ao_pc_hlZufallAn", "nicht immer jemand frei", "not always someone free", "pas toujours quelqu'un de libre"),
    ("ao_pc_hlZufallAus", "immer jemand da", "always someone there", "toujours quelqu'un"),
    ("ao_pc_hlGratis", "Sprit und Material beim Helfer", "Fuel and supplies for helpers", "Carburant et intrants des ouvriers"),
    ("ao_pc_hlGratisAn", "gratis", "free", "gratuits"),
    ("ao_pc_hlGratisAus", "zahlt der Hof", "paid by the farm", "payés par la ferme"),
    ("ao_pc_hlEinsatz", "Gerade im Einsatz", "Working now", "Au travail"),
    ("ao_pc_hlMonat", "Lohn diesen Monat", "Wages this month", "Salaires ce mois-ci"),
    ("ao_pc_abBremse", "Sicherheitsbremse", "Safety brake", "Frein de sécurité"),
    ("ao_pc_brModul", "Bremse", "Brake", "Frein"),
    ("ao_pc_brDeckel", "Deckel je Spieltag", "Cap per game day", "Plafond par jour"),
    ("ao_pc_brDeckelWert", "%s der Einnahmen", "%s of income", "%s des revenus"),
    ("ao_pc_brSchnitt", "Einnahmen je Tag im Schnitt", "Average income per day", "Revenus moyens par jour"),
    ("ao_pc_brBudget", "Tagesbudget für Abgaben", "Daily budget for charges", "Budget journalier des charges"),
    ("ao_pc_brKeinBudget", "noch keine Einnahmen, kein Deckel", "no income yet, no cap", "pas encore de revenus, pas de plafond"),
    ("ao_pc_brHeute", "Heute abgebucht", "Charged today", "Prélevé aujourd'hui"),
    ("ao_pc_brMindest", "Mindestkontostand", "Minimum balance", "Solde minimum"),
    ("ao_pc_brSpielraum", "Luft bis zum Mindestkontostand", "Room above the minimum balance", "Marge au-dessus du solde minimum"),
    ("ao_pc_brKappung", "Letzte Kürzung", "Last reduction", "Dernière réduction"),
    ("ao_pc_brKeine", "keine", "none", "aucune"),
    ("ao_pc_brKappungWert", "vor %s Tagen %s statt %s, %s", "%s days ago %s instead of %s, %s",
     "il y a %s jours %s au lieu de %s, %s"),
    ("ao_pc_brGrundDeckel", "Deckel", "cap", "plafond"),
    ("ao_pc_brGrundKonto", "Mindestkonto", "minimum balance", "solde minimum"),
    ("ao_pc_brBalken", "Heute %s von %s Tagesbudget verbraucht", "%s of the %s daily budget used today",
     "%s du budget journalier de %s utilisés aujourd'hui"),

    ("ao_pc_foBereich", "Bereich", "Section", "Section"),
    ("ao_pc_foFelder", "Felder", "Fields", "Champs"),
    ("ao_pc_foAufgaben", "Aufgaben", "Tasks", "Tâches"),
    ("ao_pc_foLager", "Lager", "Storage", "Stocks"),
    ("ao_pc_foTiere", "Tiere", "Animals", "Animaux"),
    ("ao_pc_foProduktion", "Produktion", "Production", "Production"),
    ("ao_pc_foFehlt", "Die Betriebsübersicht ist nicht geladen.", "Farm Overview is not loaded.", "Aperçu Exploitation n'est pas chargé."),
    ("ao_pc_foLeer", "Die Betriebsübersicht hat hier noch nichts zu zeigen.", "Farm Overview has nothing to show here yet.",
     "Aperçu Exploitation n'a encore rien à afficher ici."),
    ("ao_pc_foHinweis",
     "Aufgabe anklicken zum Übernehmen, Feld anklicken zum Aufklappen, öffnen führt zum Stall. Fruchtwahl und Einstellungen im ESC-Menü.",
     "Click a task to take it over, a field to expand it, open takes you to the barn. Crop choice and settings are in the ESC menu.",
     "Cliquez une tâche pour la prendre, un champ pour le déplier, ouvrir mène à l'étable. Cultures et réglages dans le menu Échap."),

    ("ao_mk_zeitraum", "Zeitraum", "Period", "Période"),
    ("ao_mk_jahr", "Dieses Spieljahr", "This game year", "Cette année de jeu"),
    ("ao_mk_vorjahr", "Voriges Spieljahr", "Last game year", "Année de jeu précédente"),
    ("ao_mk_gesamt", "Gesamt", "Total", "Total"),
    ("ao_mk_sortieren", "Sortieren", "Sort by", "Trier par"),
    ("ao_mk_sortEh", "Kosten je Stunde", "Cost per hour", "Coût par heure"),
    ("ao_mk_sortSumme", "Kosten gesamt", "Total cost", "Coût total"),
    ("ao_mk_sortStd", "Betriebsstunden", "Operating hours", "Heures de service"),
    ("ao_mk_sortAusl", "Wenig genutzt zuerst", "Least used first", "Les moins utilisés d'abord"),
    ("ao_mk_sortName", "Name", "Name", "Nom"),
    ("ao_mk_zeigen", "Zeigen", "Show", "Afficher"),
    ("ao_mk_zeigAlle", "Alles", "Everything", "Tout"),
    ("ao_mk_zeigMotor", "Nur Fahrzeuge mit Motor", "Only motor vehicles", "Véhicules à moteur seulement"),
    ("ao_mk_zeigGeraete", "Nur Geräte", "Only tools", "Outils seulement"),
    ("ao_mk_zeigLeasing", "Nur geleaste", "Only leased", "En leasing seulement"),
    ("ao_mk_zeigKaum", "Kaum genutzt", "Hardly used", "Peu utilisés"),
    ("ao_mk_seite", "Seite", "Page", "Page"),
    ("ao_mk_seiteVon", "%s von %s", "%s of %s", "%s sur %s"),
    ("ao_mk_hName", "Fahrzeug oder Gerät", "Vehicle or tool", "Véhicule ou outil"),
    ("ao_mk_hStd", "Std.", "Hrs", "H"),
    ("ao_mk_hKosten", "Kosten nach Art", "Costs by type", "Coûts par type"),
    ("ao_mk_hSumme", "Summe", "Total", "Total"),
    ("ao_mk_hEh", "je Std.", "per hr", "par h"),
    ("ao_mk_hZustand", "Zustand", "Condition", "État"),
    ("ao_mk_lWert", "Wertverlust", "Depreciation", "Dépréciation"),
    ("ao_mk_lRep", "Reparaturen", "Repairs", "Réparations"),
    ("ao_mk_lSprit", "Kraftstoffkosten", "Fuel cost", "Coût du carburant"),
    ("ao_mk_lUnterhalt", "Unterhalt und Leasing", "Upkeep and leasing", "Entretien et leasing"),
    ("ao_mk_lFuhrpark", "Fuhrpark-Kosten", "Fleet costs", "Frais de flotte"),
    ("ao_mk_kKosten", "Kosten", "Costs", "Coûts"),
    ("ao_mk_kKostenSub", "für %s Fahrzeuge und Geräte", "for %s vehicles and tools", "pour %s véhicules et outils"),
    ("ao_mk_kStunden", "Betriebsstunden", "Operating hours", "Heures de service"),
    ("ao_mk_kStundenSub", "nur Fahrzeuge mit Motor", "motor vehicles only", "véhicules à moteur seulement"),
    ("ao_mk_kEh", "Kosten je Stunde", "Cost per hour", "Coût par heure"),
    ("ao_mk_kEhSub", "Schnitt der Fahrzeuge mit Motor", "average of motor vehicles", "moyenne des véhicules à moteur"),
    ("ao_mk_kSprit", "Kraftstoff", "Fuel", "Carburant"),
    ("ao_mk_kSpritSub", "für %s", "costing %s", "pour %s"),
    ("ao_mk_kFlaeche", "Bearbeitete Fläche", "Area worked", "Surface travaillée"),
    ("ao_mk_kFlaecheSub", "%s je Hektar", "%s per hectare", "%s par hectare"),
    ("ao_mk_eigentum", "Eigentum", "Owned", "En propriété"),
    ("ao_mk_geleast", "Geleast", "Leased", "En leasing"),
    ("ao_mk_nameGeleast", "%s (Leasing)", "%s (leased)", "%s (leasing)"),
    ("ao_mk_dStatus", "%s, Zeitwert %s", "%s, current value %s", "%s, valeur actuelle %s"),
    ("ao_mk_dLeasingBesser", "Geleast hätte das nur %s gekostet statt %s. Leasing wäre hier günstiger.",
     "Leasing would have cost only %s instead of %s. Leasing would be cheaper here.",
     "En leasing, cela n'aurait coûté que %s au lieu de %s. Le leasing serait moins cher ici."),
    ("ao_mk_dLeasingVgl", "Geleast hätte das %s gekostet, als Eigentum %s (ohne Kraftstoff).",
     "Leased it would have cost %s, owned it cost %s (fuel not included).",
     "En leasing : %s, en propriété : %s (hors carburant)."),
    ("ao_mk_dAltbestand", "Stunden und Wertverlust seit dem Kauf, Reparaturen und Kraftstoff erst ab der Erfassung.",
     "Hours and depreciation since purchase, repairs and fuel only since tracking began.",
     "Heures et dépréciation depuis l'achat, réparations et carburant seulement depuis le début du suivi."),
    ("ao_mk_dStunden", "Betriebsstunden", "Operating hours", "Heures de service"),
    ("ao_mk_dStundenWert", "%s h an %s Tagen", "%s h over %s days", "%s h sur %s jours"),
    ("ao_mk_dAuslastung", "Auslastung", "Utilisation", "Utilisation"),
    ("ao_mk_dAuslastungWert", "%s h je Monat", "%s h per month", "%s h par mois"),
    ("ao_mk_dZustand", "Zustand", "Condition", "État"),
    ("ao_mk_dKraftstoff", "Kraftstoff", "Fuel", "Carburant"),
    ("ao_mk_dFlaeche", "Fläche", "Area", "Surface"),
    ("ao_mk_dUnterhalt", "Unterhalt", "Upkeep", "Entretien"),
    ("ao_mk_dLeasing", "Leasing", "Leasing", "Leasing"),
    ("ao_mk_dSumme", "Kosten zusammen", "Total costs", "Total des coûts"),
    ("ao_mk_dJe", "Je Stunde und Hektar", "Per hour and hectare", "Par heure et hectare"),
    ("ao_mk_dJeWert", "%s/h, %s/ha", "%s/h, %s/ha", "%s/h, %s/ha"),
    ("ao_mk_hinweis",
     "Zeile anklicken für Einzelheiten. Gezählt wird ab dem Laden der Mod, unter Gesamt zählen Stunden und Wertverlust ab dem Kauf.",
     "Click a row for details. Counting starts when the mod is loaded; under Total, hours and depreciation count from purchase.",
     "Cliquez sur une ligne pour le détail. Le comptage commence au chargement du mod ; sous Total, heures et dépréciation comptent depuis l'achat."),
    ("ao_mk_aus", "Die Maschinenkosten sind in den Einstellungen ausgeschaltet.",
     "Machine costs are switched off in the settings.", "Les coûts machines sont désactivés dans les réglages."),
    ("ao_mk_keineDaten", "Für diesen Zeitraum und diese Auswahl gibt es noch keine Zahlen.",
     "No figures yet for this period and selection.", "Pas encore de chiffres pour cette période et cette sélection."),

    ("ao_help_buchFensterTitle", "Der Hof-PC", "The farm PC", "Le PC de la ferme"),
    ("ao_help_buchFenster",
     "Strg+K schaltet den Hof-PC ein, zu Fuß wie im Fahrzeug. Oben in der Leiste liegen die Programme. Start zeigt Kontostand, "
     "Vermögen, das Ergebnis von Monat und Jahr und die letzten sechs Monate als Balken. Im Kassenbuch wählst du Monate oder "
     "Jahre und blätterst mit den Pfeilen zurück bis zum Anfang des vorigen Spieljahres. Links siehst du, wofür das Geld "
     "weggeht, rechts die letzten Buchungen. Unter Fuhrpark steht jedes Fahrzeug und Gerät mit Stunden, Kosten nach Art und "
     "Kosten je Stunde, ein Klick auf eine Zeile zeigt rechts die Einzelheiten samt Vergleich mit Leasing. Abgaben & Helfer "
     "sammelt Steuern, Zinsen, Helferlöhne und den Stand der Sicherheitsbremse. Ist die Betriebsübersicht installiert, gibt es deren "
     "Felder, Aufgaben, Lager, Tiere und Produktion als eigenes Programm dazu. Im Mehrspieler sieht jeder nur seinen Hof, "
     "gerechnet wird auf dem Server. Die Taste kannst du in den Spieleinstellungen umlegen.",
     "Ctrl+K switches on the farm PC, on foot or in a vehicle. The programs sit in the bar at the top. Home shows your balance, "
     "net worth, the result for month and year and the last six months as bars. In the cash book you pick months or years and "
     "page back with the arrows as far as the start of last game year; on the left you see where the money goes, on the right "
     "the latest bookings. Fleet lists every vehicle and tool with hours, costs by type and cost per hour, and a click on a row "
     "shows the details on the right, including a comparison with leasing. Charges & helpers gathers taxes, interest, helper "
     "wages and the state of the safety brake. If Farm Overview is installed, its fields, tasks, storage, animals and production "
     "come along as a program of their own. In multiplayer everyone only sees their own farm, the server does the maths. You "
     "can rebind the key in the game settings.",
     "Ctrl+K allume le PC de la ferme, à pied comme en véhicule. Les programmes se trouvent dans la barre du haut. Accueil "
     "affiche le solde, le patrimoine, le résultat du mois et de l'année et les six derniers mois en barres. Dans le livre de "
     "caisse, vous choisissez mois ou années et remontez avec les flèches jusqu'au début de l'année de jeu précédente ; à "
     "gauche, où part l'argent, à droite les dernières opérations. Parc liste chaque véhicule et outil avec heures, coûts par "
     "type et coût par heure ; un clic sur une ligne affiche le détail à droite, avec une comparaison au leasing. Charges et "
     "ouvriers regroupe impôts, intérêts, salaires des ouvriers et l'état du frein de sécurité. Si Aperçu Exploitation est installé, "
     "ses champs, tâches, stocks, animaux et productions s'ajoutent comme programme à part. En multijoueur, chacun ne voit "
     "que sa ferme et le serveur fait le calcul. La touche se change dans les réglages du jeu."),
]


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def block(name, de, en, fr):
    return ('        <text name="%s">\n            <de>%s</de>\n            <en>%s</en>\n'
            '            <fr>%s</fr>\n        </text>\n') % (name, esc(de), esc(en), esc(fr))


def main():
    with open(PFAD, encoding="utf-8", newline="") as f:
        t = f.read()

    if QUELLEN_ALT in t:
        neu = "".join('        <sourceFile filename="%s"/>\n' % q for q in QUELLEN_NEU)
        t = t.replace(QUELLEN_ALT, neu)
    for q in QUELLEN_NEU:
        if t.count('filename="%s"' % q) != 1:
            raise SystemExit("Quelle fehlt oder doppelt: " + q)

    neu_ende = []
    for name, de, en, fr in TEXTE:
        muster = re.compile(r'        <text name="%s">\n.*?        </text>\n' % re.escape(name), re.S)
        if muster.search(t):
            t = muster.sub(lambda _m: block(name, de, en, fr), t, count=1)
        else:
            neu_ende.append(block(name, de, en, fr))
    if neu_ende:
        t = t.replace("    </l10n>", "".join(neu_ende) + "    </l10n>", 1)

    with open(PFAD, "w", encoding="utf-8", newline="") as f:
        f.write(t)
    xml.dom.minidom.parse(PFAD)
    print("modDesc aktualisiert,", len(TEXTE), "Texte,", len(neu_ende), "neu")


if __name__ == "__main__":
    main()
