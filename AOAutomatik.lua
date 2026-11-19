-- AOAutomatik.lua
-- Stellt die Preisfaktoren einmal im Spieljahr selbst nach, bis der Erloes je
-- Feldhektar zur gewaehlten Stufe passt. Laeuft nur auf dem Server.
-- Gemessen wird der Ernte-/Produkterloes vor dem Faktor, so schaukelt sich nichts auf.
-- Milch und Tiere zaehlen nicht mit, die fasst der Faktor ja gar nicht an.
-- OGW

AOAutomatik = {}

AOAutomatik.LOG = "[AgrarOekonomie] "

AOAutomatik.PERIODEN_PRO_JAHR = 12
AOAutomatik.MIN_HEKTAR        = 2.0     -- darunter ist die Bilanz nicht aussagekraeftig
AOAutomatik.FAKTOR_MIN        = 0.50
AOAutomatik.FAKTOR_MAX        = 1.00

-- EUR je Feldhektar und Jahr nach Faktor. Reihenfolge wie in AOSettingsPage!
AOAutomatik.STUFEN = {
    [0] = { min = 2600, max = 3600 },   -- Leicht
    [1] = { min = 2000, max = 2700 },   -- Normal
    [2] = { min = 1600, max = 2100 },   -- Schwer
    [3] = { min = 1300, max = 1800 },   -- Realistisch
}
AOAutomatik.STUFE_EIGENE = 4

AOAutomatik.state = {
    gestartet = false,   -- Messung laeuft (erst ab dem ersten Periodenwechsel)
    perioden  = 0,       -- abgeschlossene Perioden im laufenden Messjahr
    rohErloes = 0,       -- Summe vor Faktor
}

AOAutomatik.abonniert  = false
AOAutomatik.speicherHook = false

function AOAutomatik.klemme(wert, unten, oben)
    if wert < unten then
        return unten
    end
    if wert > oben then
        return oben
    end
    return wert
end

function AOAutomatik.getZiel()
    local cfg   = AgrarOekonomie.CFG
    local stufe = math.floor((cfg.autoStufe or 1) + 0.5)
    local zmin, zmax

    if stufe == AOAutomatik.STUFE_EIGENE then
        zmin = cfg.autoZielMin or 2000
        zmax = cfg.autoZielMax or 2700
    else
        local s = AOAutomatik.STUFEN[stufe] or AOAutomatik.STUFEN[1]
        zmin, zmax = s.min, s.max
    end

    if zmin > zmax then
        zmin, zmax = zmax, zmin
    end
    return zmin, zmax
end

function AOAutomatik.getFeldBesitzer(feld)
    if feld == nil or type(feld.farmland) ~= "table" then
        return nil
    end
    local land = feld.farmland
    local mgr  = g_farmlandManager
    if land.id ~= nil and mgr ~= nil and mgr.getFarmlandOwner ~= nil then
        return mgr:getFarmlandOwner(land.id)
    end
    return land.farmId
end

function AOAutomatik.getFeldHektar()
    local summe = 0

    if g_fieldManager ~= nil and g_fieldManager.getFields ~= nil then
        local felder = g_fieldManager:getFields()
        if type(felder) == "table" then
            for _, feld in pairs(felder) do
                if type(feld) == "table" then
                    local besitzer = AOAutomatik.getFeldBesitzer(feld)
                    if type(besitzer) == "number" and AgrarOekonomie.istSpielerFarm(besitzer) then
                        summe = summe + (tonumber(feld.areaHa) or 0)
                    end
                end
            end
        end
    end

    if summe > 0 then
        return summe
    end

    -- Notloesung Farmland-Flaeche, da sind Hof und Wege mit drin
    if AOGrundsteuer ~= nil and AOGrundsteuer.getLandwert ~= nil
            and g_farmManager ~= nil and g_farmManager.getFarms ~= nil then
        local farms = g_farmManager:getFarms()
        if type(farms) == "table" then
            for _, farm in pairs(farms) do
                local id = type(farm) == "table" and farm.farmId or nil
                if type(id) == "number" and AgrarOekonomie.istSpielerFarm(id) then
                    local _, _, ha = AOGrundsteuer.getLandwert(id)
                    summe = summe + (tonumber(ha) or 0)
                end
            end
        end
    end

    return summe
end

-- kommt aus dem Geld-Hook, betrag ist noch ohne Preisfaktor
function AOAutomatik.merkeErloes(moneyType, betrag)
    local st = AOAutomatik.state
    if not st.gestartet or betrag == nil or betrag <= 0 then
        return
    end
    local statistik = AgrarOekonomie.getStatistik(moneyType)
    if statistik == nil or AgrarOekonomie.PREIS_KATEGORIEN[statistik] == nil then
        return
    end
    st.rohErloes = st.rohErloes + betrag
end

-- Jahresbilanz ----------------------------------------------------------------

function AOAutomatik.melde(text)
    if AONotifyEvent == nil then
        return
    end
    if g_server ~= nil and g_server.broadcastEvent ~= nil then
        g_server:broadcastEvent(AONotifyEvent.new(0, text), false)
    end
    if AONotifyEvent.zeigeLokal ~= nil then
        AONotifyEvent.zeigeLokal(0, text)
    end
end

-- Einen von Hand ausserhalb der Grenzen gesetzten Wert nicht in die Gegenrichtung ziehen.
local function verschiebe(wert, delta)
    local neu = wert + delta
    if delta < 0 then
        neu = math.max(neu, math.min(AOAutomatik.FAKTOR_MIN, wert))
    else
        neu = math.min(neu, math.max(AOAutomatik.FAKTOR_MAX, wert))
    end
    return math.floor(neu * 100 + 0.5) / 100
end

function AOAutomatik.auswerten()
    local cfg = AgrarOekonomie.CFG
    local st  = AOAutomatik.state
    local ha  = AOAutomatik.getFeldHektar()

    if ha < AOAutomatik.MIN_HEKTAR or st.rohErloes <= 0 then
        Logging.info(AOAutomatik.LOG ..
            "Jahresbilanz uebersprungen: %.1f ha Feldflaeche, Roherloes %s.",
            ha, AgrarOekonomie.formatGeld(st.rohErloes))
        if cfg.autoAktiv then
            AOAutomatik.melde("@ao_msg_autoZuWenig")
        end
        return
    end

    local rohProHa        = st.rohErloes / ha
    local zielMin, zielMax = AOAutomatik.getZiel()
    local faktorAlt       = cfg.preisFruechte or 1.0
    local ergebnis        = rohProHa * faktorAlt
    local faktorNeu       = faktorAlt
    local schluessel      = "@ao_msg_autoPasst"

    local ausserhalb = (ergebnis < zielMin) or (ergebnis > zielMax)

    if cfg.autoAktiv and cfg.preiseAktiv and ausserhalb then
        local schritt = AOAutomatik.klemme(cfg.autoSchritt or 0.05, 0.01, 0.50)
        local raster  = (schritt >= 0.05) and 0.05 or 0.01
        local ideal   = ((zielMin + zielMax) / 2) / rohProHa

        local ziel = AOAutomatik.klemme(ideal, faktorAlt - schritt, faktorAlt + schritt)
        ziel = AOAutomatik.klemme(ziel, AOAutomatik.FAKTOR_MIN, AOAutomatik.FAKTOR_MAX)
        ziel = math.floor(ziel / raster + 0.5) * raster
        ziel = AOAutomatik.klemme(ziel, AOAutomatik.FAKTOR_MIN, AOAutomatik.FAKTOR_MAX)

        if math.abs(ziel - faktorAlt) >= 0.001 then
            faktorNeu  = ziel
            schluessel = "@ao_msg_autoAnpassung"
        else
            local amRand = faktorAlt <= AOAutomatik.FAKTOR_MIN + 0.001
                or faktorAlt >= AOAutomatik.FAKTOR_MAX - 0.001
            if amRand then
                schluessel = "@ao_msg_autoGrenze"
            end
        end
    end

    -- Produkte um denselben Betrag, sonst wird Verarbeiten zum Schlupfloch
    if faktorNeu ~= faktorAlt then
        local delta = faktorNeu - faktorAlt
        AOSettings.applyValue("ao", "preisFruechte", faktorNeu)
        AOSettings.applyValue("ao", "preisProdukte",
            verschiebe(cfg.preisProdukte or faktorAlt, delta))
    end

    cfg.autoLetzteBilanz  = ergebnis
    cfg.autoLetzterFaktor = cfg.preisFruechte or faktorNeu

    Logging.info(AOAutomatik.LOG ..
        "Jahresbilanz: Roherloes %s auf %.1f ha = %s/ha, nach Faktor %s/ha (Ziel %s-%s). Faktor %.2f -> %.2f.",
        AgrarOekonomie.formatGeld(st.rohErloes), ha,
        AgrarOekonomie.formatGeld(rohProHa), AgrarOekonomie.formatGeld(ergebnis),
        AgrarOekonomie.formatGeld(zielMin), AgrarOekonomie.formatGeld(zielMax),
        faktorAlt, cfg.autoLetzterFaktor)

    if cfg.autoAktiv then
        AOAutomatik.melde(string.format("%s|g:%.0f|g:%.0f|g:%.0f|f:%.2f|f:%.2f",
            schluessel, ergebnis, zielMin, zielMax, faktorAlt, cfg.autoLetzterFaktor))
    end
end

-- Ein Jahreswechsel-Event gibt es nicht, also 12 Periodenwechsel zaehlen.
function AOAutomatik.onPeriodeGewechselt(_)
    if not AgrarOekonomie.istServer() then
        return
    end

    local st = AOAutomatik.state

    if not st.gestartet then
        -- erst ab dem ersten vollen Monat messen
        st.gestartet = true
        st.perioden  = 0
        st.rohErloes = 0
        if AgrarOekonomie.CFG.autoAktiv then
            AOAutomatik.melde("@ao_msg_autoStart")
        end
    else
        st.perioden = st.perioden + 1
        if st.perioden >= AOAutomatik.PERIODEN_PRO_JAHR then
            AOAutomatik.auswerten()
            st.perioden  = 0
            st.rohErloes = 0
        end
    end

    AgrarOekonomie.CFG.autoPerioden = st.perioden
    -- Messstand nicht hier schreiben, nur beim Speichern - sonst ist die Datei dem Spielstand voraus

    if AOSettings ~= nil and AOSettings.onLocalChange ~= nil then
        AOSettings.onLocalChange()
    end
end

-- Anzeige ---------------------------------------------------------------------

-- nil, wenn die Vorlage nicht genau so viele %s hat wie Werte da sind
local function formatiereVorlage(vorlage, werte)
    if type(vorlage) ~= "string" then
        return nil
    end
    local ohneProzent = string.gsub(vorlage, "%%%%", "")
    local alle        = select(2, string.gsub(ohneProzent, "%%", ""))
    local nurS        = select(2, string.gsub(ohneProzent, "%%s", ""))
    if alle ~= nurS or nurS ~= #werte then
        return nil
    end
    local texte = {}
    for i = 1, #werte do
        texte[i] = tostring(werte[i])
    end
    return string.format(vorlage, unpack(texte))
end

-- Kopfzeile im Einstellungs-Tab, laeuft auch auf Clients
function AOAutomatik.getKopfText()
    local cfg = AgrarOekonomie.CFG
    local t   = AOSettingsPage ~= nil and AOSettingsPage.getText or tostring

    local text = nil
    if (cfg.autoLetzteBilanz or -1) >= 0 then
        text = formatiereVorlage(t("ao_auto_kopfBilanz"), {
            AgrarOekonomie.formatGeld(cfg.autoLetzteBilanz),
            string.format("%.2f", cfg.autoLetzterFaktor or 0) })
    else
        text = formatiereVorlage(t("ao_auto_kopfLaeuft"), {
            tostring(math.floor(cfg.autoPerioden or 0)) })
    end

    if text ~= nil then
        return text
    end
    return t("ao_sec_automatik")
end

function AOAutomatik.getStatusZeile()
    local cfg        = AgrarOekonomie.CFG
    local st         = AOAutomatik.state
    local zmin, zmax = AOAutomatik.getZiel()
    local bilanz     = "-"
    if (cfg.autoLetzteBilanz or -1) >= 0 then
        bilanz = AgrarOekonomie.formatGeld(cfg.autoLetzteBilanz) .. "/ha"
    end

    return string.format(
        "  Automatik: aktiv=%s  Stufe=%d  Ziel=%s-%s je ha  Monat=%d/%d  Roherloes=%s  Feldflaeche=%.1f ha  letzte Bilanz=%s",
        tostring(cfg.autoAktiv), math.floor(cfg.autoStufe or 1),
        AgrarOekonomie.formatGeld(zmin), AgrarOekonomie.formatGeld(zmax),
        st.perioden, AOAutomatik.PERIODEN_PRO_JAHR,
        AgrarOekonomie.formatGeld(st.rohErloes), AOAutomatik.getFeldHektar(), bilanz)
end

-- Speichern je Spielstand -----------------------------------------------------

-- Eigene Datei, weil AOGrundsteuer FS25_FarmEconomy.xml jedes Mal komplett neu schreibt.
function AOAutomatik.getStateFilename()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    -- nicht cachen, der Ordner wird beim Speichern neu angelegt
    local dir = g_currentMission.missionInfo.savegameDirectory
    if dir == nil then
        return nil
    end
    return dir .. "/FS25_FarmEconomy_Automatik.xml"
end

function AOAutomatik.speichern()
    if not AgrarOekonomie.istServer() then
        return
    end
    local filename = AOAutomatik.getStateFilename()
    if filename == nil or XMLFile == nil then
        return
    end

    local xml = XMLFile.create("aoAutoXML", filename, "farmEconomyAutomatik")
    if xml == nil then
        return
    end
    local st  = AOAutomatik.state
    local cfg = AgrarOekonomie.CFG
    xml:setBool("farmEconomyAutomatik#gestartet", st.gestartet == true)
    xml:setInt("farmEconomyAutomatik#perioden", st.perioden or 0)
    xml:setFloat("farmEconomyAutomatik#rohErloes", st.rohErloes or 0)
    xml:setFloat("farmEconomyAutomatik#letzteBilanz", cfg.autoLetzteBilanz or -1)
    xml:setFloat("farmEconomyAutomatik#letzterFaktor", cfg.autoLetzterFaktor or -1)
    xml:save()
    xml:delete()
end

function AOAutomatik.laden()
    local st  = AOAutomatik.state
    local cfg = AgrarOekonomie.CFG

    -- erst zuruecksetzen, die Anzeigewerte koennen noch von einem anderen Spielstand sein
    st.gestartet = false
    st.perioden  = 0
    st.rohErloes = 0
    cfg.autoLetzteBilanz  = -1
    cfg.autoLetzterFaktor = -1

    local filename = AOAutomatik.getStateFilename()
    if filename ~= nil and XMLFile ~= nil then
        local xml = XMLFile.loadIfExists("aoAutoXML", filename)
        if xml ~= nil then
            st.gestartet = xml:getBool("farmEconomyAutomatik#gestartet", false)
            st.perioden  = xml:getInt("farmEconomyAutomatik#perioden", 0)
            st.rohErloes = xml:getFloat("farmEconomyAutomatik#rohErloes", 0)
            cfg.autoLetzteBilanz  = xml:getFloat("farmEconomyAutomatik#letzteBilanz", -1)
            cfg.autoLetzterFaktor = xml:getFloat("farmEconomyAutomatik#letzterFaktor", -1)
            xml:delete()
        end
    end

    cfg.autoPerioden = st.perioden
end

-- aoAutoBilanz: Bilanz sofort ziehen, stellt die Faktoren wirklich nach
function AOAutomatik.befehlBilanz(_)
    if not AgrarOekonomie.istServer() then
        return AOAutomatik.LOG .. "Nur auf dem Server bzw. im Einzelspieler moeglich."
    end

    local st      = AOAutomatik.state
    local monate  = st.perioden
    local erloes  = st.rohErloes
    local hektar  = AOAutomatik.getFeldHektar()

    st.gestartet = true
    AOAutomatik.auswerten()

    st.perioden  = 0
    st.rohErloes = 0
    AgrarOekonomie.CFG.autoPerioden = 0
    if AOSettings ~= nil then
        AOSettings.onLocalChange()
    end

    return string.format("%sBilanz aus %d Monaten berechnet: Roherloes %s, Feldflaeche %.1f ha. Neue Messung beginnt.",
        AOAutomatik.LOG, monate, AgrarOekonomie.formatGeld(erloes), hektar)
end

function AOAutomatik:loadMap(name)
    if not AgrarOekonomie.istServer() then
        return
    end

    AOAutomatik.laden()

    if not AOAutomatik.abonniert then
        if g_messageCenter ~= nil and MessageType ~= nil and MessageType.PERIOD_CHANGED ~= nil then
            g_messageCenter:subscribe(MessageType.PERIOD_CHANGED,
                AOAutomatik.onPeriodeGewechselt, AOAutomatik)
            AOAutomatik.abonniert = true
        else
            Logging.warning(AOAutomatik.LOG ..
                "MessageType.PERIOD_CHANGED nicht verfuegbar - Automatik inaktiv.")
        end
    end

    if not AOAutomatik.speicherHook and FSCareerMissionInfo ~= nil
            and FSCareerMissionInfo.saveToXMLFile ~= nil then
        FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
            FSCareerMissionInfo.saveToXMLFile,
            function() AOAutomatik.speichern() end)
        AOAutomatik.speicherHook = true
    end

    if addConsoleCommand ~= nil then
        addConsoleCommand("aoAutoBilanz",
            "Berechnet sofort die Jahresbilanz der Automatik und stellt die Faktoren nach.",
            "befehlBilanz", AOAutomatik)
    end

    Logging.info(AOAutomatik.LOG .. "Automatik bereit (aktiv=%s, Stufe=%d, Monat %d/%d).",
        tostring(AgrarOekonomie.CFG.autoAktiv), math.floor(AgrarOekonomie.CFG.autoStufe or 1),
        AOAutomatik.state.perioden, AOAutomatik.PERIODEN_PRO_JAHR)
end

function AOAutomatik:deleteMap()
    if AOAutomatik.abonniert and g_messageCenter ~= nil and g_messageCenter.unsubscribeAll ~= nil then
        g_messageCenter:unsubscribeAll(AOAutomatik)
    end
    AOAutomatik.abonniert = false
    AOAutomatik.state = { gestartet = false, perioden = 0, rohErloes = 0 }
end

addModEventListener(AOAutomatik)
