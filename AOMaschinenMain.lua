-- AOMaschinenMain.lua
-- Haengt aoMaschinen an alle Fahrzeuge und Geraete, bucht einmal am Tag
-- Unterhalt und Leasing je Fahrzeug, stellt die Zahlen fuer das
-- Fuhrpark-Fenster zusammen und bringt die Konsolenbefehle mit
-- (aoMaschinen, aoMaschinenListe).
-- OGW

AOMaschinenMain = {}

AOMaschinenMain.LOG       = "[AgrarOekonomie] "
AOMaschinenMain.MOD_NAME  = g_currentModName
AOMaschinenMain.SPEC_NAME = "aoMaschinen"
AOMaschinenMain.TAKT_MS   = 10000

AOMaschinenMain.takt       = 0
AOMaschinenMain.letzterTag = nil
AOMaschinenMain.bereit     = false

-- zuletzt erhaltenes Paket fuer das Fenster, auf dem Client vom Server
AOMaschinenMain.paket      = nil
AOMaschinenMain.wartetAuf  = nil

function AOMaschinenMain.erweitereFahrzeugtypen(typeManager)
    if typeManager == nil or typeManager.typeName ~= "vehicle" then
        return
    end

    local vollerName = string.format("%s.%s",
        tostring(AOMaschinenMain.MOD_NAME), AOMaschinenMain.SPEC_NAME)

    local anzahl = 0
    for typeName, typeEntry in pairs(typeManager:getTypes()) do
        local specs = typeEntry ~= nil and typeEntry.specializationsByName or nil
        if specs ~= nil and specs["wearable"] ~= nil
                and (specs["motorized"] ~= nil or specs["attachable"] ~= nil)
                and specs[vollerName] == nil then
            if typeManager:addSpecialization(typeName, vollerName) then
                anzahl = anzahl + 1
            end
        end
    end

    Logging.info(AOMaschinenMain.LOG .. "Maschinenkosten an %d Fahrzeugtypen angehaengt.", anzahl)
end

if TypeManager ~= nil and TypeManager.validateTypes ~= nil then
    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes,
        AOMaschinenMain.erweitereFahrzeugtypen)
else
    Logging.warning(AOMaschinenMain.LOG .. "TypeManager.validateTypes nicht gefunden, Maschinenkosten bleiben aus.")
end

local function geld(betrag)
    if AgrarOekonomie ~= nil and AgrarOekonomie.formatGeld ~= nil then
        return AgrarOekonomie.formatGeld(betrag or 0)
    end
    return string.format("%d", math.floor((betrag or 0) + 0.5))
end

function AOMaschinenMain.istErfasst(vehicle)
    if vehicle == nil or vehicle.isDeleted or vehicle.aoMkFaehig ~= true then
        return false
    end
    local farmId = vehicle.ownerFarmId
    if farmId == nil or farmId < 1 then
        return false
    end
    if AgrarOekonomie ~= nil and AgrarOekonomie.istSpielerFarm ~= nil
            and not AgrarOekonomie.istSpielerFarm(farmId) then
        return false
    end
    if VehiclePropertyState == nil then
        return false
    end
    return vehicle.propertyState == VehiclePropertyState.OWNED
        or vehicle.propertyState == VehiclePropertyState.LEASED
end

local function eigeneFarm()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        local farmId = g_currentMission:getFarmId()
        if type(farmId) == "number" and farmId >= 1 then
            return farmId
        end
    end
    return nil
end

function AOMaschinenMain.pruefen()
    if not AOMaschinen.erfassenAktiv() then
        return
    end
    if g_currentMission == nil or g_currentMission.vehicleSystem == nil
            or g_currentMission.vehicleSystem.vehicles == nil then
        return
    end

    local jahr = AOMaschinen.aktuellesJahr()
    local tag = AgrarOekonomie.getTag()
    local tage = 0
    if AOMaschinenMain.letzterTag == nil or tag < AOMaschinenMain.letzterTag then
        AOMaschinenMain.letzterTag = tag
    elseif tag > AOMaschinenMain.letzterTag then
        tage = math.min(tag - AOMaschinenMain.letzterTag, 31)
        AOMaschinenMain.letzterTag = tag
    end

    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
        if AOMaschinenMain.istErfasst(vehicle) then
            AOMaschinen.getJahresKonto(vehicle, jahr)

            local geleast = AOMaschinen.istGeleast(vehicle)
            local proTag, proStunde = -1, -1
            if geleast then
                proTag, proStunde = AOMaschinen.leasingSaetze(vehicle)
            end

            if tage > 0 then
                AOMaschinen.buchen(vehicle, "tage", tage)
                if geleast then
                    if proTag >= 0 then
                        AOMaschinen.buchen(vehicle, "leasing", proTag * tage)
                    end
                elseif vehicle.getDailyUpkeep ~= nil and AOMaschinen.getStoreItem(vehicle) ~= nil then
                    local unterhalt = vehicle:getDailyUpkeep()
                    if type(unterhalt) == "number" and unterhalt > 0 then
                        AOMaschinen.buchen(vehicle, "unterhalt", unterhalt * tage)
                    end
                end
            end

            local ms = AOMaschinen.getMs(vehicle)
            if geleast and proStunde > 0 and vehicle.aoMkLeasingMs ~= nil and ms > vehicle.aoMkLeasingMs then
                AOMaschinen.buchen(vehicle, "leasing",
                    (ms - vehicle.aoMkLeasingMs) / AOMaschinen.MS_JE_STUNDE * proStunde)
            end
            vehicle.aoMkLeasingMs = ms
        end
    end
end

-- Fuhrpark-Kosten aus FuhrparkSteuer. posten = { { vehicle, betrag } },
-- gewollt ist deren Summe, echt das, was die Bremse durchgelassen hat.
function AOMaschinenMain.verteileFuhrpark(posten, gewollt, echt)
    if posten == nil or gewollt == nil or gewollt <= 0 or echt == nil or echt <= 0 then
        return
    end
    local anteil = math.min(1, echt / gewollt)
    for _, p in ipairs(posten) do
        if AOMaschinenMain.istErfasst(p.vehicle) then
            AOMaschinen.buchen(p.vehicle, "fuhrpark", p.betrag * anteil)
        end
    end
end

function AOMaschinenMain.erstellePaket(farmId, wahl)
    local paket = { farmId = farmId, wahl = wahl, aktiv = AOMaschinen.erfassenAktiv(), eintraege = {} }
    if not paket.aktiv or g_currentMission == nil or g_currentMission.vehicleSystem == nil then
        return paket
    end
    local jahr = AOMaschinen.aktuellesJahr()
    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles or {}) do
        if AOMaschinenMain.istErfasst(vehicle) and vehicle.ownerFarmId == farmId then
            AOMaschinen.getJahresKonto(vehicle, jahr)
            local r = AOMaschinen.eintrag(vehicle, wahl)
            if r ~= nil then
                table.insert(paket.eintraege, r)
            end
        end
    end
    return paket
end

function AOMaschinenMain.anfordern(wahl)
    local farmId = eigeneFarm()
    if farmId == nil then
        AOMaschinenMain.paket = nil
        return
    end
    if AgrarOekonomie.istServer() then
        AOMaschinenMain.paket = AOMaschinenMain.erstellePaket(farmId, wahl)
        AOMaschinenMain.wartetAuf = nil
        return
    end
    if g_client ~= nil and g_client.getServerConnection ~= nil and AOMaschinenEvent ~= nil then
        local conn = g_client:getServerConnection()
        if conn ~= nil and conn.sendEvent ~= nil then
            AOMaschinenMain.wartetAuf = wahl
            conn:sendEvent(AOMaschinenEvent.new(true, farmId, wahl, nil))
        end
    end
end

function AOMaschinenMain.empfange(paket)
    AOMaschinenMain.paket = paket
    AOMaschinenMain.wartetAuf = nil
    if AOHofPC ~= nil and AOHofPC.aktualisiereOffenes ~= nil then
        AOHofPC.aktualisiereOffenes()
    end
end

local ZEITRAEUME = { jahr = "dieses Spieljahr", vorjahr = "voriges Spieljahr", gesamt = "seit Beginn der Erfassung" }

local function wahlLesen(wahl)
    if wahl == nil or ZEITRAEUME[wahl] == nil then
        return "jahr"
    end
    return wahl
end

local function zahl(wert, muster)
    if wert == nil then
        return "-"
    end
    return string.format(muster, wert)
end

local function eigenesFahrzeug()
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        local fahrzeug = g_localPlayer:getCurrentVehicle()
        if fahrzeug ~= nil then
            return fahrzeug
        end
    end
    if g_currentMission ~= nil then
        return g_currentMission.controlledVehicle
    end
    return nil
end

local function nurAufServer()
    if AgrarOekonomie ~= nil and not AgrarOekonomie.istServer() then
        return "Die Maschinenkosten zaehlt nur der Server. Im Mehrspieler bitte an der Server-Konsole aufrufen oder den Hof-PC (Strg+K) nutzen."
    end
    if not AOMaschinen.erfassenAktiv() then
        return "Maschinenkosten sind ausgeschaltet (Einstellung mkAktiv)."
    end
    return nil
end

local function satz(wert)
    if wert == nil or wert < 0 then
        return "unbekannt"
    end
    return geld(wert)
end

function AOMaschinenMain.detail(vehicle, wahl)
    local zeilen = {}
    local e = AOMaschinen.auswerten(vehicle, wahl)
    table.insert(zeilen, string.format("=== %s  (%s)", AOMaschinen.getName(vehicle), ZEITRAEUME[wahl]))
    if e == nil then
        table.insert(zeilen, "  Fuer diesen Zeitraum gibt es noch keine Zahlen.")
        return zeilen
    end

    local status = e.geleast and "geleast" or "Eigentum"
    if e.altbestand and wahl == "gesamt" then
        status = status .. ", Erfassung begann mit vorhandenen Stunden"
    end
    table.insert(zeilen, string.format("  Status          : %s", status))
    table.insert(zeilen, string.format("  Betriebsstunden : %.1f h an %d Tagen", e.stunden, e.tage))
    table.insert(zeilen, string.format("  Auslastung      : %s", zahl(e.auslastung, "%.1f h je Spielmonat")))
    table.insert(zeilen, string.format("  Zustand         : %.0f %%", e.zustand * 100))

    local sorten = {}
    for _, k in ipairs(e.kraftstoff) do
        table.insert(sorten, string.format("%s %.0f l (%s)", k.typ, k.liter, geld(k.kosten)))
    end
    table.insert(zeilen, string.format("  Kraftstoff      : %s", #sorten > 0 and table.concat(sorten, ", ") or "-"))
    table.insert(zeilen, string.format("  Flaeche         : %.2f ha selbst, %.2f ha mit Anbaugeraeten", e.ha, e.haGezogen))
    table.insert(zeilen, "  Kosten:")
    table.insert(zeilen, string.format("  Wertverlust     : %s", geld(e.wertverlust)))
    table.insert(zeilen, string.format("  Reparaturen     : %s", geld(e.reparatur)))
    table.insert(zeilen, string.format("  Kraftstoff      : %s", geld(e.sprit)))
    table.insert(zeilen, string.format("  Unterhalt Spiel : %s", geld(e.unterhalt)))
    table.insert(zeilen, string.format("  Fuhrpark-Kosten : %s", geld(e.fuhrpark)))
    table.insert(zeilen, string.format("  Leasing         : %s", geld(e.leasing)))
    table.insert(zeilen, string.format("  Summe           : %s", geld(e.summe)))
    table.insert(zeilen, "  Kennzahlen:")
    table.insert(zeilen, string.format("  je Stunde       : %s", e.proStunde ~= nil and geld(e.proStunde) or "-"))
    table.insert(zeilen, string.format("  je Hektar       : %s", e.proHa ~= nil and geld(e.proHa) or "-"))
    table.insert(zeilen, string.format("  Liter           : %s   %s",
        zahl(e.literProStunde, "%.1f l/h"), zahl(e.literProHa, "%.1f l/ha")))
    table.insert(zeilen, string.format("  Leasingsaetze   : je Tag %s, je Stunde %s", satz(e.leasTag), satz(e.leasStunde)))
    if e.leasingGleich ~= nil then
        table.insert(zeilen, string.format("  Besitz / Leasing: %s / %s ohne Kraftstoff und Anzahlung",
            geld(e.besitz), geld(e.leasingGleich)))
    end
    return zeilen
end

function AOMaschinenMain.befehlFahrzeug(_, wahl)
    local fehler = nurAufServer()
    if fehler ~= nil then
        return fehler
    end
    wahl = wahlLesen(wahl)

    local fahrzeug = eigenesFahrzeug()
    if fahrzeug == nil then
        return "Kein Fahrzeug. Bitte einsteigen. Fuer alle Fahrzeuge: aoMaschinenListe"
    end
    if not AOMaschinenMain.istErfasst(fahrzeug) then
        return string.format("%s wird nicht erfasst (nicht im Besitz oder geleast).", AOMaschinen.getName(fahrzeug))
    end

    local zeilen = AOMaschinenMain.detail(fahrzeug, wahl)
    if fahrzeug.getChildVehicles ~= nil then
        for _, kind in ipairs(fahrzeug:getChildVehicles() or {}) do
            if kind ~= fahrzeug and AOMaschinenMain.istErfasst(kind) then
                for _, zeile in ipairs(AOMaschinenMain.detail(kind, wahl)) do
                    table.insert(zeilen, zeile)
                end
            end
        end
    end

    if EconomyManager ~= nil then
        local konstanten = {}
        for k, v in pairs(EconomyManager) do
            if type(v) == "number" and type(k) == "string" and string.find(k, "LEAS") ~= nil then
                table.insert(konstanten, string.format("%s=%s", k, tostring(v)))
            end
        end
        table.sort(konstanten)
        if #konstanten > 0 then
            table.insert(zeilen, "Leasing-Konstanten: " .. table.concat(konstanten, ", "))
        end
    end
    return table.concat(zeilen, "\n")
end

function AOMaschinenMain.befehlListe(_, wahl)
    local fehler = nurAufServer()
    if fehler ~= nil then
        return fehler
    end
    wahl = wahlLesen(wahl)

    local farm = nil
    if g_dedicatedServerInfo == nil then
        farm = eigeneFarm()
    end

    local liste = {}
    for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles or {}) do
        if AOMaschinenMain.istErfasst(vehicle) and (farm == nil or vehicle.ownerFarmId == farm) then
            local e = AOMaschinen.auswerten(vehicle, wahl)
            if e ~= nil then
                table.insert(liste, e)
            end
        end
    end
    table.sort(liste, function(a, b)
        return (a.proStunde or -1) > (b.proStunde or -1)
    end)

    local zeilen = { string.format("=== Fuhrpark, %s: %d Fahrzeuge und Geraete", ZEITRAEUME[wahl], #liste) }
    local summe, stunden = 0, 0
    for _, e in ipairs(liste) do
        summe = summe + e.summe
        stunden = stunden + e.stunden
        table.insert(zeilen, string.format("  %-32s %s %7.1f h  %10s  %8s/h  %8s/ha  %s",
            string.sub(e.name, 1, 32),
            e.geleast and "L" or " ",
            e.stunden, geld(e.summe),
            e.proStunde ~= nil and geld(e.proStunde) or "-",
            e.proHa ~= nil and geld(e.proHa) or "-",
            farm == nil and string.format("Farm %d", e.vehicle.ownerFarmId) or ""))
    end
    table.insert(zeilen, string.format("  Summe %s bei %.1f Betriebsstunden", geld(summe), stunden))
    return table.concat(zeilen, "\n")
end

function AOMaschinenMain:loadMap(name)
    if addConsoleCommand ~= nil then
        addConsoleCommand("aoMaschinen", "Kosten und Kennzahlen des Fahrzeugs, in dem man sitzt",
            "befehlFahrzeug", AOMaschinenMain, "[jahr|vorjahr|gesamt]")
        addConsoleCommand("aoMaschinenListe", "Kosten aller Fahrzeuge und Geraete des Hofs",
            "befehlListe", AOMaschinenMain, "[jahr|vorjahr|gesamt]")
    end

    AOMaschinenMain.bereit = AgrarOekonomie ~= nil and AgrarOekonomie.istServer()
    Logging.info(AOMaschinenMain.LOG .. "Maschinenkosten bereit (Server=%s, aktiv=%s).",
        tostring(AOMaschinenMain.bereit), tostring(AOMaschinen.erfassenAktiv()))
end

function AOMaschinenMain:update(dt)
    if not AOMaschinenMain.bereit then
        return
    end
    AOMaschinenMain.takt = AOMaschinenMain.takt + dt
    if AOMaschinenMain.takt < AOMaschinenMain.TAKT_MS then
        return
    end
    AOMaschinenMain.takt = 0
    AOMaschinenMain.pruefen()
end

function AOMaschinenMain:deleteMap()
    AOMaschinenMain.bereit     = false
    AOMaschinenMain.takt       = 0
    AOMaschinenMain.letzterTag = nil
    AOMaschinenMain.paket      = nil
    AOMaschinenMain.wartetAuf  = nil
    AOMaschinen.imVerbrauch    = nil
end

addModEventListener(AOMaschinenMain)
