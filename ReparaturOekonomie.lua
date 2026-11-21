-- ReparaturOekonomie.lua
-- Spezialisierung: Reparatur wird mit Betriebsstunden und Anzahl Reparaturen
-- teurer, Verschleisstempo einstellbar, Hinweis wenn sich ein Fahrzeug nicht
-- mehr lohnt. Zaehler liegen im Spielstand.
-- OGW

ReparaturOekonomie = {}

ReparaturOekonomie.MOD_NAME = g_currentModName
ReparaturOekonomie.SPEC_NAME = "reparaturOekonomie"
ReparaturOekonomie.LOG = "[ReparaturOekonomie] "

-- Einstellungen, im Spiel auch per "roConfig <name> <wert>"
ReparaturOekonomie.CFG = {

    -- Reparatur
    grundfaktorReparatur = 1.1,
    faktorStunden        = 0.6,   -- volle +60 % bei referenzStunden
    referenzStunden      = 100,
    faktorProReparatur   = 0.02,  -- je bezahlter Reparatur
    faktorAlter          = 0.0,   -- aus, Kalender laeuft auch ohne Nutzung
    faktorMax            = 1.8,

    -- Lack, ohne Progression
    grundfaktorLackieren = 1.0,

    -- Verschleiss, 1.0 = Spiel
    tempoSchaden         = 1.0,
    tempoLack            = 1.0,

    -- Warnung nach Summe aller Reparaturen im Verhaeltnis zum Wert. Der
    -- Einzelpreis taugt nicht, oft reparieren ist im Spiel billig.
    warnAnteil           = 0.25,
    kritischAnteil       = 0.45,

    -- true = Restwert als Bezug, false = Neupreis
    bewertungNachRestwert = true,

    -- unter diesem Anteil vom Neupreis keine Warnung, sonst meckern billige
    -- Hoftrecker staendig. 0 = aus
    neukaufMindestNeupreis = 0.25,

    -- Warnung nach Betriebsstunden, unabhaengig von den Kosten. 0 = aus
    warnStunden          = 80,
    kritischStunden      = 120,

    -- Klassen kommen oben drauf, false = alle gleich
    klassenAktiv         = true,

    klasseTempoErnte     = 1.25,
    klasseTempoMotor     = 1.0,
    klasseTempoAnbau     = 0.75,

    -- skaliert die Warnschwellen, >1 = spaeter
    klasseNeukaufErnte   = 0.85,
    klasseNeukaufMotor   = 1.0,
    klasseNeukaufAnbau   = 2.0,

    -- nur fuer die Anzeige der Stunden in der Info-Box, 1.0 = aus
    anzeigeStundenFaktor = 1.0,

    debugAnzeige         = false,

    meldungIntervall     = 5000   -- ms
}

-- Hilfen ----------------------------------------------------------------------

function ReparaturOekonomie.formatGeld(betrag)
    betrag = betrag or 0
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local text = g_i18n:formatMoney(betrag, 0, true, true)
        if text ~= nil then
            return text
        end
    end
    return string.format("%d", betrag)
end

function ReparaturOekonomie.text(name, standard)
    if g_i18n ~= nil and g_i18n.hasText ~= nil then
        if name ~= nil and g_i18n:hasText(name) then
            return g_i18n:getText(name)
        end
    end
    return standard
end

-- ohne Mission nur ins Log
function ReparaturOekonomie.zeigeMeldung(text)
    if text == nil then
        return
    end

    if g_currentMission == nil or g_currentMission.addIngameNotification == nil then
        Logging.info(ReparaturOekonomie.LOG .. tostring(text))
        return
    end

    local prio = 2
    if FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_CRITICAL ~= nil then
        prio = FSBaseMission.INGAME_NOTIFICATION_CRITICAL
    end

    g_currentMission:addIngameNotification(prio, tostring(text))
end

-- Registrierung ---------------------------------------------------------------

function ReparaturOekonomie.prerequisitesPresent(specializations)
    -- Main haengt uns nur an Typen mit wearable
    return true
end

function ReparaturOekonomie.initSpecialization()
    if Vehicle == nil or Vehicle.xmlSchemaSavegame == nil then
        return
    end

    local schema = Vehicle.xmlSchemaSavegame
    local basis = string.format("vehicles.vehicle(?).%s.%s",
        tostring(ReparaturOekonomie.MOD_NAME), ReparaturOekonomie.SPEC_NAME)

    schema:register(XMLValueType.FLOAT, basis .. "#anzahlReparaturen", "Anzahl bezahlter Reparaturen", 0)
    schema:register(XMLValueType.FLOAT, basis .. "#kostenGesamt", "Summe der bezahlten Reparaturkosten", 0)
end

function ReparaturOekonomie.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ReparaturOekonomie)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", ReparaturOekonomie)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", ReparaturOekonomie)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", ReparaturOekonomie)
end

function ReparaturOekonomie.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "roGetDaten", ReparaturOekonomie.roGetDaten)
    SpecializationUtil.registerFunction(vehicleType, "roGetFaktor", ReparaturOekonomie.roGetFaktor)
    SpecializationUtil.registerFunction(vehicleType, "roGetBewertung", ReparaturOekonomie.roGetBewertung)
end

function ReparaturOekonomie.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getRepairPrice", ReparaturOekonomie.getRepairPrice)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getRepaintPrice", ReparaturOekonomie.getRepaintPrice)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "repairVehicle", ReparaturOekonomie.repairVehicle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateDamageAmount", ReparaturOekonomie.updateDamageAmount)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getWearMultiplier", ReparaturOekonomie.getWearMultiplier)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", ReparaturOekonomie.showInfo)
end

-- Daten je Fahrzeug -----------------------------------------------------------

function ReparaturOekonomie:roGetDaten()
    if self.roDaten == nil then
        self.roDaten = {
            anzahlReparaturen = 0,
            kostenGesamt      = 0,
            warnStufe         = 0,
            pruefTimer        = 0
        }
    end
    return self.roDaten
end

function ReparaturOekonomie:onLoad(savegame)
    local daten = self:roGetDaten()

    if savegame == nil or savegame.xmlFile == nil or savegame.key == nil then
        return
    end

    -- Spielstand legt die Spec unter Modname.Specname ab
    local schluessel = string.format("%s.%s.%s", savegame.key,
        tostring(ReparaturOekonomie.MOD_NAME), ReparaturOekonomie.SPEC_NAME)

    if savegame.xmlFile.getValue == nil then
        daten.anzahlReparaturen = 0
        daten.kostenGesamt = 0
        return
    end

    local anzahl = savegame.xmlFile:getValue(schluessel .. "#anzahlReparaturen", 0)
    local kosten = savegame.xmlFile:getValue(schluessel .. "#kostenGesamt", 0)
    daten.anzahlReparaturen = type(anzahl) == "number" and anzahl or 0
    daten.kostenGesamt      = type(kosten) == "number" and kosten or 0
end

function ReparaturOekonomie:saveToXMLFile(xmlFile, key, usedModNames)
    local daten = self:roGetDaten()

    xmlFile:setValue(key .. "#anzahlReparaturen", daten.anzahlReparaturen)
    xmlFile:setValue(key .. "#kostenGesamt", daten.kostenGesamt)
end

function ReparaturOekonomie:onWriteStream(streamId, connection)
    local daten = self:roGetDaten()
    streamWriteUIntN(streamId, math.min(math.floor(daten.anzahlReparaturen), 65535), 16)
    streamWriteFloat32(streamId, daten.kostenGesamt)
end

function ReparaturOekonomie:onReadStream(streamId, connection)
    local daten = self:roGetDaten()
    daten.anzahlReparaturen = streamReadUIntN(streamId, 16)
    daten.kostenGesamt = streamReadFloat32(streamId)
end

-- Rechnung --------------------------------------------------------------------

-- echte Stunden, ohne Anzeigefaktor
function ReparaturOekonomie.getStunden(vehicle)
    if vehicle.operatingTime == nil then
        return 0
    end
    return vehicle.operatingTime / (1000 * 60 * 60)
end

-- Zeitwert ohne Abzug fuer Schaden/Lack, sonst springt der Bezug mit jedem
-- Kratzer. nil wenn nicht ermittelbar.
function ReparaturOekonomie.getRestwert(vehicle, neupreis)
    if Vehicle == nil or Vehicle.calculateSellPrice == nil or g_storeManager == nil then
        return nil
    end
    if vehicle.configFileName == nil then
        return nil
    end

    if g_storeManager.getItemByXMLFilename == nil then
        return nil
    end
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        return nil
    end
    local wert = Vehicle.calculateSellPrice(storeItem, vehicle.age or 0,
        vehicle.operatingTime or 0, neupreis or 0, 0, 0)

    if type(wert) == "number" and wert > 0 then
        return wert
    end
    return nil
end

-- Restwert oder Neupreis, im Zweifel Neupreis
function ReparaturOekonomie.getBewertungswert(vehicle)
    local cfg = ReparaturOekonomie.CFG

    local neupreis = 0
    if vehicle.getPrice ~= nil then
        neupreis = vehicle:getPrice() or 0
    end

    if cfg.bewertungNachRestwert == true then
        local restwert = ReparaturOekonomie.getRestwert(vehicle, neupreis)
        if restwert ~= nil and restwert > 0 then
            return restwert
        end
    end

    return neupreis
end

-- Reihenfolge zaehlt, ein Drescher ist auch motorisiert
function ReparaturOekonomie.getKlasse(vehicle)
    if vehicle.spec_combine ~= nil then
        return "ernte"
    elseif vehicle.spec_motorized ~= nil then
        return "motor"
    elseif vehicle.spec_attachable ~= nil then
        return "anbau"
    end
    return "sonstige"
end

function ReparaturOekonomie.getKlasseTempo(vehicle)
    local cfg = ReparaturOekonomie.CFG
    if cfg.klassenAktiv ~= true then
        return 1.0
    end
    local k = ReparaturOekonomie.getKlasse(vehicle)
    if k == "ernte" then
        return cfg.klasseTempoErnte or 1.0
    elseif k == "anbau" then
        return cfg.klasseTempoAnbau or 1.0
    end
    return cfg.klasseTempoMotor or 1.0
end

function ReparaturOekonomie.getKlasseNeukauf(vehicle)
    local cfg = ReparaturOekonomie.CFG
    if cfg.klassenAktiv ~= true then
        return 1.0
    end
    local k = ReparaturOekonomie.getKlasse(vehicle)
    if k == "ernte" then
        return cfg.klasseNeukaufErnte or 1.0
    elseif k == "anbau" then
        return cfg.klasseNeukaufAnbau or 1.0
    end
    return cfg.klasseNeukaufMotor or 1.0
end

function ReparaturOekonomie:roGetFaktor()
    local cfg = ReparaturOekonomie.CFG
    local daten = self:roGetDaten()

    local faktor = 1.0

    if cfg.referenzStunden > 0 then
        local stunden = ReparaturOekonomie.getStunden(self)
        faktor = faktor + cfg.faktorStunden * math.min(stunden / cfg.referenzStunden, 1.0)
    end

    faktor = faktor + cfg.faktorProReparatur * daten.anzahlReparaturen

    if cfg.faktorAlter > 0 and self.age ~= nil and self.lifetime ~= nil and self.lifetime > 0 then
        faktor = faktor + cfg.faktorAlter * math.min(self.age / self.lifetime, 1.0)
    end

    if faktor > cfg.faktorMax then
        faktor = cfg.faktorMax
    end

    return faktor
end

-- Gibt anteil, stufe (0 ok, 1 teuer, 2 unwirtschaftlich) und wert zurueck.
-- Hoehere Stufe aus Kosten und Betriebsstunden gewinnt.
function ReparaturOekonomie:roGetBewertung()
    local cfg = ReparaturOekonomie.CFG
    local daten = self:roGetDaten()

    local wert = ReparaturOekonomie.getBewertungswert(self)
    if wert <= 0 then
        return 0, 0, 0
    end

    local nf = ReparaturOekonomie.getKlasseNeukauf(self)

    local anteil = daten.kostenGesamt / wert
    local stufe = 0
    if anteil >= cfg.kritischAnteil * nf then
        stufe = 2
    elseif anteil >= cfg.warnAnteil * nf then
        stufe = 1
    end

    local stunden = ReparaturOekonomie.getStunden(self)
    if cfg.kritischStunden ~= nil and cfg.kritischStunden > 0 and stunden >= cfg.kritischStunden * nf then
        stufe = math.max(stufe, 2)
    elseif cfg.warnStunden ~= nil and cfg.warnStunden > 0 and stunden >= cfg.warnStunden * nf then
        stufe = math.max(stufe, 1)
    end

    -- unter der Mindestsumme vom Neupreis bleibt es ok, egal wie alt
    if stufe > 0 and cfg.neukaufMindestNeupreis ~= nil and cfg.neukaufMindestNeupreis > 0 then
        local neupreis = 0
        if self.getPrice ~= nil then
            neupreis = self:getPrice() or 0
        end
        if neupreis > 0 and daten.kostenGesamt < cfg.neukaufMindestNeupreis * neupreis then
            stufe = 0
        end
    end

    return anteil, stufe, wert
end

-- Ueberschriebene Funktionen --------------------------------------------------

function ReparaturOekonomie:getRepairPrice(superFunc)
    local basis = superFunc(self)
    if basis == nil or basis <= 0 then
        return basis or 0
    end
    return basis * ReparaturOekonomie.CFG.grundfaktorReparatur * self:roGetFaktor()
end

function ReparaturOekonomie:getRepaintPrice(superFunc)
    local basis = superFunc(self)
    if basis == nil or basis <= 0 then
        return basis or 0
    end
    return basis * ReparaturOekonomie.CFG.grundfaktorLackieren
end

-- laeuft per WearableRepairEvent ueberall, Zaehler bleiben so ohne eigenes Event gleich
function ReparaturOekonomie:repairVehicle(superFunc, atSellingPoint)
    local preis = 0
    if self.getRepairPrice ~= nil then
        preis = self:getRepairPrice() or 0
    end

    superFunc(self, atSellingPoint)

    -- Reparatur beim Verkauf zaehlt nicht
    if atSellingPoint == true then
        return
    end

    local daten = self:roGetDaten()
    daten.anzahlReparaturen = daten.anzahlReparaturen + 1
    daten.kostenGesamt = daten.kostenGesamt + preis
    daten.warnStufe = 0

    if self.isServer and AOMaschinen ~= nil and AOMaschinen.buchen ~= nil then
        AOMaschinen.buchen(self, "reparatur", preis)
    end
end

function ReparaturOekonomie:updateDamageAmount(superFunc, dt)
    local wert = superFunc(self, dt)
    if wert == nil or wert == 0 then
        return wert or 0
    end
    return wert * ReparaturOekonomie.CFG.tempoSchaden * ReparaturOekonomie.getKlasseTempo(self)
end

-- Lack hier statt in updateWearAmount - das halten die Wear-Nodes als
-- direkte Referenz, ein Override dort greift nicht.
function ReparaturOekonomie:getWearMultiplier(superFunc, nodeData)
    local wert = superFunc(self, nodeData)
    if wert == nil or wert == 0 then
        return wert or 0
    end
    return wert * ReparaturOekonomie.CFG.tempoLack
end

function ReparaturOekonomie:showInfo(superFunc, box)
    superFunc(self, box)

    if box == nil or box.addLine == nil then
        return
    end

    local cfg = ReparaturOekonomie.CFG
    local daten = self:roGetDaten()
    local faktor = self:roGetFaktor()

    -- "Restwert" ist hier der Verkaufspreis wie im Shop, nicht der Zeitwert
    -- aus getRestwert
    local neupreis = 0
    if self.getPrice ~= nil then
        neupreis = self:getPrice() or 0
    end
    if self.getSellPrice ~= nil then
        local verkauf = self:getSellPrice()
        if type(verkauf) == "number" and verkauf > 0 then
            local prozent = (neupreis > 0) and (verkauf / neupreis * 100) or 0
            box:addLine(ReparaturOekonomie.text("ro_restwert", "Restwert"),
                string.format("%s (%.0f %%)", ReparaturOekonomie.formatGeld(verkauf), prozent))
        end
    end

    if faktor > 1.01 then
        box:addLine(ReparaturOekonomie.text("ro_faktor", "Reparaturfaktor"),
            string.format("x %.2f", faktor))
    end

    if self.getRepairPrice ~= nil then
        local preis = self:getRepairPrice() or 0
        if preis > 0 then
            box:addLine(ReparaturOekonomie.text("ro_reparatur", "Reparatur"),
                ReparaturOekonomie.formatGeld(preis))
        end
    end

    if daten.kostenGesamt > 0 then
        box:addLine(ReparaturOekonomie.text("ro_bisher", "Reparaturen bisher"),
            string.format("%s (%dx)", ReparaturOekonomie.formatGeld(daten.kostenGesamt),
                daten.anzahlReparaturen))
    end

    if cfg.anzeigeStundenFaktor ~= 1.0 then
        local stunden = ReparaturOekonomie.getStunden(self) * cfg.anzeigeStundenFaktor
        box:addLine(ReparaturOekonomie.text("ro_stunden", "Betriebsstunden"),
            string.format("%d h", stunden))
    end

    local anteil, stufe = self:roGetBewertung()
    if stufe == 2 then
        box:addLine(ReparaturOekonomie.text("ro_hinweis", "Hinweis"),
            ReparaturOekonomie.text("ro_unwirtschaftlich", "Neukauf pruefen"))
    elseif stufe == 1 then
        box:addLine(ReparaturOekonomie.text("ro_hinweis", "Hinweis"),
            ReparaturOekonomie.text("ro_teuer", "Unterhalt wird teuer"))
    end

    if cfg.debugAnzeige then
        box:addLine("RO Bh", string.format("%.2f", ReparaturOekonomie.getStunden(self)))
        box:addLine("RO Anteil", string.format("%.0f %%", anteil * 100))
        box:addLine("RO Alter/Leben", string.format("%s / %s",
            tostring(self.age), tostring(self.lifetime)))
    end
end

-- Meldung ---------------------------------------------------------------------

function ReparaturOekonomie:onUpdateTick(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    -- nur das Fahrzeug, in dem man sitzt
    if not isActiveForInputIgnoreSelection then
        return
    end

    local cfg = ReparaturOekonomie.CFG
    local daten = self:roGetDaten()

    daten.pruefTimer = (daten.pruefTimer or 0) - dt
    if daten.pruefTimer > 0 then
        return
    end
    daten.pruefTimer = cfg.meldungIntervall

    local _, stufe = self:roGetBewertung()
    if stufe <= (daten.warnStufe or 0) then
        return
    end
    daten.warnStufe = stufe

    local name = "Fahrzeug"
    if self.getFullName ~= nil then
        local voll = self:getFullName()
        if voll ~= nil then
            name = voll
        end
    end

    if stufe == 2 then
        ReparaturOekonomie.zeigeMeldung(string.format(
            ReparaturOekonomie.text("ro_meldungKritisch",
                "%s: Die naechste Reparatur ist unwirtschaftlich. Neukauf pruefen."), name))
    else
        ReparaturOekonomie.zeigeMeldung(string.format(
            ReparaturOekonomie.text("ro_meldungWarnung",
                "%s: Der Unterhalt wird teuer."), name))
    end
end
