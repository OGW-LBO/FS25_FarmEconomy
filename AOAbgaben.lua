-- AOAbgaben.lua
-- Zahlen fuer die Seite "Abgaben und Helfer" im Hof-PC: was naechsten Monat
-- faellig wird, was dieses und voriges Jahr bezahlt wurde, und wie die
-- Bremse gerade steht. Gerechnet wird auf dem Server.
-- OGW

AOAbgaben = {}

AOAbgaben.FELDER = {
    "fsAktiv", "fsJaehrlich", "fsAnzahl", "fsRuhend", "fsDach", "fsNaechste", "fsMonateBis",
    "fsJahr", "fsVorjahr",
    "gsAktiv", "gsWert", "gsHa", "gsSatz", "gsNaechste", "gsJahr", "gsVorjahr",
    "ziAktiv", "ziBasis", "ziSatz", "ziNaechste", "ziLetzte", "ziJahr", "ziVorjahr",
    "krKredit", "krJahr", "krVorjahr",
    "hlAktiv", "hlModus", "hlStufe", "hlFaktor", "hlFest", "hlZufall", "hlEinsatz", "hlGratis",
    "hlMonat", "hlJahr", "hlVorjahr",
    "brAktiv", "brAnteil", "brSchnitt", "brHeute", "brNotKonto", "brGeld",
    "kpTag", "kpGewollt", "kpEcht", "kpGrund", "tag", "karenz",
}

AOAbgaben.paket = nil

local function zahl(wert)
    return tonumber(wert) or 0
end

local function janein(wert)
    return wert == true and 1 or 0
end

local function zeilenSumme(farmId, kategorie, jahr)
    local summe = 0
    if AOKassenbuch == nil then
        return summe
    end
    for _, z in ipairs(AOKassenbuch.zeilen or {}) do
        if z.farmId == farmId and z.kategorie == kategorie and z.jahr == jahr then
            summe = summe + zahl(z.betrag)
        end
    end
    for k, e in pairs((AOKassenbuch.tagessummen or {})[farmId] or {}) do
        if k == kategorie and e.jahr == jahr then
            summe = summe + zahl(e.betrag)
        end
    end
    return math.abs(summe)
end

local function gruppenSumme(farmId, gruppe, jahr, monat)
    local summe = 0
    if AOKassenbuch == nil then
        return summe
    end
    for schluessel, werte in pairs((AOKassenbuch.monate or {})[farmId] or {}) do
        if math.floor(schluessel / 100) == jahr and (monat == nil or schluessel % 100 == monat) then
            summe = summe + zahl(werte[gruppe])
        end
    end
    for _, e in pairs((AOKassenbuch.tagessummen or {})[farmId] or {}) do
        if e.gruppe == gruppe and e.jahr == jahr and (monat == nil or e.monat == monat) then
            summe = summe + zahl(e.betrag)
        end
    end
    return math.abs(summe)
end

local function helferFaktor(cfg)
    local stufe = math.floor(zahl(cfg.lohnStufe))
    if stufe == 0 then
        return zahl(cfg.faktorAzubi)
    elseif stufe == 2 then
        return zahl(cfg.faktorAusgelernt)
    elseif stufe == 3 then
        return zahl(cfg.faktorEigen)
    end
    return zahl(cfg.faktorQuer)
end

function AOAbgaben.erstellePaket(farmId)
    local p = {}
    for _, feld in ipairs(AOAbgaben.FELDER) do
        p[feld] = 0
    end
    local cfg = AgrarOekonomie.CFG
    local jahr, monat = 1, 1
    if AOKassenbuch ~= nil and AOKassenbuch.zeitstempel ~= nil then
        jahr, monat = AOKassenbuch.zeitstempel()
    end

    local geld, kredit = 0, 0
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if type(farm) == "table" then
            geld   = zahl(farm.money)
            kredit = zahl(farm.loan)
        end
    end

    if FuhrparkSteuer ~= nil and FuhrparkSteuer.CFG ~= nil then
        local fcfg = FuhrparkSteuer.CFG
        p.fsAktiv     = janein(fcfg.enabled)
        p.fsJaehrlich = zahl(fcfg.billingMode) == 1 and 1 or 0
        local monate = p.fsJaehrlich == 1 and 12 or 1
        if FuhrparkSteuer.berechne ~= nil then
            local daten = FuhrparkSteuer.berechne(monate, false)[farmId]
            if daten ~= nil then
                p.fsAnzahl   = zahl(daten.anzahl)
                p.fsRuhend   = zahl(daten.ruhend)
                p.fsDach     = zahl(daten.unterDach)
                p.fsNaechste = zahl(daten.summe)
            end
        end
        if p.fsJaehrlich == 1 and FuhrparkSteuer.state ~= nil then
            p.fsMonateBis = math.max(1, 12 - zahl(FuhrparkSteuer.state.monateSeitJahr))
        else
            p.fsMonateBis = 1
        end
        if p.fsAktiv == 0 then
            p.fsNaechste = 0
        end
    end
    p.fsJahr    = zeilenSumme(farmId, "fleetTax", jahr)
    p.fsVorjahr = zeilenSumme(farmId, "fleetTax", jahr - 1)

    p.gsAktiv = janein(cfg.grundsteuerAktiv)
    p.gsSatz  = zahl(cfg.grundsteuerProJahr)
    if AOGrundsteuer ~= nil and AOGrundsteuer.getLandwert ~= nil then
        local wert, _, ha = AOGrundsteuer.getLandwert(farmId)
        p.gsWert = zahl(wert)
        p.gsHa   = zahl(ha)
    end
    if p.gsAktiv == 1 then
        p.gsNaechste = p.gsWert * p.gsSatz / 12
    end
    p.gsJahr    = zeilenSumme(farmId, "propertyTax", jahr)
    p.gsVorjahr = zeilenSumme(farmId, "propertyTax", jahr - 1)

    p.ziAktiv = janein(cfg.zinsAktiv)
    p.ziSatz  = zahl(cfg.zinsSatz)
    if AOZins ~= nil and AOZins.berechne ~= nil then
        local zins, basis = AOZins.berechne(geld, kredit)
        p.ziBasis = math.max(0, zahl(basis))
        if p.ziAktiv == 1 then
            p.ziNaechste = zahl(zins)
        end
        local letzte = AOZins.letzte ~= nil and AOZins.letzte[farmId] or nil
        if letzte ~= nil then
            p.ziLetzte = zahl(letzte.zins)
        end
    end
    p.ziJahr    = zeilenSumme(farmId, "interestCredit", jahr)
    p.ziVorjahr = zeilenSumme(farmId, "interestCredit", jahr - 1)

    p.krKredit  = kredit
    p.krJahr    = gruppenSumme(farmId, "zinsen", jahr)
    p.krVorjahr = gruppenSumme(farmId, "zinsen", jahr - 1)

    if HelferLohn ~= nil and HelferLohn.CFG ~= nil then
        local hcfg = HelferLohn.CFG
        p.hlAktiv   = janein(hcfg.aktiv)
        p.hlModus   = zahl(hcfg.bezahlModus)
        p.hlStufe   = zahl(hcfg.lohnStufe)
        p.hlFaktor  = helferFaktor(hcfg)
        p.hlFest    = zahl(hcfg.festLohn)
        p.hlZufall  = janein(hcfg.zufallVerfuegbar)
        p.hlGratis  = janein(hcfg.gratisBetrieb)
        p.hlEinsatz = zahl((HelferLohn.activeAIByFarm or {})[farmId])
    end
    p.hlMonat   = gruppenSumme(farmId, "loehne", jahr, monat)
    p.hlJahr    = gruppenSumme(farmId, "loehne", jahr)
    p.hlVorjahr = gruppenSumme(farmId, "loehne", jahr - 1)

    p.brAktiv    = janein(cfg.bremseAktiv)
    p.brAnteil   = zahl(cfg.bremseAnteil)
    p.brNotKonto = zahl(cfg.notbremseKonto)
    p.brGeld     = geld
    p.karenz     = zahl(cfg.karenzMonate)
    p.tag        = zahl(AgrarOekonomie.getTag())
    if AgrarOekonomie.tageswechselPruefen ~= nil then
        AgrarOekonomie.tageswechselPruefen(farmId)
    end
    if AgrarOekonomie.getTagesEinnahmen ~= nil then
        p.brSchnitt = zahl(AgrarOekonomie.getTagesEinnahmen(farmId))
    end
    p.brHeute = zahl((AgrarOekonomie.abgebucht or {})[farmId])

    local kappung = (AgrarOekonomie.letzteKappung or {})[farmId]
    if kappung ~= nil then
        p.kpTag     = zahl(kappung.tag)
        p.kpGewollt = zahl(kappung.gewollt)
        p.kpEcht    = zahl(kappung.echt)
        p.kpGrund   = kappung.grund == "notbremse" and 2 or 1
    end
    return p
end

function AOAbgaben.anfordern()
    local farmId = nil
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        farmId = g_currentMission:getFarmId()
    end
    if type(farmId) ~= "number" or farmId < 1 then
        AOAbgaben.paket = nil
        return
    end
    if AgrarOekonomie.istServer() then
        AOAbgaben.paket = AOAbgaben.erstellePaket(farmId)
        return
    end
    if g_client ~= nil and g_client.getServerConnection ~= nil and AOAbgabenEvent ~= nil then
        local conn = g_client:getServerConnection()
        if conn ~= nil and conn.sendEvent ~= nil then
            conn:sendEvent(AOAbgabenEvent.new(true, farmId, nil))
        end
    end
end

function AOAbgaben.empfange(paket)
    AOAbgaben.paket = paket
    if AOHofPC ~= nil and AOHofPC.aktualisiereOffenes ~= nil then
        AOHofPC.aktualisiereOffenes()
    end
end
