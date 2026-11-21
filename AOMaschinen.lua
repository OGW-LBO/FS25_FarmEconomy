-- AOMaschinen.lua
-- Zaehlt je Fahrzeug und Geraet Stunden, Kraftstoff, Flaeche und Kosten,
-- getrennt nach Spieljahr und seit Beginn der Erfassung. Gezaehlt wird nur
-- auf dem Server, die Zahlen liegen im Spielstand des Fahrzeugs.
-- OGW

AOMaschinen = {}

AOMaschinen.MOD_NAME  = g_currentModName
AOMaschinen.SPEC_NAME = "aoMaschinen"
AOMaschinen.LOG       = "[AgrarOekonomie] "

AOMaschinen.MS_JE_STUNDE = 60 * 60 * 1000

AOMaschinen.FELDER = { "ha", "haGezogen", "reparatur", "fuhrpark", "unterhalt", "leasing", "tage" }

AOMaschinen.imVerbrauch = nil

local function istKraftstoff(fillType)
    if FillType == nil or fillType == nil then
        return false
    end
    return fillType == FillType.DIESEL or fillType == FillType.DEF
        or fillType == FillType.ELECTRICCHARGE or fillType == FillType.METHANE
end

local function kraftstoffName(fillType)
    if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeNameByIndex ~= nil then
        local name = g_fillTypeManager:getFillTypeNameByIndex(fillType)
        if type(name) == "string" then
            return name
        end
    end
    return tostring(fillType)
end

local function literPreis(fillType)
    if g_currentMission ~= nil and g_currentMission.economyManager ~= nil
            and g_currentMission.economyManager.getCostPerLiter ~= nil then
        local preis = g_currentMission.economyManager:getCostPerLiter(fillType)
        if type(preis) == "number" and preis > 0 then
            return preis
        end
    end
    return 0
end

function AOMaschinen.prerequisitesPresent(specializations)
    return true
end

function AOMaschinen.initSpecialization()
    if Vehicle == nil or Vehicle.xmlSchemaSavegame == nil then
        return
    end

    local schema = Vehicle.xmlSchemaSavegame
    local basis = string.format("vehicles.vehicle(?).%s.%s",
        tostring(AOMaschinen.MOD_NAME), AOMaschinen.SPEC_NAME)
    local konto = basis .. ".konto(?)"

    schema:register(XMLValueType.INT,   konto .. "#jahr", "Spieljahr, 0 = seit Beginn der Erfassung", 0)
    schema:register(XMLValueType.BOOL,  konto .. "#altbestand", "Erfassung begann bei einem gebrauchten Fahrzeug", false)
    schema:register(XMLValueType.FLOAT, konto .. "#msStart", "Betriebszeit zu Beginn in ms", 0)
    schema:register(XMLValueType.FLOAT, konto .. "#msEnde", "Betriebszeit am Ende in ms, -1 = laeuft", -1)
    schema:register(XMLValueType.FLOAT, konto .. "#wertStart", "Zeitwert zu Beginn", 0)
    schema:register(XMLValueType.FLOAT, konto .. "#wertEnde", "Zeitwert am Ende, -1 = laeuft", -1)
    for _, feld in ipairs(AOMaschinen.FELDER) do
        schema:register(XMLValueType.FLOAT, konto .. "#" .. feld, feld, 0)
    end
    schema:register(XMLValueType.STRING, konto .. ".kraftstoff(?)#typ", "Kraftstoff", nil)
    schema:register(XMLValueType.FLOAT,  konto .. ".kraftstoff(?)#liter", "Liter", 0)
    schema:register(XMLValueType.FLOAT,  konto .. ".kraftstoff(?)#kosten", "Kosten", 0)
end

function AOMaschinen.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", AOMaschinen)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", AOMaschinen)
    SpecializationUtil.registerEventListener(vehicleType, "onFillUnitFillLevelChanged", AOMaschinen)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", AOMaschinen)
end

-- Die globale Taste erreicht den Fahrzeug-Kontext nicht, deshalb hier noch
-- einmal fuer das Fahrzeug, in dem man sitzt.
function AOMaschinen:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient or InputAction == nil or InputAction.AO_BUCH == nil then
        return
    end
    if self.aoMkAktionen == nil then
        self.aoMkAktionen = {}
    end
    if self.clearActionEventsTable == nil or self.addActionEvent == nil then
        return
    end
    self:clearActionEventsTable(self.aoMkAktionen)
    if self.getIsEntered == nil or not self:getIsEntered() or not isActiveForInputIgnoreSelection then
        return
    end
    local _, id = self:addActionEvent(self.aoMkAktionen, InputAction.AO_BUCH, self,
        AOMaschinen.aktionHofPC, false, true, false, true, nil)
    if id ~= nil and g_inputBinding ~= nil and g_inputBinding.setActionEventTextPriority ~= nil
            and GS_PRIO_VERY_LOW ~= nil then
        g_inputBinding:setActionEventTextPriority(id, GS_PRIO_VERY_LOW)
    end
end

function AOMaschinen.aktionHofPC(self, actionName, inputValue, callbackState, isAnalog)
    if AOHofPC ~= nil and AOHofPC.umschalten ~= nil then
        AOHofPC.umschalten()
    end
end

function AOMaschinen.neuesKonto(jahr, ms, wert)
    local konto = {
        jahr       = jahr,
        altbestand = false,
        msStart    = ms or 0,
        msEnde     = -1,
        wertStart  = wert or 0,
        wertEnde   = -1,
        kraftstoff = {},
    }
    for _, feld in ipairs(AOMaschinen.FELDER) do
        konto[feld] = 0
    end
    return konto
end

function AOMaschinen:onLoad(savegame)
    self.aoMk = nil
    self.aoMkFaehig = true

    if savegame == nil or savegame.xmlFile == nil or savegame.key == nil
            or savegame.xmlFile.getValue == nil or savegame.xmlFile.hasProperty == nil then
        return
    end

    local xml = savegame.xmlFile
    local basis = string.format("%s.%s.%s", savegame.key,
        tostring(AOMaschinen.MOD_NAME), AOMaschinen.SPEC_NAME)

    local daten = { gesamt = nil, jahre = {} }
    local i = 0
    while true do
        local key = string.format("%s.konto(%d)", basis, i)
        if not xml:hasProperty(key) then
            break
        end
        local jahr = xml:getValue(key .. "#jahr", 0) or 0
        local konto = AOMaschinen.neuesKonto(jahr,
            xml:getValue(key .. "#msStart", 0), xml:getValue(key .. "#wertStart", 0))
        konto.altbestand = xml:getValue(key .. "#altbestand", false) == true
        konto.msEnde     = xml:getValue(key .. "#msEnde", -1)
        konto.wertEnde   = xml:getValue(key .. "#wertEnde", -1)
        for _, feld in ipairs(AOMaschinen.FELDER) do
            konto[feld] = xml:getValue(key .. "#" .. feld, 0) or 0
        end
        local k = 0
        while true do
            local kKey = string.format("%s.kraftstoff(%d)", key, k)
            if not xml:hasProperty(kKey) then
                break
            end
            local typ = xml:getValue(kKey .. "#typ", "?") or "?"
            konto.kraftstoff[typ] = {
                liter  = xml:getValue(kKey .. "#liter", 0) or 0,
                kosten = xml:getValue(kKey .. "#kosten", 0) or 0,
            }
            k = k + 1
        end

        if jahr == 0 then
            daten.gesamt = konto
        else
            daten.jahre[jahr] = konto
        end
        i = i + 1
    end

    if daten.gesamt ~= nil then
        self.aoMk = daten
    end
end

local function schreibeKonto(xmlFile, key, konto)
    xmlFile:setValue(key .. "#jahr", konto.jahr)
    if konto.altbestand then
        xmlFile:setValue(key .. "#altbestand", true)
    end
    xmlFile:setValue(key .. "#msStart", konto.msStart)
    xmlFile:setValue(key .. "#msEnde", konto.msEnde)
    xmlFile:setValue(key .. "#wertStart", konto.wertStart)
    xmlFile:setValue(key .. "#wertEnde", konto.wertEnde)
    for _, feld in ipairs(AOMaschinen.FELDER) do
        xmlFile:setValue(key .. "#" .. feld, konto[feld] or 0)
    end
    local k = 0
    for typ, werte in pairs(konto.kraftstoff) do
        local kKey = string.format("%s.kraftstoff(%d)", key, k)
        xmlFile:setValue(kKey .. "#typ", typ)
        xmlFile:setValue(kKey .. "#liter", werte.liter or 0)
        xmlFile:setValue(kKey .. "#kosten", werte.kosten or 0)
        k = k + 1
    end
end

function AOMaschinen:saveToXMLFile(xmlFile, key, usedModNames)
    local daten = self.aoMk
    if daten == nil or daten.gesamt == nil then
        return
    end

    schreibeKonto(xmlFile, key .. ".konto(0)", daten.gesamt)

    local jahre = {}
    for jahr, _ in pairs(daten.jahre) do
        table.insert(jahre, jahr)
    end
    table.sort(jahre)
    for i, jahr in ipairs(jahre) do
        schreibeKonto(xmlFile, string.format("%s.konto(%d)", key, i), daten.jahre[jahr])
    end
end

function AOMaschinen.getMs(vehicle)
    if type(vehicle.operatingTime) == "number" then
        return vehicle.operatingTime
    end
    return 0
end

function AOMaschinen.istGeleast(vehicle)
    return VehiclePropertyState ~= nil and VehiclePropertyState.LEASED ~= nil
        and vehicle.propertyState == VehiclePropertyState.LEASED
end

function AOMaschinen.getPreis(vehicle)
    if vehicle.getPrice ~= nil then
        local preis = vehicle:getPrice()
        if type(preis) == "number" then
            return preis
        end
    end
    return 0
end

-- Zeitwert ohne Abzug fuer Schaden, wie in der Reparatur-Oekonomie
function AOMaschinen.getZeitwert(vehicle)
    if AOMaschinen.istGeleast(vehicle) then
        return 0
    end
    local preis = AOMaschinen.getPreis(vehicle)
    if ReparaturOekonomie ~= nil and ReparaturOekonomie.getRestwert ~= nil then
        local wert = ReparaturOekonomie.getRestwert(vehicle, preis)
        if wert ~= nil then
            return wert
        end
    end
    return preis
end

-- Ein frisch gekauftes Fahrzeug startet beim Kaufpreis, damit der Abschlag
-- beim Kauf als Wertverlust zaehlt.
local function startWert(vehicle)
    if AOMaschinen.istGeleast(vehicle) then
        return 0
    end
    if AOMaschinen.getMs(vehicle) < 60000 and (vehicle.age or 0) == 0 then
        return AOMaschinen.getPreis(vehicle)
    end
    return AOMaschinen.getZeitwert(vehicle)
end

function AOMaschinen.getDaten(vehicle)
    if vehicle == nil or vehicle.aoMkFaehig ~= true then
        return nil
    end
    if vehicle.aoMk == nil then
        local ms = AOMaschinen.getMs(vehicle)
        local gesamt = AOMaschinen.neuesKonto(0, ms, startWert(vehicle))
        gesamt.altbestand = ms >= 60000
        vehicle.aoMk = { gesamt = gesamt, jahre = {} }
    end
    return vehicle.aoMk
end

-- Konto des laufenden Spieljahres. Beim Jahreswechsel wird das alte Konto
-- abgeschlossen, aelter als das Vorjahr fliegt raus.
function AOMaschinen.getJahresKonto(vehicle, jahr)
    local daten = AOMaschinen.getDaten(vehicle)
    if daten == nil then
        return nil
    end
    local konto = daten.jahre[jahr]
    if konto ~= nil then
        return konto
    end

    local ms = AOMaschinen.getMs(vehicle)
    local wert = AOMaschinen.getZeitwert(vehicle)
    local weg = {}
    for j, alt in pairs(daten.jahre) do
        if alt.msEnde < 0 then
            alt.msEnde = ms
            alt.wertEnde = wert
        end
        if j < jahr - 1 or j > jahr then
            table.insert(weg, j)
        end
    end
    for _, j in ipairs(weg) do
        daten.jahre[j] = nil
    end

    local anfang = wert
    if next(daten.jahre) == nil and daten.gesamt.msStart == ms then
        anfang = daten.gesamt.wertStart
    end
    konto = AOMaschinen.neuesKonto(jahr, ms, anfang)
    daten.jahre[jahr] = konto
    return konto
end

function AOMaschinen.aktuellesJahr()
    if AOKassenbuch ~= nil and AOKassenbuch.zeitstempel ~= nil then
        local jahr = AOKassenbuch.zeitstempel()
        if type(jahr) == "number" and jahr > 0 then
            return jahr
        end
    end
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and type(env.currentYear) == "number" and env.currentYear > 0 then
        return math.floor(env.currentYear)
    end
    return 1
end

function AOMaschinen.erfassenAktiv()
    return AgrarOekonomie ~= nil and AgrarOekonomie.CFG ~= nil
        and AgrarOekonomie.CFG.mkAktiv == true
end

-- feld ist einer der Namen aus FELDER
local function zaehlt(vehicle)
    if not AOMaschinen.erfassenAktiv() then
        return false
    end
    if AOMaschinenMain ~= nil and AOMaschinenMain.istErfasst ~= nil then
        return AOMaschinenMain.istErfasst(vehicle)
    end
    return vehicle ~= nil and not vehicle.isDeleted and vehicle.aoMkFaehig == true
end

function AOMaschinen.buchen(vehicle, feld, betrag)
    if betrag == nil or betrag == 0 or not zaehlt(vehicle) then
        return
    end
    local daten = AOMaschinen.getDaten(vehicle)
    local konto = AOMaschinen.getJahresKonto(vehicle, AOMaschinen.aktuellesJahr())
    if daten == nil or konto == nil then
        return
    end
    daten.gesamt[feld] = (daten.gesamt[feld] or 0) + betrag
    konto[feld] = (konto[feld] or 0) + betrag
end

function AOMaschinen.bucheKraftstoff(vehicle, fillType, liter, kosten)
    if liter == nil or liter <= 0 or not zaehlt(vehicle) then
        return
    end
    local daten = AOMaschinen.getDaten(vehicle)
    local konto = AOMaschinen.getJahresKonto(vehicle, AOMaschinen.aktuellesJahr())
    if daten == nil or konto == nil then
        return
    end
    local name = kraftstoffName(fillType)
    for _, k in ipairs({ daten.gesamt, konto }) do
        local eintrag = k.kraftstoff[name]
        if eintrag == nil then
            eintrag = { liter = 0, kosten = 0 }
            k.kraftstoff[name] = eintrag
        end
        eintrag.liter  = eintrag.liter + liter
        eintrag.kosten = eintrag.kosten + kosten
    end
end

function AOMaschinen:onFillUnitFillLevelChanged(fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData, appliedDelta)
    if not self.isServer or appliedDelta == nil or appliedDelta >= 0 then
        return
    end
    local spec = self.spec_motorized
    if spec == nil or spec.consumers == nil or not istKraftstoff(fillTypeIndex) then
        return
    end
    for _, consumer in pairs(spec.consumers) do
        if consumer.fillUnitIndex == fillUnitIndex and consumer.fillType == fillTypeIndex then
            local liter = -appliedDelta
            AOMaschinen.bucheKraftstoff(self, fillTypeIndex, liter, liter * literPreis(fillTypeIndex))
            return
        end
    end
end

-- Kauft der Helfer den Diesel, bleibt der Tank voll und das Spiel bucht nur
-- Geld. Der Betrag kommt aus dem Geld-Hook, das Fahrzeug aus updateConsumers.
function AOMaschinen.buche(farmId, moneyType, betrag)
    local vehicle = AOMaschinen.imVerbrauch
    if vehicle == nil or betrag == nil or betrag >= 0 then
        return
    end
    if MoneyType == nil or moneyType ~= MoneyType.PURCHASE_FUEL or FillType == nil then
        return
    end
    local kosten = -betrag
    local preis = literPreis(FillType.DIESEL) * 1.5
    local liter = preis > 0 and kosten / preis or 0
    AOMaschinen.bucheKraftstoff(vehicle, FillType.DIESEL, liter, kosten)
end

-- Bereiche eines Typs liegen nebeneinander und werden addiert. Verschiedene
-- Typen bearbeiten dieselbe Spur, etwa Grubber und Saat, davon zaehlt nur der
-- groesste.
function AOMaschinen:onUpdateTick(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not self.isServer then
        return
    end
    local spec = self.spec_workArea
    if spec == nil or spec.workAreas == nil then
        return
    end

    local jeTyp = nil
    for _, workArea in pairs(spec.workAreas) do
        local zeit = workArea.lastProcessingTime
        if type(zeit) == "number" and zeit > (workArea.aoMkZeit or 0) then
            workArea.aoMkZeit = zeit
            local ha = workArea.lastWorkedHectares
            if type(ha) == "number" and ha > 0 then
                jeTyp = jeTyp or {}
                local typ = workArea.type or 0
                jeTyp[typ] = (jeTyp[typ] or 0) + ha
            end
        end
    end
    if jeTyp == nil then
        return
    end

    local ha = 0
    for _, wert in pairs(jeTyp) do
        if wert > ha then
            ha = wert
        end
    end

    AOMaschinen.buchen(self, "ha", ha)
    if self.getRootVehicle ~= nil then
        local zug = self:getRootVehicle()
        if zug ~= nil and zug ~= self then
            AOMaschinen.buchen(zug, "haGezogen", ha)
        end
    end
end

-- Diese Werte gehen im Mehrspieler zum Client, in genau dieser Reihenfolge
AOMaschinen.NETZ = { "stunden", "tage", "wertverlust", "reparatur", "sprit", "liter",
    "unterhalt", "leasing", "fuhrpark", "ha", "haGezogen", "zeitwert", "zustand",
    "leasTag", "leasStunde", "stundenErfasst" }

function AOMaschinen.getName(vehicle)
    if vehicle ~= nil and vehicle.getFullName ~= nil then
        local voll = vehicle:getFullName()
        if type(voll) == "string" and voll ~= "" then
            return voll
        end
    end
    return "?"
end

function AOMaschinen.getStoreItem(vehicle)
    if g_storeManager == nil or g_storeManager.getItemByXMLFilename == nil
            or vehicle.configFileName == nil then
        return nil
    end
    return g_storeManager:getItemByXMLFilename(vehicle.configFileName)
end

-- Leasing je Tag und je Betriebsstunde, -1 = unbekannt. Die Rechnung des
-- Spiels steckt im EconomyManager, der im Quellcode fehlt.
function AOMaschinen.leasingSaetze(vehicle)
    local preis = AOMaschinen.getPreis(vehicle)
    local proTag, proStunde = -1, -1
    if EconomyManager ~= nil and type(EconomyManager.PER_DAY_LEASING_FACTOR) == "number" then
        proTag = preis * EconomyManager.PER_DAY_LEASING_FACTOR
    end
    local item = AOMaschinen.getStoreItem(vehicle)
    if item ~= nil and type(item.runningLeasingFactor) == "number" then
        proStunde = preis * item.runningLeasingFactor
    end
    return proTag, proStunde
end

-- Rohzahlen eines Fahrzeugs fuer den Zeitraum. wahl: "jahr", "vorjahr"
-- oder "gesamt". nil, wenn es fuer den Zeitraum nichts gibt.
function AOMaschinen.eintrag(vehicle, wahl)
    local daten = AOMaschinen.getDaten(vehicle)
    if daten == nil then
        return nil
    end

    local konto
    if wahl == "gesamt" then
        konto = daten.gesamt
    else
        local jahr = AOMaschinen.aktuellesJahr()
        if wahl == "vorjahr" then
            jahr = jahr - 1
        end
        konto = daten.jahre[jahr]
    end
    if konto == nil then
        return nil
    end

    local msEnde = konto.msEnde >= 0 and konto.msEnde or AOMaschinen.getMs(vehicle)
    local zeitwert = AOMaschinen.getZeitwert(vehicle)
    local wertEnde = konto.wertEnde >= 0 and konto.wertEnde or zeitwert

    local zustand = 1
    if vehicle.getDamageAmount ~= nil then
        local schaden = vehicle:getDamageAmount()
        if type(schaden) == "number" then
            zustand = math.max(0, math.min(1, 1 - schaden))
        end
    end

    local leasTag, leasStunde = AOMaschinen.leasingSaetze(vehicle)

    local r = {
        vehicle    = vehicle,
        name       = AOMaschinen.getName(vehicle),
        geleast    = AOMaschinen.istGeleast(vehicle),
        motor      = vehicle.spec_motorized ~= nil,
        altbestand = daten.gesamt.altbestand == true,
        stunden    = math.max(0, msEnde - konto.msStart) / AOMaschinen.MS_JE_STUNDE,
        tage       = konto.tage or 0,
        wertverlust = math.max(0, konto.wertStart - wertEnde),
        reparatur  = konto.reparatur or 0,
        sprit      = 0,
        liter      = 0,
        unterhalt  = konto.unterhalt or 0,
        leasing    = konto.leasing or 0,
        fuhrpark   = konto.fuhrpark or 0,
        ha         = konto.ha or 0,
        haGezogen  = konto.haGezogen or 0,
        zeitwert   = zeitwert,
        zustand    = zustand,
        leasTag    = leasTag,
        leasStunde = leasStunde,
        kraftstoff = {},
    }
    for typ, werte in pairs(konto.kraftstoff) do
        r.sprit = r.sprit + (werte.kosten or 0)
        r.liter = r.liter + (werte.liter or 0)
        table.insert(r.kraftstoff, { typ = typ, liter = werte.liter or 0, kosten = werte.kosten or 0 })
    end
    table.sort(r.kraftstoff, function(a, b) return a.typ < b.typ end)

    r.stundenErfasst = r.stunden
    if wahl == "gesamt" and r.altbestand then
        r.stunden = AOMaschinen.getMs(vehicle) / AOMaschinen.MS_JE_STUNDE
        if not r.geleast then
            r.wertverlust = math.max(r.wertverlust, AOMaschinen.getPreis(vehicle) - zeitwert)
        end
        if type(vehicle.age) == "number" then
            r.tage = math.max(r.tage, math.floor(vehicle.age * AOMaschinen.tageJeMonat() + 0.5))
        end
    else
        r.altbestand = false
    end
    return r
end

function AOMaschinen.tageJeMonat()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and type(env.daysPerPeriod) == "number" and env.daysPerPeriod > 0 then
        return env.daysPerPeriod
    end
    return 1
end

-- Kennzahlen aus den Rohzahlen, laeuft auch auf dem Client
function AOMaschinen.ableiten(r)
    r.summe = r.wertverlust + r.reparatur + r.sprit + r.unterhalt + r.leasing + r.fuhrpark

    local stundenLiter = r.stunden
    if r.altbestand then
        stundenLiter = r.stundenErfasst or 0
    end
    r.proStunde      = r.stunden > 0.05 and r.summe / r.stunden or nil
    r.literProStunde = stundenLiter > 0.05 and r.liter > 0 and r.liter / stundenLiter or nil

    local flaeche = r.ha > 0 and r.ha or r.haGezogen
    r.flaeche    = flaeche
    r.proHa      = not r.altbestand and flaeche > 0.01 and r.summe / flaeche or nil
    r.literProHa = flaeche > 0.01 and r.liter > 0 and r.liter / flaeche or nil

    local monate = r.tage / AOMaschinen.tageJeMonat()
    r.auslastung = monate >= 0.5 and r.stunden / monate or nil

    -- Was dieselbe Nutzung geleast gekostet haette. Kraftstoff faellt so oder
    -- so an und bleibt draussen, die Anzahlung ebenfalls.
    r.besitz = r.wertverlust + r.reparatur + r.unterhalt + r.fuhrpark
    r.leasingGleich = nil
    r.leasingBesser = false
    r.breakEven = nil
    if not r.geleast and not r.altbestand and (r.leasTag >= 0 or r.leasStunde >= 0) then
        local proTag = math.max(0, r.leasTag)
        local proStunde = math.max(0, r.leasStunde)
        r.leasingGleich = proTag * r.tage + proStunde * r.stunden
        r.leasingBesser = monate >= 1 and r.leasingGleich < r.besitz * 0.8
        if proStunde > 0 then
            local stunden = (r.besitz - proTag * r.tage) / proStunde
            if stunden > 0 then
                r.breakEven = stunden
            end
        end
    end
    return r
end

function AOMaschinen.auswerten(vehicle, wahl)
    local r = AOMaschinen.eintrag(vehicle, wahl)
    if r == nil then
        return nil
    end
    return AOMaschinen.ableiten(r)
end
