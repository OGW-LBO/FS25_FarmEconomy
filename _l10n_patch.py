#!/usr/bin/env python3
"""Ergaenzt die modDesc.xml um alles, was der ModHub verlangt:

  1. Korrigiert zwei uebernommene Hilfetexte, die noch auf die Pfade und
     Konsolenbefehle der Vorgaenger-Mods zeigen.
  2. Traegt Franzoesisch in die 31 Schluessel nach, die nur de/en hatten.
  3. Legt die l10n-Schluessel der neuen Einstellungsseite an (de/en/fr).
  4. Ergaenzt <title><fr> und <description><fr>.

Alles INLINE in der modDesc - separate i18n-Dateien werden vom TestRunner
als "obsolete" gemeldet (siehe FarmOverview 08.2026).

Das Skript ist idempotent: bereits vorhandene <fr>-Eintraege und Schluessel
werden nicht doppelt angelegt.
"""
import re
import sys

PFAD = "modDesc.xml"

# ---------------------------------------------------------------------------
# 1. Hilfetexte, die noch auf die alten Einzel-Mods zeigen
# ---------------------------------------------------------------------------

KORREKTUR = {
    "fs_help_config": {
        "de": "Einstellbar im ESC-Menue unter Allgemeine Einstellungen, ueber die Datei "
              "modSettings/FS25_FarmEconomy/settings.xml oder im Spiel per Konsole: "
              "aoConfig fuhrpark.Name Wert. Uebersicht mit aoStatus, Kosten des aktuellen "
              "Fahrzeugs mit fsVehicle. Aenderungen wirken sofort, werden gespeichert und "
              "im Multiplayer verteilt.",
        "en": "Configure in the ESC menu under General Settings, via the file "
              "modSettings/FS25_FarmEconomy/settings.xml or the in-game console: "
              "aoConfig fuhrpark.Name Value. Overview with aoStatus, current vehicle cost "
              "with fsVehicle. Changes apply immediately, are saved and synchronized in "
              "multiplayer.",
        "fr": "Reglable dans le menu ESC sous Parametres generaux, via le fichier "
              "modSettings/FS25_FarmEconomy/settings.xml ou par la console : "
              "aoConfig fuhrpark.Nom Valeur. Vue d'ensemble avec aoStatus, cout du vehicule "
              "actuel avec fsVehicle. Les changements sont immediats, sauvegardes et "
              "synchronises en multijoueur.",
    },
    "ro_help_config": {
        "de": "Einstellbar im ESC-Menue unter Allgemeine Einstellungen, ueber die Datei "
              "modSettings/FS25_FarmEconomy/settings.xml oder im Spiel per Konsole: "
              "aoConfig reparatur.Name Wert. Werte des aktuellen Fahrzeugs mit roStatus.",
        "en": "Configure in the ESC menu under General Settings, via the file "
              "modSettings/FS25_FarmEconomy/settings.xml or the in-game console: "
              "aoConfig reparatur.Name Value. Check the current vehicle's values with roStatus.",
        "fr": "Reglable dans le menu ESC sous Parametres generaux, via le fichier "
              "modSettings/FS25_FarmEconomy/settings.xml ou par la console : "
              "aoConfig reparatur.Nom Valeur. Valeurs du vehicule actuel avec roStatus.",
    },
}

# ---------------------------------------------------------------------------
# 2. Franzoesisch fuer die uebernommenen Schluessel
# ---------------------------------------------------------------------------

FR = {
    "ao_help_category":      "Economie Agricole",
    "fs_meldungMonat":       "Taxe de flotte : %d vehicules, -%s (mensuel)",
    "fs_meldungJahr":        "Taxe de flotte : %d vehicules, -%s (annuel)",
    "fs_infoLabel":          "Taxe/frais",
    "fs_help_category":      "Taxe De Flotte",
    "fs_help_pageTitle":     "Taxe De Flotte",
    "fs_help_intro":
        "Chaque vehicule et outil vous appartenant genere des couts recurrents - comme la taxe, "
        "l'assurance et l'entretien dans la vie reelle. Les couts sont preleves mensuellement ou "
        "annuellement et dependent de la valeur du vehicule. Ils apparaissent dans le bilan financier.",
    "fs_help_configTitle":   "Configuration",
    "fs_help_valuesTitle":   "Reglages principaux",
    "fs_help_values":
        "billingMode (0 = mensuel, 1 = annuel), taxRatePerYear et upkeepRatePerYear (part de la "
        "valeur du vehicule par an, 0.02 = 2 pour cent), ownedOnly (exclure le materiel en leasing), "
        "useResaleValue (valeur de revente au lieu du prix d'achat), minCostPerVehicleMonth "
        "(cout minimum par vehicule).",
    "ro_faktor":             "Facteur de reparation",
    "ro_reparatur":          "Reparation",
    "ro_bisher":             "Reparations effectuees",
    "ro_stunden":            "Heures de service",
    "ro_restwert":           "Valeur de revente",
    "ro_hinweis":            "Avertissement",
    "ro_teuer":              "Entretien de plus en plus cher",
    "ro_unwirtschaftlich":   "Envisagez un remplacement",
    "ro_meldungWarnung":     "%s : l'entretien devient cher.",
    "ro_meldungKritisch":    "%s : la prochaine reparation n'est plus rentable. Envisagez un remplacement.",
    "ro_werkstatt_kritisch":
        "%s\nLes couts de reparation cumules atteignent %d %% de la valeur du vehicule. "
        "Un remplacement est probablement moins cher que de continuer a reparer.",
    "ro_help_category":      "Economie De Reparation",
    "ro_help_pageTitle":     "Economie De Reparation",
    "ro_help_intro":
        "Les reparations coutent plus cher avec l'usage - plus il y a d'heures de service et de "
        "reparations, plus le prix monte. Quand un vehicule n'est plus rentable, le mod previent "
        "dans la boite d'info, par message a l'ecran et dans l'atelier.",
    "ro_help_configTitle":   "Configuration",
    "ro_help_valuesTitle":   "Reglages principaux",
    "ro_help_values":
        "referenzStunden et faktorStunden (hausse selon les heures de service), faktorProReparatur "
        "(hausse par reparation), faktorMax (plafond), tempoSchaden et tempoLack (vitesse d'usure), "
        "warnStunden et kritischStunden (seuils des avertissements).",
    "ro_help_noteTitle":     "Remarque",
    "ro_help_note":
        "A ne pas utiliser avec d'autres mods qui modifient les couts de reparation ou la vitesse d'usure.",
}

# ---------------------------------------------------------------------------
# 3. Neue Schluessel der Einstellungsseite: (de, en, fr)
# ---------------------------------------------------------------------------

NEU = {
    # --- Abschnitts-Ueberschriften ---
    "ao_sec_preise":      ("Agrar-Oekonomie: Verkaufspreise",
                           "Farm Economy: Selling Prices",
                           "Economie Agricole : prix de vente"),
    "ao_sec_bremse":      ("Agrar-Oekonomie: Sicherheitsbremse",
                           "Farm Economy: Safety Brake",
                           "Economie Agricole : frein de securite"),
    "ao_sec_fuhrpark":    ("Fuhrpark-Steuer", "Fleet Tax", "Taxe de flotte"),
    "ao_sec_grundsteuer": ("Grundsteuer", "Property Tax", "Impot foncier"),
    "ao_sec_reparatur":   ("Reparatur-Oekonomie", "Repair Economics", "Economie de reparation"),
    "ao_sec_helfer":      ("Helfer-Arbeitsmarkt", "Helper Job Market", "Marche du travail des ouvriers"),
    "ao_sec_verbrauch":   ("Verbrauch Bindegarn, Netz und Folie",
                           "Twine, Net and Wrap Usage",
                           "Consommation ficelle, filet et film"),

    # --- Auswahltexte ---
    "ao_opt_aus":         ("Aus", "Off", "Desactive"),
    "ao_opt_an":          ("An", "On", "Active"),
    "ao_opt_monatlich":   ("monatlich", "monthly", "mensuel"),
    "ao_opt_jaehrlich":   ("jaehrlich", "yearly", "annuel"),
    "ao_opt_azubi":       ("Azubi", "Apprentice", "Apprenti"),
    "ao_opt_quer":        ("Quereinsteiger", "Career changer", "Reconversion"),
    "ao_opt_ausgelernt":  ("Ausgelernt", "Fully trained", "Qualifie"),
    "ao_opt_eigen":       ("Eigener Lohn", "Custom wage", "Salaire personnalise"),
    "ao_opt_auto":        ("Automatisch", "Automatic", "Automatique"),
    "ao_opt_leicht":      ("Leicht", "Easy", "Facile"),
    "ao_opt_normal":      ("Normal", "Normal", "Normal"),
    "ao_opt_schwer":      ("Schwer", "Hard", "Difficile"),
    "ao_opt_eigenePreise":("Eigene Preise", "Custom prices", "Prix personnalises"),
    "ao_opt_stundenlohn": ("Stundenlohn", "Hourly wage", "Salaire horaire"),
    "ao_opt_festpreis":   ("Festpreis", "Fixed price", "Prix fixe"),

    # --- Verkaufspreise ---
    "ao_ui_preiseAktiv":  ("Verkaufspreise anpassen", "Adjust selling prices",
                           "Ajuster les prix de vente"),
    "ao_ui_preiseAktiv_t":
        ("Schaltet die Preisanpassung fuer Feldfruechte und Produktionserzeugnisse ein.",
         "Enables price scaling for crops and production output.",
         "Active l'ajustement des prix pour les cultures et les produits de production."),
    "ao_ui_preisFruechte":("Faktor Feldfruechte", "Crop price factor",
                           "Facteur prix des cultures"),
    "ao_ui_preisFruechte_t":
        ("Erloes beim Verkauf von Ernte. 1.00 = unveraendert, 0.75 = ein Viertel weniger.",
         "Revenue when selling harvested crops. 1.00 = unchanged, 0.75 = a quarter less.",
         "Revenu lors de la vente des recoltes. 1.00 = inchange, 0.75 = un quart de moins."),
    "ao_ui_preisProdukte":("Faktor Produktionserzeugnisse", "Production output factor",
                           "Facteur produits de production"),
    "ao_ui_preisProdukte_t":
        ("Erloes aus Produktionen. Tierprodukte, BGA-Strom und Holz bleiben unberuehrt.",
         "Revenue from production points. Animal products, biogas power and wood stay untouched.",
         "Revenu des sites de production. Produits animaux, electricite du biogaz et bois non affectes."),

    # --- Sicherheitsbremse ---
    "ao_ui_bremseAktiv":  ("Sicherheitsbremse", "Safety brake", "Frein de securite"),
    "ao_ui_bremseAktiv_t":
        ("Begrenzt alle Abbuchungen dieser Mod, damit sie den Betrieb nie erdruecken koennen.",
         "Caps all charges from this mod so they can never crush the farm.",
         "Plafonne tous les prelevements de ce mod pour qu'ils n'etouffent jamais l'exploitation."),
    "ao_ui_bremseAnteil": ("Kostendeckel je Spieltag", "Cost cap per day",
                           "Plafond de couts par jour"),
    "ao_ui_bremseAnteil_t":
        ("Hoechstanteil der mittleren Tageseinnahmen, den die Mod pro Spieltag abbuchen darf.",
         "Maximum share of average daily income the mod may charge per day.",
         "Part maximale du revenu journalier moyen que le mod peut prelever par jour."),
    "ao_ui_notbremseKonto":("Notbremse ab Kontostand", "Emergency stop below balance",
                            "Arret d'urgence sous le solde"),
    "ao_ui_notbremseKonto_t":
        ("Unter diesem Kontostand bucht die Mod gar nichts mehr ab.",
         "Below this balance the mod stops charging entirely.",
         "En dessous de ce solde, le mod ne preleve plus rien."),
    "ao_ui_karenzMonate": ("Karenz fuer Neufahrzeuge (Monate)", "Grace period for new vehicles (months)",
                           "Delai de grace vehicules neufs (mois)"),
    "ao_ui_karenzMonate_t":
        ("So viele Spielmonate bleibt ein frisch gekauftes Fahrzeug steuerfrei - entlastet Kreditkaeufe.",
         "Number of in-game months a newly bought vehicle stays tax free - eases purchases on credit.",
         "Nombre de mois de jeu pendant lesquels un vehicule neuf reste exonere - allege les achats a credit."),
    "ao_unit_monate":     ("Mon.", "mo.", "mois"),

    # --- Fuhrpark ---
    "ao_ui_fsEnabled":    ("Fuhrpark-Steuer", "Fleet tax", "Taxe de flotte"),
    "ao_ui_fsEnabled_t":
        ("Laufende Kosten je eigenem Fahrzeug und Anbaugeraet.",
         "Recurring costs per owned vehicle and implement.",
         "Couts recurrents par vehicule et outil possede."),
    "ao_ui_fsTax":        ("Steuersatz pro Jahr", "Tax rate per year", "Taux de taxe par an"),
    "ao_ui_fsTax_t":
        ("Anteil des Fahrzeugwerts, der jaehrlich als Steuer anfaellt.",
         "Share of the vehicle value charged as tax each year.",
         "Part de la valeur du vehicule prelevee comme taxe chaque annee."),
    "ao_ui_fsUpkeep":     ("Unterhalt pro Jahr", "Upkeep per year", "Entretien par an"),
    "ao_ui_fsUpkeep_t":
        ("Anteil des Fahrzeugwerts fuer Versicherung, Wartung und Unterstellung.",
         "Share of the vehicle value for insurance, servicing and storage.",
         "Part de la valeur du vehicule pour l'assurance, l'entretien et le remisage."),
    "ao_ui_fsOwned":      ("Nur eigene Fahrzeuge", "Owned vehicles only",
                           "Vehicules possedes uniquement"),
    "ao_ui_fsOwned_t":
        ("Geleaste Geraete bleiben steuerfrei.",
         "Leased equipment stays tax free.",
         "Le materiel en leasing reste exonere."),
    "ao_ui_fsBilling":    ("Abbuchung", "Billing", "Prelevement"),
    "ao_ui_fsBilling_t":
        ("Monatlich verteilt die Last, jaehrlich kommt sie als ein Betrag.",
         "Monthly spreads the load, yearly comes as a single amount.",
         "Mensuel repartit la charge, annuel arrive en un seul montant."),

    # --- Grundsteuer ---
    "ao_ui_gsAktiv":      ("Grundsteuer", "Property tax", "Impot foncier"),
    "ao_ui_gsAktiv_t":
        ("Laufende Kosten auf gekauftes Land - der einzige Posten, der mit der Flaeche waechst.",
         "Recurring costs on owned land - the only item that scales with acreage.",
         "Couts recurrents sur les terres achetees - le seul poste qui croit avec la surface."),
    "ao_ui_gsSatz":       ("Satz pro Jahr", "Rate per year", "Taux par an"),
    "ao_ui_gsSatz_t":
        ("Anteil des Landwerts, der jaehrlich faellig wird.",
         "Share of the land value due each year.",
         "Part de la valeur des terres due chaque annee."),

    # --- Reparatur ---
    "ao_ui_roGrund":      ("Grundfaktor Reparatur", "Repair base factor",
                           "Facteur de base reparation"),
    "ao_ui_roGrund_t":
        ("Multiplikator auf die Reparaturkosten des Basisspiels.",
         "Multiplier on the base game repair costs.",
         "Multiplicateur sur les couts de reparation du jeu de base."),
    "ao_ui_roStunden":    ("Aufschlag je Betriebsstunden", "Surcharge per operating hours",
                           "Supplement selon heures de service"),
    "ao_ui_roStunden_t":
        ("Wie stark die Kosten mit der Nutzung steigen.",
         "How steeply costs rise with usage.",
         "A quel point les couts augmentent avec l'utilisation."),
    "ao_ui_roMax":        ("Obergrenze", "Cap", "Plafond"),
    "ao_ui_roMax_t":
        ("Hoechster Multiplikator, den ein Fahrzeug erreichen kann.",
         "Highest multiplier a vehicle can reach.",
         "Multiplicateur maximal qu'un vehicule peut atteindre."),
    "ao_ui_roTempo":      ("Tempo des Verschleisses", "Wear speed", "Vitesse d'usure"),
    "ao_ui_roTempo_t":
        ("Wie schnell Fahrzeuge ueberhaupt Schaden ansammeln.",
         "How quickly vehicles accumulate damage at all.",
         "A quelle vitesse les vehicules accumulent des dommages."),

    # --- Helfer ---
    "ao_ui_hlAktiv":      ("Helfer-Arbeitsmarkt", "Helper job market",
                           "Marche du travail des ouvriers"),
    "ao_ui_hlAktiv_t":
        ("Lohnstufen und Verfuegbarkeit statt pauschalem Helferlohn.",
         "Wage tiers and availability instead of a flat helper wage.",
         "Niveaux de salaire et disponibilite au lieu d'un salaire forfaitaire."),
    "ao_ui_hlStufe":      ("Lohnstufe", "Wage tier", "Niveau de salaire"),
    "ao_ui_hlStufe_t":
        ("Bessere Helfer arbeiten zuverlaessiger, kosten aber mehr.",
         "Better helpers work more reliably but cost more.",
         "De meilleurs ouvriers travaillent plus surement mais coutent plus cher."),
    "ao_ui_hlNiveau":     ("Preisniveau der Loehne", "Wage price level", "Niveau des salaires"),
    "ao_ui_hlNiveau_t":
        ("Automatisch richtet sich nach der Wirtschaftsschwierigkeit und ueberschreibt die "
         "Lohnbetraege bei jedem Start. Eigene Preise laesst sie unangetastet.",
         "Automatic follows the economic difficulty and overwrites the wage amounts on every "
         "start. Custom prices leaves them untouched.",
         "Automatique suit la difficulte economique et ecrase les montants a chaque demarrage. "
         "Prix personnalises les laisse intacts."),
    "ao_ui_hlModus":      ("Abrechnung", "Payment mode", "Mode de paiement"),
    "ao_ui_hlModus_t":
        ("Stundenlohn laeuft mit, Festpreis wird am Ende des Auftrags faellig.",
         "Hourly wage runs along, fixed price is due when the job ends.",
         "Le salaire horaire court en continu, le prix fixe est du a la fin de la mission."),
    "ao_ui_hlGratis":     ("Betriebsmittel frei bei Helferarbeit",
                           "Free supplies during helper work",
                           "Consommables gratuits pendant le travail de l'ouvrier"),
    "ao_ui_hlGratis_t":
        ("An: waehrend ein Helfer arbeitet, kosten Sprit, Saatgut und Duenger nichts.",
         "On: while a helper works, fuel, seeds and fertilizer are free.",
         "Active : pendant qu'un ouvrier travaille, carburant, semences et engrais sont gratuits."),
    "ao_ui_hlZufall":     ("Zufaellige Verfuegbarkeit", "Random availability",
                           "Disponibilite aleatoire"),
    "ao_ui_hlZufall_t":
        ("Nicht zu jedem Lohn ist sofort ein Helfer zu bekommen.",
         "Not every wage gets you a helper right away.",
         "Un ouvrier n'est pas disponible immediatement a n'importe quel salaire."),

    # --- Verbrauch ---
    "ao_ui_vTwine":       ("Bindegarn (Quaderballen)", "Twine (square bales)",
                           "Ficelle (balles carrees)"),
    "ao_ui_vTwine_t":
        ("Multiplikator auf den Bindegarnverbrauch der Pressen.",
         "Multiplier on the twine usage of balers.",
         "Multiplicateur sur la consommation de ficelle des presses."),
    "ao_ui_vNet":         ("Netz (Rundballen)", "Net (round bales)", "Filet (balles rondes)"),
    "ao_ui_vNet_t":
        ("Multiplikator auf den Netzverbrauch der Pressen.",
         "Multiplier on the net usage of balers.",
         "Multiplicateur sur la consommation de filet des presses."),
    "ao_ui_vWrap":        ("Wickelfolie", "Wrapping film", "Film d'enrubannage"),
    "ao_ui_vWrap_t":
        ("Multiplikator auf den Folienverbrauch der Wickler. Wirkt beim naechsten Laden.",
         "Multiplier on the wrap usage of wrappers. Applies the next time one is loaded.",
         "Multiplicateur sur la consommation de film des enrubanneuses. Effectif au prochain chargement."),
}

TITEL_FR = "Economie Agricole"

BESCHREIBUNG_FR = """Reunit six briques economiques sous un meme toit et rend l'exploitation aussi couteuse qu'elle devrait l'etre - sans qu'un mauvais reglage puisse ruiner la ferme.

- Prix de vente : facteurs distincts pour les cultures et les produits de production. Produits animaux, electricite du biogaz, bois et missions ne sont pas touches.
- Taxe de flotte : couts recurrents par vehicule et outil possede, avec un delai de grace pour les achats neufs.
- Impot foncier : couts recurrents sur les terres achetees - le seul poste qui croit avec la surface (desactive par defaut).
- Economie de reparation : les couts de reparation augmentent avec les heures de service et le nombre de reparations.
- Marche du travail : niveaux de salaire et disponibilite aleatoire au lieu d'un salaire forfaitaire.
- Consommables : ficelle, filet et film d'enrubannage en multiple reglable.

FREIN DE SECURITE : l'ensemble des prelevements de ce mod est plafonne a une part du revenu journalier moyen, et sous un solde configurable plus rien n'est preleve. Un reglage trop dur ou un vehicule achete a credit ne peut pas etouffer l'exploitation.

Independant de la carte : l'ajustement des prix s'accroche a la categorie financiere de l'ecriture, pas a une liste de cultures. Il fonctionne donc aussi sur des cultures que le jeu de base ne connait pas.

Entierement configurable dans le menu ESC sous Parametres generaux, autorite serveur et compatible multijoueur. Commandes console : aoStatus, aoConfig nom valeur, aoReload.

PC/Mac uniquement (mod script)."""


def main():
    s = open(PFAD, encoding="utf-8").read()

    # --- 1. Hilfetexte korrigieren -----------------------------------------
    for key, sprachen in KORREKTUR.items():
        for lang, text in sprachen.items():
            muster = r'(<text name="%s">.*?<%s>).*?(</%s>)' % (re.escape(key), lang, lang)
            if re.search(muster, s, re.S):
                s = re.sub(muster, lambda m: m.group(1) + text + m.group(2), s, count=1, flags=re.S)
            elif lang == "fr":
                # fr fehlt noch -> hinter </en> einfuegen
                muster = r'(<text name="%s">.*?</en>)' % re.escape(key)
                s = re.sub(muster, lambda m: m.group(1) + "\n            <fr>" + text + "</fr>",
                           s, count=1, flags=re.S)

    # --- 2. Franzoesisch nachtragen ----------------------------------------
    ergaenzt = 0
    for key, text in FR.items():
        block = re.search(r'<text name="%s">(.*?)</text>' % re.escape(key), s, re.S)
        if block is None or "<fr>" in block.group(1):
            continue
        muster = r'(<text name="%s">.*?</en>)' % re.escape(key)
        s = re.sub(muster, lambda m: m.group(1) + "\n            <fr>" + text + "</fr>",
                   s, count=1, flags=re.S)
        ergaenzt += 1

    # --- 3. Neue Schluessel anlegen ----------------------------------------
    neu = []
    for key, (de, en, fr) in NEU.items():
        if re.search(r'<text name="%s">' % re.escape(key), s):
            continue
        neu.append(
            '        <text name="%s">\n'
            "            <de>%s</de>\n"
            "            <en>%s</en>\n"
            "            <fr>%s</fr>\n"
            "        </text>" % (key, de, en, fr))
    if neu:
        s = s.replace("    </l10n>", "\n".join(neu) + "\n    </l10n>", 1)

    # --- 4. Titel und Beschreibung auf Franzoesisch ------------------------
    if "<fr>" not in re.search(r"<title>.*?</title>", s, re.S).group(0):
        s = re.sub(r"(<title>.*?</en>)",
                   lambda m: m.group(1) + "\n        <fr>" + TITEL_FR + "</fr>",
                   s, count=1, flags=re.S)

    if "</en>" in s and "<fr><![CDATA[" not in s:
        s = re.sub(r"(</en>\s*\n\s*</description>)",
                   lambda m: "</en>\n        <fr><![CDATA[" + BESCHREIBUNG_FR + "]]></fr>\n    </description>",
                   s, count=1)

    open(PFAD, "w", encoding="utf-8").write(s)
    print("Hilfetexte korrigiert : %d" % len(KORREKTUR))
    print("Franzoesisch ergaenzt : %d" % ergaenzt)
    print("Neue Schluessel       : %d" % len(neu))


if __name__ == "__main__":
    sys.exit(main())
