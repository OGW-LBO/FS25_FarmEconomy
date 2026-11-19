-- AOSettingsPage.lua
-- Welche Regler es im Mod-Tab gibt und welche Werte sie haben. Gezeichnet wird
-- in AOMenuPage. Feinheiten bleiben in der settings.xml bzw. bei aoConfig.
-- OGW

AOSettingsPage = {}

AOSettingsPage.LOG = "[AgrarOekonomie] "

-- faellt auf den Schluessel zurueck, damit nie eine leere Zeile entsteht
function AOSettingsPage.getText(key)
    if key == nil then
        return ""
    end
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n.getText ~= nil then
        if g_i18n:hasText(key) then
            local wert = g_i18n:getText(key)
            if wert ~= nil then
                return wert
            end
        end
    end
    return key
end

local t = AOSettingsPage.getText

-- art:
--   bool     Aus / An
--   faktor   x0.75
--   prozent  7.5 %
--   geld     Waehrungsbetrag
--   zahl     Zahl, optional mit Einheit
--   dezimal  zwei Nachkommastellen + einheit, bei 0 nullText
--   liste    feste Auswahl, texte = l10n-Schluessel

AOSettingsPage.ABSCHNITTE = {
    {
        -- Kopfzeile kommt zur Laufzeit aus AOAutomatik.getKopfText()
        titel     = "ao_sec_automatik",
        dynamisch = true,
        eintraege = {
            { modul = "ao", key = "autoAktiv",   art = "bool",
              label = "ao_ui_autoAktiv",   tipp = "ao_ui_autoAktiv_t" },
            -- Reihenfolge wie AOAutomatik.STUFEN
            { modul = "ao", key = "autoStufe",   art = "liste",
              texte = { "ao_opt_leicht", "ao_opt_normal", "ao_opt_schwer",
                        "ao_opt_realistisch", "ao_opt_eigene" },
              label = "ao_ui_autoStufe",   tipp = "ao_ui_autoStufe_t" },
            { modul = "ao", key = "autoZielMin", art = "geld", min = 500, max = 6000, step = 100,
              einheitText = "ao_unit_proHa",
              label = "ao_ui_autoZielMin", tipp = "ao_ui_autoZielMin_t" },
            { modul = "ao", key = "autoZielMax", art = "geld", min = 500, max = 6000, step = 100,
              einheitText = "ao_unit_proHa",
              label = "ao_ui_autoZielMax", tipp = "ao_ui_autoZielMax_t" },
        },
    },
    {
        titel = "ao_sec_preise",
        eintraege = {
            { modul = "ao", key = "preiseAktiv",   art = "bool",
              label = "ao_ui_preiseAktiv",   tipp = "ao_ui_preiseAktiv_t" },
            { modul = "ao", key = "preisFruechte", art = "faktor", min = 0.30, max = 1.20, step = 0.05,
              label = "ao_ui_preisFruechte", tipp = "ao_ui_preisFruechte_t" },
            { modul = "ao", key = "preisProdukte", art = "faktor", min = 0.30, max = 1.20, step = 0.05,
              label = "ao_ui_preisProdukte", tipp = "ao_ui_preisProdukte_t" },
        },
    },
    {
        titel = "ao_sec_bremse",
        eintraege = {
            { modul = "ao", key = "bremseAktiv",    art = "bool",
              label = "ao_ui_bremseAktiv",    tipp = "ao_ui_bremseAktiv_t" },
            { modul = "ao", key = "bremseAnteil",   art = "prozent", min = 0.05, max = 1.00, step = 0.05,
              label = "ao_ui_bremseAnteil",   tipp = "ao_ui_bremseAnteil_t" },
            { modul = "ao", key = "notbremseKonto", art = "geld", min = 0, max = 500000, step = 25000,
              label = "ao_ui_notbremseKonto", tipp = "ao_ui_notbremseKonto_t" },
            { modul = "ao", key = "karenzMonate",   art = "zahl", min = 0, max = 24, step = 1,
              einheitText = "ao_unit_monate",
              label = "ao_ui_karenzMonate",   tipp = "ao_ui_karenzMonate_t" },
        },
    },
    {
        titel = "ao_sec_fuhrpark",
        eintraege = {
            { modul = "fuhrpark", key = "enabled",           art = "bool",
              label = "ao_ui_fsEnabled", tipp = "ao_ui_fsEnabled_t" },
            { modul = "fuhrpark", key = "taxRatePerYear",    art = "prozent", min = 0.0, max = 0.20, step = 0.005,
              label = "ao_ui_fsTax",     tipp = "ao_ui_fsTax_t" },
            { modul = "fuhrpark", key = "upkeepRatePerYear", art = "prozent", min = 0.0, max = 0.30, step = 0.005,
              label = "ao_ui_fsUpkeep",  tipp = "ao_ui_fsUpkeep_t" },
            { modul = "fuhrpark", key = "ownedOnly",         art = "bool",
              label = "ao_ui_fsOwned",   tipp = "ao_ui_fsOwned_t" },
            { modul = "fuhrpark", key = "rabattRuhend",      art = "prozent", min = 0.0, max = 1.0, step = 0.05,
              label = "ao_ui_fsRuhend",  tipp = "ao_ui_fsRuhend_t" },
            { modul = "fuhrpark", key = "rabattUnterstand",  art = "prozent", min = 0.0, max = 1.0, step = 0.05,
              label = "ao_ui_fsDach",    tipp = "ao_ui_fsDach_t" },
            { modul = "fuhrpark", key = "rabattMinAnteil",   art = "prozent", min = 0.0, max = 1.0, step = 0.05,
              label = "ao_ui_fsRabattMin", tipp = "ao_ui_fsRabattMin_t" },
            -- 0 = monatlich, 1 = jaehrlich
            { modul = "fuhrpark", key = "billingMode",       art = "liste",
              texte = { "ao_opt_monatlich", "ao_opt_jaehrlich" },
              label = "ao_ui_fsBilling", tipp = "ao_ui_fsBilling_t" },
        },
    },
    {
        titel = "ao_sec_grundsteuer",
        eintraege = {
            { modul = "ao", key = "grundsteuerAktiv",   art = "bool",
              label = "ao_ui_gsAktiv", tipp = "ao_ui_gsAktiv_t" },
            { modul = "ao", key = "grundsteuerProJahr", art = "prozent", min = 0.0, max = 0.10, step = 0.005,
              label = "ao_ui_gsSatz",  tipp = "ao_ui_gsSatz_t" },
        },
    },
    {
        titel = "ao_sec_zins",
        eintraege = {
            { modul = "ao", key = "zinsAktiv",   art = "bool",
              label = "ao_ui_zinsAktiv",   tipp = "ao_ui_zinsAktiv_t" },
            { modul = "ao", key = "zinsSatz",    art = "prozent", min = 0.0, max = 0.10, step = 0.0025, stellen = 2,
              label = "ao_ui_zinsSatz",    tipp = "ao_ui_zinsSatz_t" },
            { modul = "ao", key = "zinsGrenze1", art = "geld", min = 0, max = 5000000, step = 50000,
              label = "ao_ui_zinsGrenze1", tipp = "ao_ui_zinsGrenze1_t" },
            { modul = "ao", key = "zinsGrenze2", art = "geld", min = 0, max = 10000000, step = 250000,
              label = "ao_ui_zinsGrenze2", tipp = "ao_ui_zinsGrenze2_t" },
        },
    },
    {
        titel = "ao_sec_reparatur",
        eintraege = {
            { modul = "reparatur", key = "grundfaktorReparatur", art = "faktor", min = 0.5, max = 3.0, step = 0.25,
              label = "ao_ui_roGrund",   tipp = "ao_ui_roGrund_t" },
            { modul = "reparatur", key = "faktorStunden",        art = "faktor", min = 0.0, max = 1.5, step = 0.1,
              label = "ao_ui_roStunden", tipp = "ao_ui_roStunden_t" },
            { modul = "reparatur", key = "faktorMax",            art = "faktor", min = 1.5, max = 4.0, step = 0.25,
              label = "ao_ui_roMax",     tipp = "ao_ui_roMax_t" },
            { modul = "reparatur", key = "tempoSchaden",         art = "faktor", min = 0.25, max = 3.0, step = 0.25,
              label = "ao_ui_roTempo",   tipp = "ao_ui_roTempo_t" },
        },
    },
    {
        titel = "ao_sec_helfer",
        eintraege = {
            { modul = "helfer", key = "aktiv",            art = "bool",
              label = "ao_ui_hlAktiv", tipp = "ao_ui_hlAktiv_t" },
            -- Reihenfolge wie HelferLohn.STUFE_*
            { modul = "helfer", key = "lohnStufe",        art = "liste",
              texte = { "ao_opt_azubi", "ao_opt_quer", "ao_opt_ausgelernt", "ao_opt_eigen" },
              label = "ao_ui_hlStufe", tipp = "ao_ui_hlStufe_t" },
            -- wie HelferLohn.SCHWER_*
            { modul = "helfer", key = "schwierigkeit",    art = "liste",
              texte = { "ao_opt_auto", "ao_opt_leicht", "ao_opt_normal", "ao_opt_schwer", "ao_opt_eigenePreise" },
              label = "ao_ui_hlNiveau", tipp = "ao_ui_hlNiveau_t" },
            -- 0 = Stundenlohn, 1 = Festpreis
            { modul = "helfer", key = "bezahlModus",      art = "liste",
              texte = { "ao_opt_stundenlohn", "ao_opt_festpreis" },
              label = "ao_ui_hlModus", tipp = "ao_ui_hlModus_t" },
            { modul = "helfer", key = "nurBeiErfolg",     art = "bool",
              label = "ao_ui_hlNurErfolg", tipp = "ao_ui_hlNurErfolg_t" },
            { modul = "helfer", key = "gratisBetrieb",    art = "bool",
              label = "ao_ui_hlGratis", tipp = "ao_ui_hlGratis_t" },
            { modul = "helfer", key = "zufallVerfuegbar", art = "bool",
              label = "ao_ui_hlZufall", tipp = "ao_ui_hlZufall_t" },
        },
    },
    {
        titel = "ao_sec_verbrauch",
        eintraege = {
            { modul = "ao", key = "verbrauchNurEigene", art = "bool",
              label = "ao_ui_vNurEigene", tipp = "ao_ui_vNurEigene_t" },
            { modul = "ao", key = "verbrauchBindegarn", art = "faktor", min = 0, max = 20, step = 0.5,
              label = "ao_ui_vTwine", tipp = "ao_ui_vTwine_t" },
            { modul = "ao", key = "verbrauchNetz",      art = "faktor", min = 0, max = 20, step = 0.5,
              label = "ao_ui_vNet",   tipp = "ao_ui_vNet_t" },
            { modul = "ao", key = "verbrauchFolie",     art = "faktor", min = 0, max = 20, step = 0.5,
              label = "ao_ui_vWrap",  tipp = "ao_ui_vWrap_t" },
        },
    },
    {
        titel = "ao_sec_sprit",
        eintraege = {
            { modul = "ao", key = "dieselAktiv",     art = "bool",
              label = "ao_ui_spAktiv",  tipp = "ao_ui_spAktiv_t" },
            { modul = "ao", key = "dieselFaktor",    art = "faktor", min = 0.10, max = 4.00, step = 0.05,
              label = "ao_ui_spFaktor", tipp = "ao_ui_spFaktor_t" },
            { modul = "ao", key = "dieselFaktorFahrt", art = "faktor", min = 0.10, max = 4.00, step = 0.05,
              label = "ao_ui_spFahrt",  tipp = "ao_ui_spFahrt_t" },
            { modul = "ao", key = "dieselProKwh",    art = "dezimal", min = 0.00, max = 0.60, step = 0.01,
              einheit = "l/kWh", nullText = "ao_ui_spKwhAus",
              label = "ao_ui_spKwh",    tipp = "ao_ui_spKwh_t" },
            { modul = "ao", key = "dieselLastkurve", art = "bool",
              label = "ao_ui_spKurve",  tipp = "ao_ui_spKurve_t" },
            { modul = "ao", key = "dieselAnzeige",   art = "bool",
              label = "ao_ui_spAnzeige", tipp = "ao_ui_spAnzeige_t" },
        },
    },
    {
        titel = "ao_sec_buch",
        eintraege = {
            { modul = "ao", key = "buchAktiv",    art = "bool",
              label = "ao_ui_buchAktiv",    tipp = "ao_ui_buchAktiv_t" },
            { modul = "ao", key = "buchSchwelle", art = "geld", min = 0, max = 2000, step = 50,
              label = "ao_ui_buchSchwelle", tipp = "ao_ui_buchSchwelle_t" },
        },
    },
    {
        -- AOMenuPage haengt darunter je Produktionsgebaeude eine Zeile an
        titel = "ao_sec_produktion",
        produktionen = true,
        eintraege = {
            { modul = "ao", key = "prodAktiv",     art = "bool",
              label = "ao_ui_prodAktiv",  tipp = "ao_ui_prodAktiv_t" },
            { modul = "ao", key = "prodFaktor",    art = "faktor", min = 0.25, max = 10.0, step = 0.25,
              label = "ao_ui_prodFaktor", tipp = "ao_ui_prodFaktor_t" },
            -- wie AOProduktion.kostenFaktor
            { modul = "ao", key = "prodKosten",    art = "liste",
              texte = { "ao_opt_kostenGleich", "ao_opt_kostenWurzel", "ao_opt_kostenVoll" },
              label = "ao_ui_prodKosten", tipp = "ao_ui_prodKosten_t" },
        },
    },
}

local function rundeAuf(wert, step)
    if step == nil or step <= 0 then
        return wert
    end
    return math.floor(wert / step + 0.5) * step
end

function AOSettingsPage.baueWerte(eintrag)
    if eintrag.art == "bool" then
        return { false, true }, { t("ao_opt_aus"), t("ao_opt_an") }
    end

    if eintrag.art == "liste" then
        local werte, texte = {}, {}
        for i, schluessel in ipairs(eintrag.texte) do
            werte[i] = i - 1        -- Index ab 0
            texte[i] = t(schluessel)
        end
        return werte, texte
    end

    local werte, texte = {}, {}
    local step = eintrag.step or 1
    local wert = eintrag.min or 0
    local max  = eintrag.max or 1

    local maxEintraege = 200

    while wert <= max + step * 0.001 and #werte < maxEintraege do
        local w = rundeAuf(wert, step)
        table.insert(werte, w)

        if eintrag.art == "faktor" then
            table.insert(texte, string.format("x%.2f", w))
        elseif eintrag.art == "dezimal" then
            if w == 0 and eintrag.nullText ~= nil then
                table.insert(texte, t(eintrag.nullText))
            else
                table.insert(texte, string.format("%.2f %s", w, eintrag.einheit or ""))
            end
        elseif eintrag.art == "prozent" then
            table.insert(texte, string.format("%." .. (eintrag.stellen or 1) .. "f %%", w * 100))
        elseif eintrag.art == "geld" then
            local geld = string.format("%d", w)
            if AgrarOekonomie ~= nil then
                geld = AgrarOekonomie.formatGeld(w)
            end
            if eintrag.einheitText ~= nil then
                geld = geld .. " " .. t(eintrag.einheitText)
            end
            table.insert(texte, geld)
        elseif eintrag.einheitText ~= nil then
            -- Leerzeichen hier, fuehrende Leerzeichen im XML-Text gehen verloren
            table.insert(texte, string.format("%d %s", math.floor(w + 0.5), t(eintrag.einheitText)))
        else
            table.insert(texte, string.format("%d%s", math.floor(w + 0.5), eintrag.einheit or ""))
        end

        wert = wert + step
    end

    return werte, texte
end

-- 1-basiert, bei Zahlen gewinnt der naechstliegende Wert
function AOSettingsPage.findeIndex(werte, aktuell)
    if aktuell == nil then
        return 1
    end

    if type(aktuell) == "boolean" then
        return aktuell and 2 or 1
    end

    local besterIndex, besteDistanz = 1, nil
    for i, w in ipairs(werte) do
        if type(w) == "number" then
            local d = math.abs(w - aktuell)
            if besteDistanz == nil or d < besteDistanz then
                besteDistanz = d
                besterIndex  = i
            end
        end
    end
    return besterIndex
end
