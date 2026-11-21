-- DieselVerbrauch.lua
-- Stufenlos einstellbarer Spritverbrauch (Arbeit/Fahrt getrennt), wahlweise
-- aus der Motorleistung statt aus der Fahrzeug-XML. Dazu die Tacho-Anzeige.
-- OGW
--
-- Spiel:  motorFactor = 0.5 * (0.2*rpmFactor + 1.8*loadFactor), verbraucht = Stufe * motorFactor * usage * dt
-- Eigen:  motorFactor = min((0.1*rpmFactor + 0.9*loadFactor) * Wirkungsgrad, 1.25)
--
-- updateConsumers wird nicht ersetzt, nur usage vorher skaliert und danach
-- zurueckgesetzt. Laeuft nur auf dem Server, die Anzeige rechnet am Client nach.

DieselVerbrauch = {}

DieselVerbrauch.LOG = "[AgrarOekonomie] "

-- Deckel gegen Ausreisser beim Drehmoment
DieselVerbrauch.MAX_MOTOR_FACTOR = 1.25

-- darunter (Leerlauf) nicht umrechnen, sonst Division durch fast 0
DieselVerbrauch.MIN_MOTOR_FACTOR = 0.001

-- Tacho-Anzeige in Pixeln des 232er Zifferblatts, knapp unter "km/h"
DieselVerbrauch.ANZEIGE_SCHRIFT_PX  = 11
DieselVerbrauch.ANZEIGE_Y_PX        = -39
DieselVerbrauch.ANZEIGE_ZEITKONSTANTE = 1500  -- ms

-- ist das CoworkerHUD da, zeichnet es die Zeile selbst
DieselVerbrauch.COWORKER_HUD = "FS25_CoworkerHUD"

-- ueberbrueckt das Ausheben am Vorgewende
DieselVerbrauch.ARBEIT_HALTEZEIT = 5000     -- ms

DieselVerbrauch.hooksInstalliert = false

-- Einstellungen ---------------------------------------------------------------

local function getCfg()
    if AgrarOekonomie ~= nil and AgrarOekonomie.CFG ~= nil then
        return AgrarOekonomie.CFG
    end
    return nil
end

-- Luftbremse bleibt aussen vor
local function istMotorVerbrauch(fillType)
    if FillType == nil then
        return false
    end
    return fillType == FillType.DIESEL
        or fillType == FillType.ELECTRICCHARGE
        or fillType == FillType.METHANE
        or fillType == FillType.DEF
end

-- Stufe des Spiels, wird wieder herausgeteilt
local function getSpielStufe()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return 1.5
    end
    local stufe = g_currentMission.missionInfo.fuelUsage
    if stufe == 1 then
        return 1.0
    elseif stufe == 3 then
        return 2.5
    end
    return 1.5
end

local function getSchadensFaktor(vehicle)
    if vehicle == nil or vehicle.getVehicleDamage == nil then
        return 1
    end
    local schaden = vehicle:getVehicleDamage() or 0
    if schaden <= 0 then
        return 1
    end
    return 1 + schaden * (Motorized.DAMAGED_USAGE_INCREASE or 0)
end

-- Lastkurven ------------------------------------------------------------------

local function getSpielMotorFactor(spec)
    local motor = spec.motor
    if motor == nil then
        return nil
    end

    local spanne = (motor.maxRpm or 0) - (motor.minRpm or 0)
    if spanne <= 0 then
        return nil
    end

    local rpmPercentage = ((motor.lastMotorRpm or 0) - (motor.minRpm or 0)) / spanne
    local rpmFactor     = 0.5 + rpmPercentage * 0.5
    local last          = spec.smoothedLoadPercentage or 0
    local loadFactor    = math.max(last * rpmPercentage, 0)

    return 0.5 * ((0.2 * rpmFactor) + (1.8 * loadFactor))
end

-- Anteil an der Nennleistung plus Wirkungsgrad ueber der Drehzahl. Last aus
-- smoothedLoadPercentage, weil motorAppliedTorque ungeglaettet ist und Server
-- und Anzeige sonst verschiedene Werte erwischen.
local function getEigenerMotorFactor(spec)
    local motor = spec.motor
    if motor == nil then
        return nil
    end

    local nennDrehzahl = motor.peakMotorPowerRotSpeed
    if nennDrehzahl == nil or nennDrehzahl <= 0 then
        return nil
    end

    local last = spec.smoothedLoadPercentage or 0
    if last < 0 then
        last = 0
    elseif last > 1 then
        last = 1
    end

    -- motorRotSpeed ist nur am Server echt, am Client oft 0. Dort deshalb die
    -- vom Server gesendete lastMotorRpm (U/min -> rad/s).
    local rotSpeed = motor.motorRotSpeed or 0
    local vomServer = (motor.lastMotorRpm or 0) * math.pi / 30
    if motor.vehicle ~= nil and motor.vehicle.isServer ~= true then
        rotSpeed = vomServer
    elseif rotSpeed <= 0 then
        rotSpeed = vomServer
    end
    local rpmFactor = rotSpeed / nennDrehzahl
    local loadFactor = last * math.min(rpmFactor, 1)

    -- bestes Band 75-100 % Nenndrehzahl, darunter/darueber mehr Verbrauch
    local efficiencyFx = 1
    local untereGrenze = 0.75 * nennDrehzahl
    if rotSpeed < untereGrenze then
        efficiencyFx = 1 + 0.00159 * (untereGrenze - rotSpeed)
    elseif rotSpeed > nennDrehzahl then
        efficiencyFx = 1 + 0.004775 * (rotSpeed - nennDrehzahl)
    end

    local faktor = (0.1 * rpmFactor + 0.9 * loadFactor) * efficiencyFx
    if faktor > DieselVerbrauch.MAX_MOTOR_FACTOR then
        faktor = DieselVerbrauch.MAX_MOTOR_FACTOR
    end
    if faktor < 0 then
        faktor = 0
    end

    return faktor
end

-- Umrechnung ------------------------------------------------------------------

-- Arbeit = eingeschaltet, Werkzeug im Boden oder gerade Flaeche bearbeitet.
-- isTurnedOn als Feld, weil getIsTurnedOn() bei isAlwaysTurnedOn immer an ist.
-- lastProcessingTime gibt es nur am Server, groundReferenceNode auch am Client.
local function erkenneArbeit(wurzel, jetzt)
    local gespann = nil
    if wurzel.getChildVehicles ~= nil then
        gespann = wurzel:getChildVehicles()
    end
    if gespann == nil then
        return false
    end

    for _, teil in ipairs(gespann) do
        local turnOn = teil.spec_turnOnVehicle
        if turnOn ~= nil and turnOn.isTurnedOn == true then
            return true
        end

        local wa = teil.spec_workArea
        if wa ~= nil and wa.workAreas ~= nil then
            for _, workArea in ipairs(wa.workAreas) do
                local boden = workArea.groundReferenceNode
                if workArea.requiresGroundContact == true and boden ~= nil
                        and boden.isActive == true then
                    return true
                end
                local zeit = workArea.lastProcessingTime
                if zeit ~= nil and zeit > 0 and jetzt - zeit < 1000 then
                    return true
                end
            end
        end
    end

    return false
end

function DieselVerbrauch.istAmArbeiten(vehicle)
    if vehicle == nil or g_currentMission == nil then
        return false
    end

    local wurzel = vehicle
    if vehicle.getRootVehicle ~= nil then
        wurzel = vehicle:getRootVehicle() or vehicle
    end

    local jetzt = g_currentMission.time or 0
    if erkenneArbeit(wurzel, jetzt) then
        wurzel.aoLetzteArbeit = jetzt
        return true
    end

    local letzte = wurzel.aoLetzteArbeit
    return letzte ~= nil and jetzt - letzte < DieselVerbrauch.ARBEIT_HALTEZEIT
end

function DieselVerbrauch.getModusFaktor(vehicle, cfg)
    if DieselVerbrauch.istAmArbeiten(vehicle) then
        return cfg.dieselFaktor or 1.0
    end
    return cfg.dieselFaktorFahrt or 1.0
end

function DieselVerbrauch.getGrundFaktor(vehicle, spec, cfg)
    local faktor = DieselVerbrauch.getModusFaktor(vehicle, cfg) / getSpielStufe()

    if cfg.dieselLastkurve == true then
        local spiel = getSpielMotorFactor(spec)
        local eigen = getEigenerMotorFactor(spec)
        if spiel ~= nil and eigen ~= nil and spiel > DieselVerbrauch.MIN_MOTOR_FACTOR then
            faktor = faktor * (eigen / spiel)
        end
    end

    return faktor
end

-- Verbrauch aus Nennleistung geteilt durch XML-Wert, 1 wenn aus
function DieselVerbrauch.getLeistungsVerhaeltnis(spec, cfg)
    local proKwh = cfg.dieselProKwh or 0
    if proKwh <= 0 then
        return 1
    end

    local motor = spec.motor
    if motor == nil or motor.peakMotorPower == nil or motor.peakMotorPower <= 0 then
        return 1
    end

    for _, consumer in pairs(spec.consumers) do
        if consumer.permanentConsumption and consumer.fillType == FillType.DIESEL
                and (consumer.usage or 0) > 0 then
            -- usage ist l/ms
            local ziel = motor.peakMotorPower * proKwh / 3600000
            if ziel > 0 then
                return ziel / consumer.usage
            end
        end
    end

    return 1
end

-- AdBlue bekommt dasselbe Verhaeltnis wie Diesel, Strom und Methan nicht
function DieselVerbrauch.getVerbraucherFaktor(consumer, grundFaktor, verhaeltnis)
    if consumer.fillType == FillType.DIESEL or consumer.fillType == FillType.DEF then
        return grundFaktor * verhaeltnis
    end
    return grundFaktor
end

-- Hook ------------------------------------------------------------------------

local verbrauchen

function DieselVerbrauch.updateConsumers(self, superFunc, dt, accInput)
    if AOMaschinen ~= nil then
        AOMaschinen.imVerbrauch = self
    end
    verbrauchen(self, superFunc, dt, accInput)
    if AOMaschinen ~= nil then
        AOMaschinen.imVerbrauch = nil
    end
end

verbrauchen = function(self, superFunc, dt, accInput)
    local cfg = getCfg()
    if cfg == nil or cfg.dieselAktiv ~= true then
        superFunc(self, dt, accInput)
        return
    end

    local spec = self.spec_motorized
    if spec == nil or spec.consumers == nil or spec.motor == nil then
        superFunc(self, dt, accInput)
        return
    end

    local grundFaktor = DieselVerbrauch.getGrundFaktor(self, spec, cfg)
    if grundFaktor == nil or grundFaktor < 0 then
        superFunc(self, dt, accInput)
        return
    end
    local verhaeltnis = DieselVerbrauch.getLeistungsVerhaeltnis(spec, cfg)

    local gemerkt = nil
    for _, consumer in pairs(spec.consumers) do
        if consumer.permanentConsumption and (consumer.usage or 0) > 0
                and istMotorVerbrauch(consumer.fillType) then
            local faktor = DieselVerbrauch.getVerbraucherFaktor(consumer, grundFaktor, verhaeltnis)
            if faktor ~= nil and faktor >= 0 and faktor ~= 1 then
                if gemerkt == nil then
                    gemerkt = {}
                end
                gemerkt[consumer] = consumer.usage
                consumer.usage = consumer.usage * faktor
            end
        end
    end

    superFunc(self, dt, accInput)

    if gemerkt ~= nil then
        for consumer, wert in pairs(gemerkt) do
            consumer.usage = wert
        end
    end
end

function DieselVerbrauch.installiereHooks()
    if DieselVerbrauch.hooksInstalliert then
        return
    end

    if Motorized == nil or Motorized.updateConsumers == nil
            or Utils == nil or Utils.overwrittenFunction == nil then
        Logging.warning(DieselVerbrauch.LOG ..
            "Motorized.updateConsumers nicht gefunden - Spritverbrauch bleibt unveraendert.")
        return
    end

    Motorized.updateConsumers = Utils.overwrittenFunction(
        Motorized.updateConsumers, DieselVerbrauch.updateConsumers)

    DieselVerbrauch.hooksInstalliert = true
end

-- Rechnung fuer Anzeige und Konsole -------------------------------------------

-- Wird vom CoworkerHUD aufgerufen, Name nicht aendern.
-- Liefert l/h laut Datei und mit dieser Mod, nil ohne Diesel.
function DieselVerbrauch.berechneLiterJeStunde(vehicle, volllast)
    local spec = vehicle.spec_motorized
    if spec == nil or spec.consumers == nil or spec.motor == nil then
        return nil, nil
    end

    local diesel = nil
    for _, consumer in pairs(spec.consumers) do
        if consumer.permanentConsumption and consumer.fillType == FillType.DIESEL
                and (consumer.usage or 0) > 0 then
            diesel = consumer
            break
        end
    end
    if diesel == nil then
        return nil, nil
    end

    local motorFactor = 1
    if not volllast then
        motorFactor = getSpielMotorFactor(spec) or 0
    end

    local basis = getSpielStufe() * getSchadensFaktor(vehicle) * motorFactor * 3600000
    local datei = basis * diesel.usage

    local cfg = getCfg()
    if cfg == nil or cfg.dieselAktiv ~= true then
        return datei, datei
    end

    local grund = DieselVerbrauch.getGrundFaktor(vehicle, spec, cfg)
    if volllast then
        -- bei Volllast liefern beide Kurven 1
        grund = DieselVerbrauch.getModusFaktor(vehicle, cfg) / getSpielStufe()
    end
    local verhaeltnis = DieselVerbrauch.getLeistungsVerhaeltnis(spec, cfg)

    return datei, datei * DieselVerbrauch.getVerbraucherFaktor(diesel, grund, verhaeltnis)
end

-- Tankstand -------------------------------------------------------------------

-- Abgebucht wird erst ab vollem Liter, der Rest in fillLevelToChange zaehlt
-- schon als verbraucht. Am MP-Client ist der Rest immer 0.
local function getDieselStand(vehicle)
    local spec = vehicle.spec_motorized
    if spec == nil or spec.consumers == nil or vehicle.getFillUnitFillLevel == nil then
        return nil
    end
    for _, consumer in pairs(spec.consumers) do
        if consumer.permanentConsumption and consumer.fillType == FillType.DIESEL then
            local stand = vehicle:getFillUnitFillLevel(consumer.fillUnitIndex)
            if stand == nil then
                return nil
            end
            return stand - (consumer.fillLevelToChange or 0)
        end
    end
    return nil
end

-- Anzeige im Tacho ------------------------------------------------------------

local function text(schluessel)
    if g_i18n ~= nil and g_i18n.getText ~= nil then
        return g_i18n:getText(schluessel)
    end
    return schluessel
end

-- unter 10 l/h eine Nachkommastelle, sonst steht beim Hoflader nur 0
function DieselVerbrauch.formatLiterJeStunde(literJeStunde)
    local stellen = 0
    if literJeStunde < 9.95 then
        stellen = 1
    end
    if g_i18n ~= nil and g_i18n.formatNumber ~= nil then
        return g_i18n:formatNumber(literJeStunde, stellen) .. " l/h"
    end
    if stellen == 1 then
        return string.format("%.1f l/h", literJeStunde)
    end
    return string.format("%.0f l/h", literJeStunde)
end

-- Wird vom CoworkerHUD aufgerufen, Name nicht aendern.
-- Rueckgabe: literJeStunde (geglaettet), istArbeit, modusText, anzeigeText
-- oder nil, wenn nichts anzuzeigen ist.
function DieselVerbrauch.getAnzeige(vehicle)
    local cfg = getCfg()
    if cfg == nil or cfg.dieselAktiv ~= true or cfg.dieselAnzeige ~= true then
        return nil
    end
    if vehicle == nil or vehicle.spec_motorized == nil then
        return nil
    end

    local _, jetzt = DieselVerbrauch.berechneLiterJeStunde(vehicle, false)
    if jetzt == nil then
        return nil
    end

    -- ueber die Zeit glaetten, nicht je Bild
    local spec = vehicle.spec_motorized
    local zeit = g_time or 0
    if spec.aoSpritAnzeige == nil or spec.aoSpritZeit == nil then
        spec.aoSpritAnzeige = jetzt
    else
        local schritt = zeit - spec.aoSpritZeit
        local anteil = 1
        if schritt >= 0 and schritt < DieselVerbrauch.ANZEIGE_ZEITKONSTANTE then
            anteil = schritt / DieselVerbrauch.ANZEIGE_ZEITKONSTANTE
        end
        spec.aoSpritAnzeige = spec.aoSpritAnzeige + (jetzt - spec.aoSpritAnzeige) * anteil
    end
    spec.aoSpritZeit = zeit

    local arbeit = DieselVerbrauch.istAmArbeiten(vehicle)
    local modus = text("ao_hud_spFahrt")
    if arbeit then
        modus = text("ao_hud_spArbeit")
    end
    return spec.aoSpritAnzeige, arbeit, modus,
        DieselVerbrauch.formatLiterJeStunde(spec.aoSpritAnzeige)
end

local function getTacho()
    if g_currentMission == nil or g_currentMission.hud == nil then
        return nil, nil
    end
    local hud = g_currentMission.hud
    if hud.isVisible == false then
        return nil, nil
    end
    local tacho = hud.speedMeter
    if tacho == nil or tacho.vehicle == nil or tacho.speedBg == nil then
        return nil, nil
    end
    local bg = tacho.speedBg
    if bg.x == nil or bg.y == nil or bg.width == nil or bg.height == nil
            or bg.width <= 0 or bg.height <= 0 then
        return nil, nil
    end
    return tacho, bg
end

local function breite(groesse, zeile)
    if getTextWidth ~= nil then
        return getTextWidth(groesse, zeile) or 0
    end
    return 0
end

function DieselVerbrauch:draw()
    if g_modIsLoaded ~= nil and g_modIsLoaded[DieselVerbrauch.COWORKER_HUD] then
        return
    end
    if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil then
        return
    end

    local tacho, bg = getTacho()
    if bg == nil then
        return
    end

    local literJeStunde, _, modus, anzeigeText =
        DieselVerbrauch.getAnzeige(g_localPlayer:getCurrentVehicle())
    if literJeStunde == nil then
        return
    end

    -- Mitte des Zifferblatts, Ersatzwerte falls das Spiel sie nicht gesetzt hat
    local py = bg.height / 232
    local mitteX = bg.x + (tacho.speedGaugeCenterOffsetX or bg.width * 117 / 232)
    local mitteY = bg.y + (tacho.speedGaugeCenterOffsetY or bg.height * 116 / 232)

    local groesse = DieselVerbrauch.ANZEIGE_SCHRIFT_PX * py
    local y = mitteY + DieselVerbrauch.ANZEIGE_Y_PX * py

    local teil1 = modus .. "  "
    local teil2 = anzeigeText
    local x = mitteX - (breite(groesse, teil1) + breite(groesse, teil2)) * 0.5

    local r, g, b, a = 0.62, 0.86, 0.17, 1.0
    if HUD ~= nil and HUD.COLOR ~= nil and HUD.COLOR.ACTIVE ~= nil then
        r, g, b, a = unpack(HUD.COLOR.ACTIVE)
    end

    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(r, g, b, a)
    renderText(x, y, groesse, teil1)
    setTextColor(1, 1, 1, 1)
    renderText(x + breite(groesse, teil1), y, groesse, teil2)
end

-- Konsole ---------------------------------------------------------------------

function DieselVerbrauch:consoleStatus()
    local cfg = getCfg()
    if cfg == nil then
        return DieselVerbrauch.LOG .. "Einstellungen noch nicht bereit."
    end

    local zeilen = {
        "=== Spritverbrauch ===",
        string.format("Aktiv            : %s", tostring(cfg.dieselAktiv)),
        string.format("Faktor Arbeit    : %.2f  (Spielstufe %.1f wird herausgerechnet)",
            cfg.dieselFaktor or 1.0, getSpielStufe()),
        string.format("Faktor Fahrt     : %.2f", cfg.dieselFaktorFahrt or 1.0),
        string.format("Liter je kWh     : %.3f  (0 = Wert aus der Fahrzeugdatei)",
            cfg.dieselProKwh or 0),
        string.format("Eigene Lastkurve : %s", tostring(cfg.dieselLastkurve)),
        string.format("Anzeige          : %s", tostring(cfg.dieselAnzeige)),
    }

    local fahrzeug = nil
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        fahrzeug = g_localPlayer:getCurrentVehicle()
    end

    if fahrzeug == nil or fahrzeug.spec_motorized == nil then
        table.insert(zeilen, "Kein Fahrzeug - fuer die Einzelwerte in eines einsteigen.")
        return table.concat(zeilen, "\n")
    end

    local motor = fahrzeug.spec_motorized.motor
    if motor ~= nil and (motor.peakMotorPower or 0) > 0 then
        table.insert(zeilen, string.format("Nennleistung     : %.0f kW (%.0f PS) bei %.0f min-1",
            motor.peakMotorPower, motor.peakMotorPower * 1.35962,
            (motor.peakMotorPowerRotSpeed or 0) * 30 / math.pi))
    end

    local modus = "Fahrt"
    if DieselVerbrauch.istAmArbeiten(fahrzeug) then
        modus = "Arbeit"
    end
    table.insert(zeilen, string.format("Betriebsart jetzt: %s", modus))

    local datei, jetzt = DieselVerbrauch.berechneLiterJeStunde(fahrzeug, true)
    if datei == nil then
        table.insert(zeilen, "Dieses Fahrzeug verbraucht keinen Diesel.")
    elseif cfg.dieselAktiv == true then
        table.insert(zeilen, string.format(
            "Volllast         : %.1f l/h laut Datei  ->  %.1f l/h mit dieser Einstellung",
            datei, jetzt))
    else
        table.insert(zeilen, string.format(
            "Volllast         : %.1f l/h laut Datei (Modul aus, dieser Wert gilt)", datei))
    end

    return table.concat(zeilen, "\n")
end

-- Messung ---------------------------------------------------------------------

-- Misst am Tankstand statt an lastFuelUsage, das springt bei jedem
-- abgebuchten Liter.
DieselVerbrauch.messung = nil

function DieselVerbrauch:consoleMessen()
    local fahrzeug = nil
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        fahrzeug = g_localPlayer:getCurrentVehicle()
    end
    if fahrzeug == nil then
        DieselVerbrauch.messung = nil
        return "Erst in ein Fahrzeug einsteigen."
    end

    local stand = getDieselStand(fahrzeug)
    if stand == nil then
        DieselVerbrauch.messung = nil
        return "Dieses Fahrzeug verbraucht keinen Diesel."
    end

    local m = DieselVerbrauch.messung
    if m == nil or m.fahrzeug ~= fahrzeug then
        DieselVerbrauch.messung = { fahrzeug = fahrzeug, stand = stand, zeit = g_time }
        return "Messung gestartet. Jetzt mindestens eine Minute gleichmaessig fahren, "
            .. "dann aoSpritMessen erneut eingeben."
    end

    DieselVerbrauch.messung = nil
    local sekunden = (g_time - m.zeit) / 1000
    if sekunden < 10 then
        return "Zu kurz gemessen - bitte mindestens eine Minute fahren."
    end

    local liter = m.stand - stand
    return string.format("Gemessen: %.2f l in %.0f s = %.1f l/h tatsaechlicher Verbrauch",
        liter, sekunden, liter * 3600 / sekunden)
end

function DieselVerbrauch.registriereBefehle()
    if addConsoleCommand == nil then
        return
    end
    addConsoleCommand("aoSprit", "Zeigt die Spritverbrauch-Einstellung und das aktuelle Fahrzeug.",
        "consoleStatus", DieselVerbrauch)
    addConsoleCommand("aoSpritMessen", "Misst den tatsaechlichen Verbrauch am Tankstand (zweimal aufrufen).",
        "consoleMessen", DieselVerbrauch)
end

-- Lebenszyklus ----------------------------------------------------------------

-- Spezialisierungen sind beim Laden der Datei schon da, loadMap ist nur Reserve.
DieselVerbrauch.installiereHooks()


function DieselVerbrauch:loadMap(name)
    DieselVerbrauch.installiereHooks()
    DieselVerbrauch.registriereBefehle()

    local cfg = getCfg()
    Logging.info(DieselVerbrauch.LOG .. "Spritverbrauch bereit (aktiv=%s).",
        tostring(cfg ~= nil and cfg.dieselAktiv or false))
end


addModEventListener(DieselVerbrauch)
