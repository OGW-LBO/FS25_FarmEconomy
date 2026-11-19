-- AOGrundsteuer.lua
-- Grundsteuer auf gekauftes Land, monatlich nach Landwert. Standard ist aus.
-- Gebucht wird ueber AgrarOekonomie.vormerken, also mit Deckel und Notbremse.
-- OGW

AOGrundsteuer = {}

AOGrundsteuer.LOG = "[AgrarOekonomie] "

AOGrundsteuer.state = {
    initialisiert = false,
    lastDay       = 0,
    lastPeriod    = 0,
    tageAkku      = 0,
}

AOGrundsteuer.bereit       = false
AOGrundsteuer.letzterWert  = {}   -- [farmId] = zuletzt ermittelter Landwert

-- Summe der Kaufpreise. farmland.price hat den priceScale der Karte schon
-- drin, sonst Flaeche mal Hektarpreis.
function AOGrundsteuer.getLandwert(farmId)
    local wert, anzahl, hektar = 0, 0, 0

    if g_farmlandManager == nil or g_farmlandManager.getFarmlands == nil then
        return 0, 0, 0
    end

    local proHa = 0
    if g_farmlandManager.getPricePerHa ~= nil then
        local p = g_farmlandManager:getPricePerHa()
        if type(p) == "number" then
            proHa = p
        end
    end

    local liste = g_farmlandManager:getFarmlands()
    if type(liste) ~= "table" then
        return 0, 0, 0
    end

    for _, farmland in pairs(liste) do
        if type(farmland) == "table" and farmland.id ~= nil then
            local besitzer = nil
            if g_farmlandManager.getFarmlandOwner ~= nil then
                besitzer = g_farmlandManager:getFarmlandOwner(farmland.id)
            elseif farmland.farmId ~= nil then
                besitzer = farmland.farmId
            end

            if besitzer == farmId then
                local ha = tonumber(farmland.areaInHa) or 0
                local p  = tonumber(farmland.price)

                if p == nil or p <= 0 then
                    p = ha * proHa
                end

                wert   = wert + p
                hektar = hektar + ha
                anzahl = anzahl + 1
            end
        end
    end

    return wert, anzahl, hektar
end

-- Abrechnung ------------------------------------------------------------------

function AOGrundsteuer.getMoneyType()
    if MoneyType == nil then
        return nil
    end
    if MoneyType.PROPERTY_MAINTENANCE ~= nil then
        return MoneyType.PROPERTY_MAINTENANCE
    end
    return MoneyType.OTHER
end

-- monate: 1 oder 12
function AOGrundsteuer.rechneAb(monate)
    local cfg = AgrarOekonomie.CFG

    if not cfg.grundsteuerAktiv then
        return
    end
    if not AgrarOekonomie.istServer() then
        return
    end
    if g_farmManager == nil or g_farmManager.getFarms == nil then
        return
    end

    local satz = (cfg.grundsteuerProJahr or 0) / 12.0 * (monate or 1)
    if satz <= 0 then
        return
    end

    local mt    = AOGrundsteuer.getMoneyType()
    local farms = g_farmManager:getFarms()
    if type(farms) ~= "table" then
        return
    end

    for _, farm in pairs(farms) do
        local farmId = type(farm) == "table" and farm.farmId or nil
        if farmId ~= nil and AgrarOekonomie.istSpielerFarm(farmId) then
            local wert, anzahl, hektar = AOGrundsteuer.getLandwert(farmId)
            AOGrundsteuer.letzterWert[farmId] = wert

            if wert > 0 then
                AgrarOekonomie.vormerken(farmId, wert * satz, mt, "Grundsteuer", function(echt)
                    if echt <= 0 then
                        return
                    end
                    Logging.info(AOGrundsteuer.LOG ..
                        "Grundsteuer Farm %d: %d Flaechen, %.1f ha, Landwert %s -> %s abgebucht.",
                        farmId, anzahl, hektar,
                        AgrarOekonomie.formatGeld(wert),
                        AgrarOekonomie.formatGeld(echt))

                    if cfg.meldungen then
                        AOGrundsteuer.zeigeMeldung(farmId, hektar, echt)
                    end
                end)
            end
        end
    end
end

function AOGrundsteuer.zeigeMeldung(farmId, hektar, betrag)
    -- Schluessel statt fertigem Text, uebersetzt wird beim Client
    local text = string.format("@ao_msg_grundsteuer|g:%.0f|n:%.1f", betrag, hektar)
    if AONotifyEvent == nil then
        return
    end
    if AgrarOekonomie.istServer() and g_server ~= nil and g_server.broadcastEvent ~= nil then
        g_server:broadcastEvent(AONotifyEvent.new(farmId, text), false)
    end
    if AONotifyEvent.zeigeLokal ~= nil then
        AONotifyEvent.zeigeLokal(farmId, text)
    end
end

-- Zeitsteuerung ---------------------------------------------------------------

-- Zins haengt hier mit dran, so gibt es nur einen Monatszaehler.
function AOGrundsteuer.monatswechsel()
    AOGrundsteuer.rechneAb(1)
    if AOZins ~= nil and AOZins.verzinse ~= nil then
        AOZins.verzinse()
    end
end

function AOGrundsteuer.getPeriode()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then
        return nil
    end
    if env.currentPeriod ~= nil then
        return env.currentPeriod
    end
    if env.currentMonth ~= nil then
        return env.currentMonth
    end
    return nil
end

function AOGrundsteuer.pruefeZeit()
    if g_currentMission == nil or g_currentMission.environment == nil then
        return
    end

    local env    = g_currentMission.environment
    local curDay = env.currentDay
    if curDay == nil then
        return
    end

    local curPeriod = AOGrundsteuer.getPeriode()
    local st        = AOGrundsteuer.state

    -- erster Start: nur Referenz merken
    if not st.initialisiert then
        st.initialisiert = true
        st.lastDay       = curDay
        st.lastPeriod    = curPeriod or 0
        st.tageAkku      = 0
        -- nicht hier speichern, nur zusammen mit dem Spielstand
        return
    end

    if curPeriod ~= nil and curPeriod > 0 then
        if curPeriod ~= st.lastPeriod then
            st.lastPeriod = curPeriod
            st.lastDay    = curDay
            AOGrundsteuer.monatswechsel()
        end
    else
        if curDay > st.lastDay then
            st.tageAkku = st.tageAkku + (curDay - st.lastDay)
            st.lastDay  = curDay

            local proMonat = 1
            if FuhrparkSteuer ~= nil and FuhrparkSteuer.CFG ~= nil then
                proMonat = math.max(1, math.floor(FuhrparkSteuer.CFG.daysPerMonth or 1))
            end

            while st.tageAkku >= proMonat do
                st.tageAkku = st.tageAkku - proMonat
                AOGrundsteuer.monatswechsel()
            end
        end
    end
end

-- Spielstand ------------------------------------------------------------------

function AOGrundsteuer.getStateFilename()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    local dir = g_currentMission.missionInfo.savegameDirectory
    if dir == nil then
        return nil
    end
    return dir .. "/FS25_FarmEconomy.xml"
end

function AOGrundsteuer.speichern()
    if not AgrarOekonomie.istServer() then
        return
    end

    local filename = AOGrundsteuer.getStateFilename()
    if filename == nil or XMLFile == nil then
        return
    end

    local xmlFile = XMLFile.create("aoStateXML", filename, "agrarOekonomie")
    if xmlFile == nil then
        return
    end
    local st = AOGrundsteuer.state
    xmlFile:setBool("agrarOekonomie.grundsteuer#initialisiert", st.initialisiert == true)
    xmlFile:setInt("agrarOekonomie.grundsteuer#lastDay", st.lastDay or 0)
    xmlFile:setInt("agrarOekonomie.grundsteuer#lastPeriod", st.lastPeriod or 0)
    xmlFile:setInt("agrarOekonomie.grundsteuer#tageAkku", st.tageAkku or 0)
    xmlFile:save()
    xmlFile:delete()
end

function AOGrundsteuer.laden()
    local filename = AOGrundsteuer.getStateFilename()
    if filename == nil or XMLFile == nil then
        return
    end

    local xmlFile = XMLFile.loadIfExists("aoStateXML", filename)
    if xmlFile == nil then
        return
    end
    local st = AOGrundsteuer.state
    st.initialisiert = xmlFile:getBool("agrarOekonomie.grundsteuer#initialisiert", false)
    st.lastDay       = xmlFile:getInt("agrarOekonomie.grundsteuer#lastDay", 0)
    st.lastPeriod    = xmlFile:getInt("agrarOekonomie.grundsteuer#lastPeriod", 0)
    st.tageAkku      = xmlFile:getInt("agrarOekonomie.grundsteuer#tageAkku", 0)
    xmlFile:delete()
end

function AOGrundsteuer:loadMap(name)
    if AgrarOekonomie.istServer() then
        AOGrundsteuer.laden()

        if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
            FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
                FSCareerMissionInfo.saveToXMLFile,
                function() AOGrundsteuer.speichern() end)
        end
    end

    AOGrundsteuer.bereit = true
    Logging.info(AOGrundsteuer.LOG .. "Grundsteuer bereit (aktiv=%s).",
        tostring(AgrarOekonomie.CFG.grundsteuerAktiv))
end

function AOGrundsteuer:update(dt)
    if not AOGrundsteuer.bereit then
        return
    end
    if not AgrarOekonomie.istServer() then
        return
    end
    AOGrundsteuer.pruefeZeit()
end

addModEventListener(AOGrundsteuer)
