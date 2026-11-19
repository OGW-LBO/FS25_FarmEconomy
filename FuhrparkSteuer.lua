-- FuhrparkSteuer.lua
-- Bucht Steuer und laufende Kosten fuer jedes eigene Fahrzeug, monatlich oder
-- jaehrlich nach Fahrzeugwert. Abgerechnet wird nur auf dem Server.
-- OGW

FuhrparkSteuer = {}

FuhrparkSteuer.LOG = "[FuhrparkSteuer] "
FuhrparkSteuer.MOD_NAME = g_currentModName
FuhrparkSteuer.SPEC_NAME = "fuhrparkSteuerInfo"

-- Einstellungen, ueber settings.xml und fsConfig aenderbar
FuhrparkSteuer.CFG = {
    enabled                 = true,

    billingMode             = 0,      -- 0 monatlich, 1 jaehrlich

    -- Saetze pro Jahr, bezogen auf den Fahrzeugwert
    taxRatePerYear          = 0.02,
    upkeepRatePerYear       = 0.03,   -- Versicherung/Unterhalt

    useResaleValue          = true,   -- Verkaufswert statt Neupreis

    minCostPerVehicleMonth  = 5,

    -- Rabatt fuer Maschinen, die im Zeitraum nicht gelaufen sind. Wer sammelt,
    -- soll nicht fuer jeden abgemeldeten Schlepper im Schuppen voll zahlen.
    rabattRuhend            = 0.50,

    -- Rabatt fuer Fahrzeuge unterm Dach
    rabattUnterstand        = 0.30,

    -- Beide Rabatte zusammen nie unter diesen Anteil, sonst wird ein grosser Fuhrpark gratis
    rabattMinAnteil         = 0.20,

    ownedOnly               = true,   -- Leasing zahlt schon Gebuehr

    showNotification        = true,
    showInInfoBox           = true,

    -- nur falls die Periode nicht lesbar ist: so viele Tage = ein Monat
    daysPerMonth            = 1,
}

-- wird mit dem Spielstand gespeichert
FuhrparkSteuer.state = {
    initialisiert   = false,
    lastDay         = 0,
    lastPeriod      = 0,      -- 0 = unbekannt
    tageAkku        = 0,      -- fuer den Tage-Rueckfall
    monateSeitJahr  = 0,
    stunden         = {},     -- Betriebszeit je Fahrzeug bei der letzten Abrechnung
}

FuhrparkSteuer.bereit = false
FuhrparkSteuer.pollAkkuMs = 0
-- Ein Spieltag dauert selbst bei x120 noch rund 12 Minuten, 30 s reichen dicke
FuhrparkSteuer.POLL_INTERVALL_MS = 30000
FuhrparkSteuer.befehleRegistriert = false

FuhrparkSteuer.isServerCached = nil
FuhrparkSteuer.moneyTypeCached = nil

-- Status aendert sich in der Sitzung nicht, also merken
function FuhrparkSteuer.istServer()
    if FuhrparkSteuer.isServerCached ~= nil then
        return FuhrparkSteuer.isServerCached
    end

    local wert = false
    if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil then
        local v = g_currentMission:getIsServer()
        wert = (v == true)
    else
        wert = g_server ~= nil
    end

    if g_currentMission ~= nil then
        FuhrparkSteuer.isServerCached = wert
    end
    return wert
end

-- OTHER gibt es immer, die genaueren Typen nur wenn vorhanden
function FuhrparkSteuer.getMoneyType()
    if FuhrparkSteuer.moneyTypeCached ~= nil then
        return FuhrparkSteuer.moneyTypeCached
    end
    if MoneyType == nil then
        return 0
    end
    local mt = MoneyType.OTHER
    if MoneyType.PROPERTY_MAINTENANCE ~= nil then
        mt = MoneyType.PROPERTY_MAINTENANCE
    end
    if MoneyType.VEHICLE_RUNNING_COST ~= nil then
        mt = MoneyType.VEHICLE_RUNNING_COST
    end
    FuhrparkSteuer.moneyTypeCached = mt
    return mt
end

function FuhrparkSteuer.formatGeld(betrag)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local txt = g_i18n:formatMoney(betrag, 0, true, true)
        if txt ~= nil then
            return txt
        end
    end
    return string.format("%d", math.floor(betrag + 0.5))
end

function FuhrparkSteuer.getPeriode()
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

function FuhrparkSteuer.istBesteuerbar(vehicle)
    if vehicle == nil then
        return false
    end

    if vehicle.getSellPrice == nil and vehicle.getPrice == nil then
        return false
    end

    -- keine Paletten, Ballen, BigBags
    if vehicle.spec_motorized == nil and vehicle.spec_attachable == nil then
        return false
    end

    local farmId = vehicle.ownerFarmId
    if farmId == nil or farmId < 1 then
        return false
    end

    if FuhrparkSteuer.CFG.ownedOnly then
        if VehiclePropertyState ~= nil and VehiclePropertyState.LEASED ~= nil then
            if vehicle.propertyState == VehiclePropertyState.LEASED then
                return false
            end
        end
    end

    -- Neufahrzeuge eine Weile steuerfrei. vehicle.age zaehlt Spielmonate, nicht Tage.
    if AgrarOekonomie ~= nil and AgrarOekonomie.CFG ~= nil then
        local karenz = AgrarOekonomie.CFG.karenzMonate or 0
        if karenz > 0 and type(vehicle.age) == "number" then
            if vehicle.age < karenz then
                return false
            end
        elseif karenz > 0 and not AgrarOekonomie.karenzHinweis then
            AgrarOekonomie.karenzHinweis = true
            Logging.info(FuhrparkSteuer.LOG ..
                "vehicle.age nicht verfuegbar - Karenz fuer Neufahrzeuge inaktiv.")
        end
    end

    return true
end

function FuhrparkSteuer.getWert(vehicle)
    local cfg = FuhrparkSteuer.CFG
    local wert = 0
    if cfg.useResaleValue and vehicle.getSellPrice ~= nil then
        local v = vehicle:getSellPrice()
        if type(v) == "number" then wert = v end
    end
    if wert <= 0 and vehicle.getPrice ~= nil then
        local v = vehicle:getPrice()
        if type(v) == "number" then wert = v end
    end
    return wert or 0
end

function FuhrparkSteuer.getFahrzeugId(vehicle)
    if vehicle == nil then
        return nil
    end
    if vehicle.getUniqueId ~= nil then
        local id = vehicle:getUniqueId()
        if type(id) == "string" and id ~= "" then
            return id
        end
    end
    -- ohne Id gilt es als gearbeitet, also kein Rabatt
    return nil
end

-- operatingTime laeuft in ms und nur im Betrieb; eine Minute Toleranz fuers Rangieren
function FuhrparkSteuer.hatGearbeitet(vehicle)
    local id = FuhrparkSteuer.getFahrzeugId(vehicle)
    if id == nil then
        return true
    end

    local jetzt = vehicle.operatingTime
    if type(jetzt) ~= "number" then
        return true
    end

    local vorher = FuhrparkSteuer.state.stunden[id]
    if vorher == nil then
        return true
    end

    return (jetzt - vorher) > 60000
end

-- gleiche Innenraum-Maske, ueber die das Spiel entscheidet, ob es reinregnet
function FuhrparkSteuer.stehtUnterDach(vehicle)
    if g_currentMission == nil or g_currentMission.indoorMask == nil then
        return false
    end
    local maske = g_currentMission.indoorMask
    if maske.getIsIndoorAtWorldPosition == nil then
        return false
    end
    if vehicle == nil or vehicle.rootNode == nil or not entityExists(vehicle.rootNode) then
        return false
    end

    local x, _, z = getWorldTranslation(vehicle.rootNode)
    if x == nil then
        return false
    end
    return maske:getIsIndoorAtWorldPosition(x, z) == true
end

-- 1.0 = voller Satz
function FuhrparkSteuer.getRabattFaktor(vehicle)
    local cfg = FuhrparkSteuer.CFG
    local faktor = 1.0

    if (cfg.rabattRuhend or 0) > 0 and not FuhrparkSteuer.hatGearbeitet(vehicle) then
        faktor = faktor * (1 - cfg.rabattRuhend)
    end
    if (cfg.rabattUnterstand or 0) > 0 and FuhrparkSteuer.stehtUnterDach(vehicle) then
        faktor = faktor * (1 - cfg.rabattUnterstand)
    end

    local minimum = cfg.rabattMinAnteil or 0
    if faktor < minimum then
        faktor = minimum
    end
    return faktor
end

function FuhrparkSteuer.getMonatskosten(vehicle)
    local cfg = FuhrparkSteuer.CFG
    local wert = FuhrparkSteuer.getWert(vehicle)
    local jahres = wert * (cfg.taxRatePerYear + cfg.upkeepRatePerYear)
    local monat = (jahres / 12) * FuhrparkSteuer.getRabattFaktor(vehicle)
    if monat < cfg.minCostPerVehicleMonth then
        monat = cfg.minCostPerVehicleMonth
    end
    return monat
end

function FuhrparkSteuer.merkeStunden(vehicle)
    local id = FuhrparkSteuer.getFahrzeugId(vehicle)
    if id == nil then
        return
    end
    if type(vehicle.operatingTime) == "number" then
        FuhrparkSteuer.state.stunden[id] = vehicle.operatingTime
    end
end

-- Abrechnung -----------------------------------------------------------------

-- merken nur bei echter Abrechnung, die Vorschau darf die Stunden nicht anfassen
function FuhrparkSteuer.berechne(monate, merken)
    local proFarm = {}

    if g_currentMission == nil or g_currentMission.vehicleSystem == nil then
        return proFarm
    end
    local liste = g_currentMission.vehicleSystem.vehicles
    if liste == nil then
        return proFarm
    end

    for _, vehicle in ipairs(liste) do
        if FuhrparkSteuer.istBesteuerbar(vehicle) then
            local farmId = vehicle.ownerFarmId
            local monat = FuhrparkSteuer.getMonatskosten(vehicle)

            if proFarm[farmId] == nil then
                proFarm[farmId] = { summe = 0, anzahl = 0, ruhend = 0, unterDach = 0 }
            end
            proFarm[farmId].summe = proFarm[farmId].summe + monat * monate
            proFarm[farmId].anzahl = proFarm[farmId].anzahl + 1
            if not FuhrparkSteuer.hatGearbeitet(vehicle) then
                proFarm[farmId].ruhend = proFarm[farmId].ruhend + 1
            end
            if FuhrparkSteuer.stehtUnterDach(vehicle) then
                proFarm[farmId].unterDach = proFarm[farmId].unterDach + 1
            end

            -- erst nach der Kostenberechnung, sonst ist alles "ruhend"
            if merken then
                FuhrparkSteuer.merkeStunden(vehicle)
            end
        end
    end

    return proFarm
end

function FuhrparkSteuer.rechneAb(monate)
    if not FuhrparkSteuer.CFG.enabled then
        return
    end
    if not FuhrparkSteuer.istServer() then
        return
    end

    local proFarm = FuhrparkSteuer.berechne(monate, true)
    local mt = FuhrparkSteuer.getMoneyType()
    local jaehrlich = (monate >= 12)

    for farmId, daten in pairs(proFarm) do
        if daten.summe > 0 then
            -- Deckel und Notbremse koennen weniger oder nichts uebrig lassen
            if AgrarOekonomie ~= nil and AgrarOekonomie.vormerken ~= nil then
                AgrarOekonomie.vormerken(farmId, daten.summe, mt, "Fuhrparksteuer", function(echt)
                    FuhrparkSteuer.abgerechnet(farmId, daten, echt, jaehrlich)
                end)
            elseif g_currentMission ~= nil and g_currentMission.addMoney ~= nil then
                g_currentMission:addMoney(-daten.summe, farmId, mt, true, true)
                FuhrparkSteuer.abgerechnet(farmId, daten, daten.summe, jaehrlich)
            else
                Logging.warning(FuhrparkSteuer.LOG .. "addMoney not available (farm %s).",
                    tostring(farmId))
            end
        end
    end
end

function FuhrparkSteuer.abgerechnet(farmId, daten, betrag, jaehrlich)
    if betrag <= 0 then
        return
    end
    Logging.info(FuhrparkSteuer.LOG ..
        "Farm %d: %d vehicles (%d idle, %d indoors), -%d %s charged.",
        farmId, daten.anzahl, daten.ruhend, daten.unterDach,
        math.floor(betrag + 0.5),
        jaehrlich and "(yearly)" or "(monthly)")

    FuhrparkSteuer.zeigeMeldung(farmId, daten.anzahl, betrag, jaehrlich)
    if g_server ~= nil and g_server.broadcastEvent ~= nil
        and FuhrparkSteuerNotifyEvent ~= nil and FuhrparkSteuerNotifyEvent.new ~= nil then
        g_server:broadcastEvent(
            FuhrparkSteuerNotifyEvent.new(farmId, daten.anzahl, betrag, jaehrlich), false)
    end
end

function FuhrparkSteuer.zeigeMeldung(farmId, anzahl, betrag, jaehrlich)
    if not FuhrparkSteuer.CFG.showNotification then
        return
    end
    if g_currentMission == nil then
        return
    end

    local eigeneFarm = nil
    if g_currentMission.getFarmId ~= nil then
        eigeneFarm = g_currentMission:getFarmId()
    end
    if eigeneFarm ~= nil and eigeneFarm ~= farmId then
        return
    end

    local key = jaehrlich and "fs_meldungJahr" or "fs_meldungMonat"
    local text = key
    if g_i18n ~= nil and g_i18n.getText ~= nil
        and (g_i18n.hasText == nil or g_i18n:hasText(key)) then
        local t = g_i18n:getText(key)
        if type(t) == "string" then text = t end
    end
    -- kaputte Uebersetzung mit zu vielen Platzhaltern wuerde format crashen
    local ohneProzent = string.gsub(text, "%%%%", "")
    local _, anzahlPlatzhalter = string.gsub(ohneProzent, "%%", "")
    if anzahlPlatzhalter <= 2 then
        text = string.format(text, anzahl, FuhrparkSteuer.formatGeld(betrag))
    end

    local infoTyp = nil
    if FSBaseMission ~= nil then
        infoTyp = FSBaseMission.INGAME_NOTIFICATION_INFO
    end
    if g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil then
        g_currentMission.hud:addSideNotification(infoTyp, text, 5000)
    elseif g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(infoTyp, text)
    elseif g_currentMission.showBlinkingWarning ~= nil then
        g_currentMission:showBlinkingWarning(text, 5000)
    end
end

-- Monatswechsel --------------------------------------------------------------

-- neuePeriode ist nil, wenn ueber Tage gezaehlt wird
function FuhrparkSteuer.onMonatswechsel(neuePeriode)
    local st = FuhrparkSteuer.state
    st.monateSeitJahr = st.monateSeitJahr + 1

    if FuhrparkSteuer.CFG.billingMode == 1 then
        local jahresGrenze = false
        if neuePeriode ~= nil then
            if neuePeriode == 1 then
                jahresGrenze = true
            end
        end
        if st.monateSeitJahr >= 12 then
            jahresGrenze = true
        end

        if jahresGrenze then
            FuhrparkSteuer.rechneAb(12)
            st.monateSeitJahr = 0
        end
    else
        FuhrparkSteuer.rechneAb(1)
    end
    -- hier nicht speichern, nur zusammen mit dem Spielstand
end

function FuhrparkSteuer.pruefeZeit()
    if g_currentMission == nil or g_currentMission.environment == nil then
        return
    end
    local env = g_currentMission.environment
    local curDay = env.currentDay
    if curDay == nil then
        return
    end
    local curPeriod = FuhrparkSteuer.getPeriode()

    local st = FuhrparkSteuer.state

    -- beim ersten Mal nur Startwert merken
    if not st.initialisiert then
        st.initialisiert = true
        st.lastDay = curDay
        st.lastPeriod = curPeriod or 0
        st.tageAkku = 0
        return
    end

    if curPeriod ~= nil and curPeriod > 0 then
        if curPeriod ~= st.lastPeriod then
            st.lastPeriod = curPeriod
            st.lastDay = curDay
            FuhrparkSteuer.onMonatswechsel(curPeriod)
        end
    else
        -- keine Periode, also ueber Tage
        if curDay > st.lastDay then
            st.tageAkku = st.tageAkku + (curDay - st.lastDay)
            st.lastDay = curDay
            local proMonat = math.max(1, math.floor(FuhrparkSteuer.CFG.daysPerMonth))
            while st.tageAkku >= proMonat do
                st.tageAkku = st.tageAkku - proMonat
                FuhrparkSteuer.onMonatswechsel(nil)
            end
        end
    end
end

-- Speichern/Laden ------------------------------------------------------------

function FuhrparkSteuer.getStateFilename()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    local dir = g_currentMission.missionInfo.savegameDirectory
    if dir == nil then
        return nil
    end
    return dir .. "/FS25_FleetTax.xml"
end

function FuhrparkSteuer.speichern()
    if not FuhrparkSteuer.istServer() then
        return
    end
    local filename = FuhrparkSteuer.getStateFilename()
    if filename == nil or XMLFile == nil then
        return
    end
    local st = FuhrparkSteuer.state
    if XMLFile.create == nil then
        return
    end
    local xmlFile = XMLFile.create("fsStateXML", filename, "fuhrparkSteuer")
    if xmlFile == nil then
        return
    end
    xmlFile:setBool("fuhrparkSteuer.state#initialisiert", st.initialisiert == true)
    xmlFile:setInt("fuhrparkSteuer.state#lastDay", st.lastDay or 0)
    xmlFile:setInt("fuhrparkSteuer.state#lastPeriod", st.lastPeriod or 0)
    xmlFile:setInt("fuhrparkSteuer.state#tageAkku", st.tageAkku or 0)
    xmlFile:setInt("fuhrparkSteuer.state#monateSeitJahr", st.monateSeitJahr or 0)

    -- Betriebszeiten fuer den Ruhend-Rabatt
    local i = 0
    for id, stunden in pairs(st.stunden or {}) do
        if type(id) == "string" and type(stunden) == "number" then
            local key = string.format("fuhrparkSteuer.fahrzeuge.fahrzeug(%d)", i)
            xmlFile:setString(key .. "#id", id)
            xmlFile:setFloat(key .. "#betriebszeit", stunden)
            i = i + 1
        end
    end

    xmlFile:save()
    xmlFile:delete()
end

function FuhrparkSteuer.laden()
    local filename = FuhrparkSteuer.getStateFilename()
    if filename == nil or XMLFile == nil then
        return
    end
    if XMLFile.loadIfExists == nil then
        return
    end
    local xmlFile = XMLFile.loadIfExists("fsStateXML", filename)
    if xmlFile == nil then
        return
    end
    local st = FuhrparkSteuer.state
    st.initialisiert  = xmlFile:getBool("fuhrparkSteuer.state#initialisiert", false)
    st.lastDay        = xmlFile:getInt("fuhrparkSteuer.state#lastDay", 0)
    st.lastPeriod     = xmlFile:getInt("fuhrparkSteuer.state#lastPeriod", 0)
    st.tageAkku       = xmlFile:getInt("fuhrparkSteuer.state#tageAkku", 0)
    st.monateSeitJahr = xmlFile:getInt("fuhrparkSteuer.state#monateSeitJahr", 0)

    st.stunden = {}
    local i = 0
    while true do
        local key = string.format("fuhrparkSteuer.fahrzeuge.fahrzeug(%d)", i)
        local id = xmlFile:getString(key .. "#id", nil)
        if id == nil then
            break
        end
        local wert = xmlFile:getFloat(key .. "#betriebszeit", nil)
        if type(wert) == "number" then
            st.stunden[id] = wert
        end
        i = i + 1
    end

    xmlFile:delete()
end

-- Laden der Mod --------------------------------------------------------------

function FuhrparkSteuer:loadMap(name)
    if FuhrparkSteuer.istServer() then
        FuhrparkSteuer.laden()

        if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
            FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
                FSCareerMissionInfo.saveToXMLFile,
                function() FuhrparkSteuer.speichern() end)
        end
    end

    FuhrparkSteuer.bereit = true

    Logging.info(FuhrparkSteuer.LOG .. "loaded (server=%s, mode=%s).",
        tostring(FuhrparkSteuer.istServer()),
        FuhrparkSteuer.CFG.billingMode == 1 and "yearly" or "monthly")

    FuhrparkSteuer.registriereBefehle()
end

function FuhrparkSteuer:update(dt)
    if not FuhrparkSteuer.bereit then
        return
    end
    if not FuhrparkSteuer.CFG.enabled then
        return
    end
    if not FuhrparkSteuer.istServer() then
        return
    end

    FuhrparkSteuer.pollAkkuMs = FuhrparkSteuer.pollAkkuMs + (dt or 0)
    if FuhrparkSteuer.pollAkkuMs < FuhrparkSteuer.POLL_INTERVALL_MS then
        return
    end
    FuhrparkSteuer.pollAkkuMs = 0

    FuhrparkSteuer.pruefeZeit()
end

-- Konsole --------------------------------------------------------------------

function FuhrparkSteuer.getFahrzeug()
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        local fahrzeug = g_localPlayer:getCurrentVehicle()
        if fahrzeug ~= nil then
            return fahrzeug
        end
    end
    if g_currentMission ~= nil and g_currentMission.controlledVehicle ~= nil then
        return g_currentMission.controlledVehicle
    end
    return nil
end

function FuhrparkSteuer:consoleVehicle()
    local fahrzeug = FuhrparkSteuer.getFahrzeug()
    if fahrzeug == nil then
        return "No vehicle. Please enter a vehicle and run the command again."
    end

    local name = "?"
    if fahrzeug.getFullName ~= nil then
        local voll = fahrzeug:getFullName()
        if voll ~= nil then name = voll end
    end

    if not FuhrparkSteuer.istBesteuerbar(fahrzeug) then
        return string.format("%s: not taxable (not an owned vehicle/implement, or leased with 'ownedOnly').", name)
    end

    local cfg = FuhrparkSteuer.CFG
    local wert = FuhrparkSteuer.getWert(fahrzeug)
    local monat = FuhrparkSteuer.getMonatskosten(fahrzeug)
    local jahr = monat * 12

    return table.concat({
        string.format("=== %s ===", name),
        string.format("Value (%s)   : %s", cfg.useResaleValue and "resale" or "new", FuhrparkSteuer.formatGeld(wert)),
        string.format("Total rate/year   : %.1f %%", (cfg.taxRatePerYear + cfg.upkeepRatePerYear) * 100),
        string.format("Tax/fees          : %s /month   |   %s /year",
            FuhrparkSteuer.formatGeld(monat), FuhrparkSteuer.formatGeld(jahr)),
    }, "\n")
end

function FuhrparkSteuer:consoleStatus()
    local cfg = FuhrparkSteuer.CFG
    local st = FuhrparkSteuer.state

    local zeilen = {
        "=== Fleet Tax ==================================",
        string.format("Enabled             : %s", tostring(cfg.enabled)),
        string.format("Interval            : %s", cfg.billingMode == 1 and "yearly" or "monthly"),
        string.format("Tax rate/year       : %.1f %%", cfg.taxRatePerYear * 100),
        string.format("Upkeep rate/year    : %.1f %%", cfg.upkeepRatePerYear * 100),
        string.format("Total/year          : %.1f %% of value", (cfg.taxRatePerYear + cfg.upkeepRatePerYear) * 100),
        string.format("Value basis         : %s", cfg.useResaleValue and "resale value" or "purchase price"),
        string.format("Min per vehicle/mo  : %d", cfg.minCostPerVehicleMonth),
        string.format("Owned only (no lease): %s", tostring(cfg.ownedOnly)),
        string.format("Period seen         : %s   (fallback %d days/month)",
            tostring(FuhrparkSteuer.getPeriode() or "n/a"), cfg.daysPerMonth),
        string.format("Months since year   : %d", st.monateSeitJahr),
        "=== Next billing (preview) ===",
    }

    local monate = cfg.billingMode == 1 and 12 or 1
    local proFarm = FuhrparkSteuer.berechne(monate)
    local gab = false
    for farmId, daten in pairs(proFarm) do
        gab = true
        table.insert(zeilen, string.format(
            "  Farm %d: %d vehicles (%d idle, %d indoors)  ->  %s %s",
            farmId, daten.anzahl, daten.ruhend, daten.unterDach,
            FuhrparkSteuer.formatGeld(daten.summe),
            cfg.billingMode == 1 and "/year" or "/month"))
    end
    if not gab then
        table.insert(zeilen, "  (no taxable vehicles found)")
    end
    table.insert(zeilen, "=================================================")

    return table.concat(zeilen, "\n")
end

function FuhrparkSteuer:consoleConfig(name, wert)
    local cfg = FuhrparkSteuer.CFG

    if name == nil then
        local zeilen = { "=== Fleet Tax configuration ===" }
        local namen = {}
        for k, _ in pairs(cfg) do
            table.insert(namen, k)
        end
        table.sort(namen)
        for _, k in ipairs(namen) do
            table.insert(zeilen, string.format("  %-24s = %s", k, tostring(cfg[k])))
        end
        table.insert(zeilen, "Change with: fsConfig <name> <value>")
        return table.concat(zeilen, "\n")
    end

    if cfg[name] == nil then
        return string.format("Unknown setting '%s'. Call without arguments to list all.", tostring(name))
    end

    if wert == nil then
        return string.format("%s = %s", name, tostring(cfg[name]))
    end

    local neu
    if type(cfg[name]) == "boolean" then
        neu = (wert == "true" or wert == "1")
    else
        neu = tonumber(wert)
        if neu == nil then
            return string.format("'%s' is not a number.", tostring(wert))
        end
    end

    local alt = cfg[name]
    cfg[name] = neu

    local hinweis = "applies immediately"
    if FuhrparkSteuerSettings ~= nil and FuhrparkSteuerSettings.onLocalChange ~= nil then
        FuhrparkSteuerSettings.onLocalChange()
        hinweis = "applies immediately, saved and synchronized"
    end

    return string.format("%s: %s -> %s  (%s)", name, tostring(alt), tostring(neu), hinweis)
end

function FuhrparkSteuer:consoleReload()
    if FuhrparkSteuerSettings == nil or FuhrparkSteuerSettings.reload == nil then
        return "Settings manager not ready."
    end
    local ok, info = FuhrparkSteuerSettings.reload()
    if ok then
        return string.format("settings.xml reloaded and synchronized.\nFile: %s", tostring(info))
    else
        return tostring(info)
    end
end

function FuhrparkSteuer.registriereBefehle()
    if FuhrparkSteuer.befehleRegistriert then
        return
    end
    FuhrparkSteuer.befehleRegistriert = true

    if addConsoleCommand == nil then
        Logging.warning(FuhrparkSteuer.LOG .. "Console commands not registered: addConsoleCommand not available")
        return
    end

    addConsoleCommand("fsStatus", "Shows settings and the next billing (preview)",
        "consoleStatus", FuhrparkSteuer)
    addConsoleCommand("fsVehicle", "Shows value and tax/fees of the current vehicle",
        "consoleVehicle", FuhrparkSteuer)
    addConsoleCommand("fsConfig", "Shows or changes a mod setting",
        "consoleConfig", FuhrparkSteuer, "[name] [value]")
    addConsoleCommand("fsReloadConfig", "Reloads settings.xml while the game is running",
        "consoleReload", FuhrparkSteuer)
end

-- Info-Spezialisierung fuer die Zeile in der Fahrzeug-Infobox an alle
-- Typen mit "wearable" haengen
function FuhrparkSteuer.erweitereFahrzeugtypen(typeManager)
    if typeManager == nil or typeManager.typeName ~= "vehicle" then
        return
    end

    local vollerName = string.format("%s.%s",
        tostring(FuhrparkSteuer.MOD_NAME), FuhrparkSteuer.SPEC_NAME)

    local anzahl = 0
    for typeName, typeEntry in pairs(typeManager:getTypes()) do
        if typeEntry ~= nil and typeEntry.specializationsByName ~= nil then
            if typeEntry.specializationsByName["wearable"] ~= nil
                and typeEntry.specializationsByName[vollerName] == nil then
                if typeManager:addSpecialization(typeName, vollerName) then
                    anzahl = anzahl + 1
                end
            end
        end
    end

    Logging.info(FuhrparkSteuer.LOG .. "Info specialization attached to %d vehicle types.", anzahl)
end

if TypeManager ~= nil and TypeManager.validateTypes ~= nil then
    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes,
        FuhrparkSteuer.erweitereFahrzeugtypen)
else
    Logging.warning(FuhrparkSteuer.LOG .. "TypeManager.validateTypes not found - info box line stays off.")
end

addModEventListener(FuhrparkSteuer)
