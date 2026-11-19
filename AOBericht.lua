-- AOBericht.lua
-- Monatssummen je Farm fuer den Jahresvergleich, dazu der Betriebsstand zu
-- jedem Monatsbeginn. Verglichen werden immer dieselben Monate beider Jahre.
-- Die Anzeige macht FS25_FarmOverview, die paket, GRUPPEN, STAND, anfordern()
-- und monatsName() direkt benutzt - also nicht umbenennen.
-- Gerechnet wird nur auf dem Server, Clients holen sich ihr Paket per AOBerichtEvent.
-- OGW

AOBericht = {}

AOBericht.LOG = "[AgrarOekonomie] "

-- Anzeige-Reihenfolge; inv = Kaeufe minus Verkaeufe von Anlagegut
AOBericht.GRUPPEN = {
    { id = "ernte",          art = "ein", label = "ao_rep_ernte" },
    { id = "produkte",       art = "ein", label = "ao_rep_produkte" },
    { id = "tiere",          art = "ein", label = "ao_rep_tiere" },
    { id = "ballenHolz",     art = "ein", label = "ao_rep_ballenHolz" },
    { id = "energie",        art = "ein", label = "ao_rep_energie" },
    { id = "auftraege",      art = "ein", label = "ao_rep_auftraege" },
    { id = "sonstEin",       art = "ein", label = "ao_rep_sonstEin" },
    { id = "betriebsmittel", art = "aus", label = "ao_rep_betriebsmittel" },
    { id = "fahrzeugKosten", art = "aus", label = "ao_rep_fahrzeugKosten" },
    { id = "gebaeudeKosten", art = "aus", label = "ao_rep_gebaeudeKosten" },
    { id = "loehne",         art = "aus", label = "ao_rep_loehne" },
    { id = "zinsen",         art = "aus", label = "ao_rep_zinsen" },
    { id = "sonstAus",       art = "aus", label = "ao_rep_sonstAus" },
    { id = "investFahrzeuge", art = "inv", label = "ao_rep_investFahrzeuge" },
    { id = "investBau",       art = "inv", label = "ao_rep_investBau" },
    { id = "investLand",      art = "inv", label = "ao_rep_investLand" },
    { id = "investTiere",     art = "inv", label = "ao_rep_investTiere" },
}

-- moneyType.statistic -> Gruppe. Unbekanntes geht nach sonstEin/sonstAus,
-- false heisst gar nicht erfassen (Kredit ist weder Einnahme noch Ausgabe).
AOBericht.ZUORDNUNG = {
    harvestIncome      = "ernte",
    soldProducts       = "produkte",
    soldAnimals        = "tiere",
    soldMilk           = "tiere",
    soldWool           = "tiere",
    soldEggs           = "tiere",
    soldBales          = "ballenHolz",
    soldWood           = "ballenHolz",
    incomeBga          = "energie",
    missionIncome      = "auftraege",
    propertyIncome     = "sonstEin",

    purchaseSeeds      = "betriebsmittel",
    purchaseFertilizer = "betriebsmittel",
    purchaseFuel       = "betriebsmittel",
    purchaseSaplings   = "betriebsmittel",
    purchaseWater      = "betriebsmittel",
    purchaseBales      = "betriebsmittel",
    purchasePallets    = "betriebsmittel",
    vehicleRunningCost = "fahrzeugKosten",
    vehicleLeasingCost = "fahrzeugKosten",
    propertyMaintenance = "gebaeudeKosten",
    productionCosts    = "gebaeudeKosten",
    wagePayment        = "loehne",
    loanInterest       = "zinsen",

    newVehiclesCost    = "investFahrzeuge",
    soldVehicles       = "investFahrzeuge",
    newHandtoolsCost   = "investFahrzeuge",
    soldHandtools      = "investFahrzeuge",
    constructionCost   = "investBau",
    soldBuildings      = "investBau",
    fieldPurchase      = "investLand",
    fieldSelling       = "investLand",
    newAnimalsCost     = "investTiere",

    loan               = false,
}

-- Reihenfolge gilt auch fuers Netzwerk-Paket
AOBericht.STAND = {
    "vermoegen", "geld", "kredit", "fahrzeuge", "gebaeude",
    "land", "landHa", "feldHa", "anzahlFahrzeuge",
}

AOBericht.daten         = {}     -- [farmId] = siehe getDaten
AOBericht.letztePeriode = nil
AOBericht.abonniert     = false
AOBericht.speicherHook  = false

AOBericht.paket = nil   -- zuletzt empfangen (Client) oder berechnet (SP)

function AOBericht.aktuellePeriode()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and type(env.currentPeriod) == "number" and env.currentPeriod >= 1 then
        return math.floor(env.currentPeriod)
    end
    return 1
end

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

function AOBericht.monatsName(periode)
    if g_i18n ~= nil and g_i18n.formatPeriod ~= nil then
        local txt = g_i18n:formatPeriod(periode)
        if type(txt) == "string" and txt ~= "" then
            return txt
        end
    end
    local vorlage = "Monat %s"
    if AOSettingsPage ~= nil then
        vorlage = AOSettingsPage.getText("ao_rep_monat")
    end
    local txt = formatiereVorlage(vorlage, { tostring(periode) })
    return txt or tostring(periode)
end

function AOBericht.gruppeFuer(moneyType, betrag)
    local statistik = AgrarOekonomie.getStatistik(moneyType)
    -- kein "a and b or nil" - fuer loan steht dort false, das wuerde zu nil
    local gruppe = nil
    if statistik ~= nil then
        gruppe = AOBericht.ZUORDNUNG[statistik]
    end
    if gruppe == false then
        return nil
    end
    if gruppe == nil then
        return betrag >= 0 and "sonstEin" or "sonstAus"
    end
    return gruppe
end

function AOBericht.getDaten(farmId)
    local d = AOBericht.daten[farmId]
    if d == nil then
        d = {
            erfasstAb        = AOBericht.aktuellePeriode(),
            vorjahrErfasstAb = 1,
            hatVorjahr       = false,
            jahr             = {},   -- [periode] = { [gruppe] = betrag }
            vorjahr          = {},
            stand            = {},   -- [periode] = { [kennzahl] = wert }
            vorjahrStand     = {},
        }
        AOBericht.daten[farmId] = d
    end
    return d
end

local function summe(monate, gruppe, von, bis)
    local s = 0
    if type(monate) ~= "table" then
        return s
    end
    for m = von, bis do
        local eintrag = monate[m]
        if eintrag ~= nil and eintrag[gruppe] ~= nil then
            s = s + eintrag[gruppe]
        end
    end
    return s
end

-- kommt aus dem Geld-Hook, Betrag schon nach Preisfaktor
function AOBericht.buche(farmId, moneyType, betrag)
    if betrag == nil or betrag == 0 or not AgrarOekonomie.istSpielerFarm(farmId) then
        return
    end
    local gruppe = AOBericht.gruppeFuer(moneyType, betrag)
    if gruppe == nil then
        return
    end
    local d = AOBericht.getDaten(farmId)
    local p = AOBericht.aktuellePeriode()
    local monat = d.jahr[p]
    if monat == nil then
        monat = {}
        d.jahr[p] = monat
    end
    monat[gruppe] = (monat[gruppe] or 0) + betrag
end

-- Betriebsstand ---------------------------------------------------------------

function AOBericht.getFeldHektar(farmId)
    local ha = 0
    if g_fieldManager == nil or g_fieldManager.getFields == nil
            or AOAutomatik == nil or AOAutomatik.getFeldBesitzer == nil then
        return ha
    end
    local felder = g_fieldManager:getFields()
    if type(felder) ~= "table" then
        return ha
    end
    for _, feld in pairs(felder) do
        if type(feld) == "table" and AOAutomatik.getFeldBesitzer(feld) == farmId then
            ha = ha + (tonumber(feld.areaHa) or 0)
        end
    end
    return ha
end

-- nur auf dem Server vollstaendig
function AOBericht.ermittleStand(farmId)
    local s = {}
    for _, k in ipairs(AOBericht.STAND) do
        s[k] = 0
    end

    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if type(farm) == "table" then
            s.geld   = tonumber(farm.money) or 0
            s.kredit = tonumber(farm.loan) or 0
        end
    end

    -- wie bei der Fuhrpark-Steuer (keine Paletten/Ballen), aber ohne Leasing
    local vehicleSystem = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    if vehicleSystem ~= nil and type(vehicleSystem.vehicles) == "table"
            and VehiclePropertyState ~= nil then
        for _, v in ipairs(vehicleSystem.vehicles) do
            if type(v) == "table" and v.ownerFarmId == farmId
                    and (v.spec_motorized ~= nil or v.spec_attachable ~= nil)
                    and v.propertyState == VehiclePropertyState.OWNED
                    and v.getSellPrice ~= nil then
                local preis = v:getSellPrice()
                if type(preis) == "number" then
                    s.fahrzeuge = s.fahrzeuge + preis
                end
                s.anzahlFahrzeuge = s.anzahlFahrzeuge + 1
            end
        end
    end

    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if placeableSystem ~= nil and type(placeableSystem.placeables) == "table" then
        for _, p in pairs(placeableSystem.placeables) do
            if type(p) == "table" and p.ownerFarmId == farmId and p.getSellPrice ~= nil then
                local preis = p:getSellPrice()
                if type(preis) == "number" then
                    s.gebaeude = s.gebaeude + preis
                end
            end
        end
    end

    if AOGrundsteuer ~= nil and AOGrundsteuer.getLandwert ~= nil then
        local wert, _, ha = AOGrundsteuer.getLandwert(farmId)
        s.land   = tonumber(wert) or 0
        s.landHa = tonumber(ha) or 0
    end
    s.feldHa = AOBericht.getFeldHektar(farmId)

    s.vermoegen = s.geld - s.kredit + s.fahrzeuge + s.gebaeude + s.land
    return s
end

function AOBericht.standFesthalten(periode, nurFehlende)
    if g_farmManager == nil or g_farmManager.getFarms == nil then
        return
    end
    local farms = g_farmManager:getFarms()
    if type(farms) ~= "table" then
        return
    end
    for _, farm in pairs(farms) do
        local id = type(farm) == "table" and farm.farmId or nil
        if type(id) == "number" and AgrarOekonomie.istSpielerFarm(id) then
            local d = AOBericht.getDaten(id)
            if not nurFehlende or d.stand[periode] == nil then
                d.stand[periode] = AOBericht.ermittleStand(id)
            end
        end
    end
end

-- Neues Jahr = Periode springt zurueck (12 -> 1), ein eigenes Event gibt es nicht.
function AOBericht.jahreswechsel()
    for _, d in pairs(AOBericht.daten) do
        d.vorjahr          = d.jahr
        d.vorjahrStand     = d.stand
        d.vorjahrErfasstAb = d.erfasstAb
        d.hatVorjahr       = true
        d.jahr             = {}
        d.stand            = {}
        d.erfasstAb        = 1
    end
    Logging.info(AOBericht.LOG .. "Betriebsuebersicht: neues Spieljahr begonnen.")
end

function AOBericht.onPeriodeGewechselt(_)
    if not AgrarOekonomie.istServer() then
        return
    end
    local p = AOBericht.aktuellePeriode()
    if AOBericht.letztePeriode ~= nil and p < AOBericht.letztePeriode then
        AOBericht.jahreswechsel()
    end
    AOBericht.letztePeriode = p
    AOBericht.standFesthalten(p, false)
    -- gespeichert wird erst mit dem Spielstand, sonst laufen beide auseinander
end

-- Anzeige ---------------------------------------------------------------------

function AOBericht.erstellePaket(farmId)
    if type(farmId) ~= "number" then
        return nil
    end
    local d = AOBericht.getDaten(farmId)
    local m = AOBericht.aktuellePeriode()

    local von        = math.min(d.erfasstAb, m)
    local vergleich  = false
    if d.hatVorjahr then
        local gemeinsam = math.max(d.erfasstAb, d.vorjahrErfasstAb)
        if gemeinsam <= m then
            von       = gemeinsam
            vergleich = true
        end
    end

    local paket = {
        von = von, bis = m, vergleich = vergleich,
        gruppen = {}, stand = {}, standVorjahr = {}, standVergleich = false,
    }

    for i, g in ipairs(AOBericht.GRUPPEN) do
        paket.gruppen[i] = {
            jetzt   = summe(d.jahr, g.id, von, m),
            vorjahr = vergleich and summe(d.vorjahr, g.id, von, m) or 0,
        }
    end

    local jetzt = AOBericht.ermittleStand(farmId)
    local vor   = d.hatVorjahr and type(d.vorjahrStand) == "table" and d.vorjahrStand[m] or nil
    paket.standVergleich = (vor ~= nil)
    for i, k in ipairs(AOBericht.STAND) do
        paket.stand[i]        = jetzt[k] or 0
        paket.standVorjahr[i] = vor ~= nil and (vor[k] or 0) or 0
    end
    return paket
end

-- SP/Host rechnet direkt, Clients fragen per Event (Antwort landet in empfange)
function AOBericht.anfordern()
    local farmId = nil
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        farmId = g_currentMission:getFarmId()
    end
    if type(farmId) ~= "number" or farmId < 1 then
        return
    end

    if AgrarOekonomie.istServer() then
        AOBericht.paket = AOBericht.erstellePaket(farmId)
        return
    end

    if g_client ~= nil and g_client.getServerConnection ~= nil and AOBerichtEvent ~= nil then
        local conn = g_client:getServerConnection()
        if conn ~= nil and conn.sendEvent ~= nil then
            conn:sendEvent(AOBerichtEvent.new(true, farmId, nil))
        end
    end
end

function AOBericht.empfange(farmId, paket)
    AOBericht.paket = paket
end

-- Speichern je Spielstand -----------------------------------------------------

function AOBericht.getStateFilename()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    -- nicht cachen, der Ordner wird beim Speichern neu angelegt
    local dir = g_currentMission.missionInfo.savegameDirectory
    if dir == nil then
        return nil
    end
    return dir .. "/FS25_FarmEconomy_Bericht.xml"
end

local function gruppenIds()
    local ids = {}
    for _, g in ipairs(AOBericht.GRUPPEN) do
        table.insert(ids, g.id)
    end
    return ids
end

local function schreibeMonate(xml, schluessel, monate, felder)
    local j = 0
    for m = 1, 12 do
        local eintrag = monate[m]
        if eintrag ~= nil then
            local mk = string.format("%s.monat(%d)", schluessel, j)
            xml:setInt(mk .. "#nr", m)
            for _, feld in ipairs(felder) do
                local v = eintrag[feld]
                if v ~= nil and v ~= 0 then
                    xml:setFloat(mk .. "#" .. feld, v)
                end
            end
            j = j + 1
        end
    end
end

local function leseMonate(xml, schluessel, felder)
    local monate = {}
    local j = 0
    while true do
        local mk = string.format("%s.monat(%d)", schluessel, j)
        local nr = xml:getInt(mk .. "#nr", nil)
        if nr == nil then
            break
        end
        local eintrag = {}
        for _, feld in ipairs(felder) do
            local v = xml:getFloat(mk .. "#" .. feld, nil)
            if v ~= nil then
                eintrag[feld] = v
            end
        end
        monate[nr] = eintrag
        j = j + 1
    end
    return monate
end

function AOBericht.speichern()
    if not AgrarOekonomie.istServer() then
        return
    end
    local filename = AOBericht.getStateFilename()
    if filename == nil or XMLFile == nil then
        return
    end

    local wurzel = "farmEconomyBericht"
    local xml = XMLFile.create("aoBerichtXML", filename, wurzel)
    if xml == nil then
        return
    end
    local ids = gruppenIds()
    xml:setInt(wurzel .. "#letztePeriode", AOBericht.letztePeriode or 0)

    local i = 0
    for farmId, d in pairs(AOBericht.daten) do
        -- nur Spieler-Farmen, alte Eintraege von Hilfsfarmen fliegen so raus
        if type(farmId) == "number" and type(d) == "table"
                and AgrarOekonomie.istSpielerFarm(farmId) then
            local fk = string.format("%s.farm(%d)", wurzel, i)
            xml:setInt(fk .. "#id", farmId)
            xml:setInt(fk .. "#erfasstAb", d.erfasstAb or 1)
            xml:setInt(fk .. "#vorjahrErfasstAb", d.vorjahrErfasstAb or 1)
            xml:setBool(fk .. "#hatVorjahr", d.hatVorjahr == true)
            schreibeMonate(xml, fk .. ".jahr",         d.jahr or {},         ids)
            schreibeMonate(xml, fk .. ".vorjahr",      d.vorjahr or {},      ids)
            schreibeMonate(xml, fk .. ".stand",        d.stand or {},        AOBericht.STAND)
            schreibeMonate(xml, fk .. ".vorjahrStand", d.vorjahrStand or {}, AOBericht.STAND)
            i = i + 1
        end
    end

    xml:save()
    xml:delete()
end

function AOBericht.laden()
    AOBericht.daten         = {}
    AOBericht.letztePeriode = nil

    local filename = AOBericht.getStateFilename()
    if filename == nil or XMLFile == nil then
        return
    end

    local wurzel = "farmEconomyBericht"
    local xml = XMLFile.loadIfExists("aoBerichtXML", filename)
    if xml == nil then
        return
    end
    local ids = gruppenIds()
    local lp = xml:getInt(wurzel .. "#letztePeriode", 0)
    if lp ~= nil and lp > 0 then
        AOBericht.letztePeriode = lp
    end

    local i = 0
    while true do
        local fk = string.format("%s.farm(%d)", wurzel, i)
        local id = xml:getInt(fk .. "#id", nil)
        if id == nil then
            break
        end
        AOBericht.daten[id] = {
            erfasstAb        = xml:getInt(fk .. "#erfasstAb", 1),
            vorjahrErfasstAb = xml:getInt(fk .. "#vorjahrErfasstAb", 1),
            hatVorjahr       = xml:getBool(fk .. "#hatVorjahr", false),
            jahr             = leseMonate(xml, fk .. ".jahr",         ids),
            vorjahr          = leseMonate(xml, fk .. ".vorjahr",      ids),
            stand            = leseMonate(xml, fk .. ".stand",        AOBericht.STAND),
            vorjahrStand     = leseMonate(xml, fk .. ".vorjahrStand", AOBericht.STAND),
        }
        i = i + 1
    end
    xml:delete()
end

function AOBericht:loadMap(name)
    if not AgrarOekonomie.istServer() then
        return
    end

    AOBericht.laden()

    -- Beim Laden keinen Jahreswechsel aus der gespeicherten Periode ableiten,
    -- zwischen Speichern und Laden vergeht ja keine Spielzeit.
    local p = AOBericht.aktuellePeriode()
    AOBericht.letztePeriode = p

    if not AOBericht.abonniert and g_messageCenter ~= nil and MessageType ~= nil
            and MessageType.PERIOD_CHANGED ~= nil then
        g_messageCenter:subscribe(MessageType.PERIOD_CHANGED,
            AOBericht.onPeriodeGewechselt, AOBericht)
        AOBericht.abonniert = true
    end

    if not AOBericht.speicherHook and FSCareerMissionInfo ~= nil
            and FSCareerMissionInfo.saveToXMLFile ~= nil then
        FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
            FSCareerMissionInfo.saveToXMLFile,
            function() AOBericht.speichern() end)
        AOBericht.speicherHook = true
    end

    Logging.info(AOBericht.LOG .. "Betriebsuebersicht bereit (%d Farm(en) aus dem Spielstand, Monat %d).",
        (function() local n = 0 for _ in pairs(AOBericht.daten) do n = n + 1 end return n end)(), p)
end

-- Fehlenden Monatsstand erst hier nachtragen, bei loadMap sind noch nicht alle Fahrzeuge da.
function AOBericht:update(dt)
    if AOBericht.standNachgetragen or not AgrarOekonomie.istServer() then
        return
    end
    if g_currentMission == nil or g_currentMission.isMissionStarted == false then
        return
    end
    AOBericht.standNachgetragen = true
    AOBericht.standFesthalten(AOBericht.aktuellePeriode(), true)
end

function AOBericht:deleteMap()
    if AOBericht.abonniert and g_messageCenter ~= nil and g_messageCenter.unsubscribeAll ~= nil then
        g_messageCenter:unsubscribeAll(AOBericht)
    end
    AOBericht.abonniert         = false
    AOBericht.standNachgetragen = false
    AOBericht.daten             = {}
    AOBericht.letztePeriode     = nil
    AOBericht.paket             = nil
end

addModEventListener(AOBericht)
