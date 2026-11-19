-- AOKassenbuch.lua
-- Schreibt die Geldbewegungen des Hofes in eine Datei im Spielstand-Ordner,
-- damit man auch ausserhalb des Spiels nachlesen kann, wofuer Geld geflossen
-- ist. Posten, die im Sekundentakt buchen, stehen als Tagessumme drin.
-- Gefuehrt wird eine XML, daneben entsteht dieselbe Liste als CSV fuer die
-- Tabellenkalkulation. Geschrieben wird nur auf dem Server.
-- OGW

AOKassenbuch = {}

AOKassenbuch.LOG = "[AgrarOekonomie] "

-- Diese Kategorien buchen beim Fahren und Arbeiten laufend. Einzeln waeren das
-- tausende Zeilen pro Spielstunde, deshalb nur eine Summe pro Spieltag.
AOKassenbuch.DAUERPOSTEN = {
    purchaseFuel        = true,
    purchaseSeeds       = true,
    purchaseFertilizer  = true,
    purchaseSaplings    = true,
    purchaseWater       = true,
    -- stuendlich, PlaceableIncomePerHour:onHourChanged
    propertyIncome      = true,
    vehicleRunningCost  = true,
    vehicleLeasingCost  = true,
    propertyMaintenance = true,
    productionCosts     = true,
}

-- Die Steuern der Mod bekommen eine eigene Zeile. Sie laufen ueber dieselben
-- Kategorien wie die laufenden Kosten und waeren sonst in deren Tagessumme
-- nicht mehr zu erkennen. Schluessel ist die Quelle aus vormerken().
AOKassenbuch.EIGENE = {
    Fuhrparksteuer = "fleetTax",
    Grundsteuer    = "propertyTax",
}
AOKassenbuch.KATEGORIE_TEXT = {
    fleetTax    = "ao_sec_fuhrpark",
    propertyTax = "ao_sec_grundsteuer",
}

AOKassenbuch.KOPFZEILE  = "Jahr;Monat;Tag;Zeit;Hof;Gruppe;Kategorie;Text;Betrag;Kontostand;Art"
AOKassenbuch.MAX_LETZTE = 12
-- Behalten werden das laufende und das vorige Spieljahr. Die Obergrenze
-- bleibt trotzdem, auf einem Server mit vielen Hoefen wird die Datei sonst
-- zu gross, um sie jede Minute neu zu schreiben.
AOKassenbuch.MAX_ZEILEN = 2000
AOKassenbuch.TAKT_MS    = 2000
-- Die Datei wird komplett neu geschrieben, deshalb nicht bei jeder Buchung
AOKassenbuch.SCHREIB_MS = 60000

AOKassenbuch.zeilen       = {}
AOKassenbuch.tagessummen  = {}
-- [farmId][jahr * 100 + monat] = { [gruppe] = betrag }. Anders als die Zeilen
-- wird hier nie etwas wegen der Obergrenze gestrichen.
AOKassenbuch.monate       = {}
AOKassenbuch.letzterTag   = nil
AOKassenbuch.letztesJahr  = nil
-- Quelle der Steuer, die gerade abgebucht wird (setzt AgrarOekonomie.verteile)
AOKassenbuch.quelle       = nil
AOKassenbuch.csvGeht      = false
AOKassenbuch.schmutzig    = false
AOKassenbuch.seitSchreiben = 0
AOKassenbuch.bereit       = false
AOKassenbuch.speicherHook = false
AOKassenbuch.takt         = 0

-- Zuletzt erhaltenes Paket (Client) bzw. zuletzt berechnetes (Einzelspieler)
AOKassenbuch.paket        = nil

local function umgebung()
    if g_currentMission == nil then
        return nil
    end
    return g_currentMission.environment
end

function AOKassenbuch.ordner()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    -- nicht cachen, der Ordner entsteht erst beim ersten Speichern
    return g_currentMission.missionInfo.savegameDirectory
end

-- Solange der Spielstand nie gespeichert wurde, gibt es den Ordner nicht.
function AOKassenbuch.ordnerDa()
    local dir = AOKassenbuch.ordner()
    if dir == nil then
        return nil
    end
    if fileExists ~= nil and not fileExists(dir .. "/farms.xml") then
        return nil
    end
    return dir
end

-- Beim Speichern gibt es den Ordner mit Sicherheit; dann wird die Pruefung
-- uebersprungen, damit sie nicht aus Versehen alles verhindert.
function AOKassenbuch.pfad(endung, ohnePruefung)
    local dir = nil
    if ohnePruefung == true then
        dir = AOKassenbuch.ordner()
    else
        dir = AOKassenbuch.ordnerDa()
    end
    if dir == nil then
        return nil
    end
    return dir .. "/FS25_FarmEconomy_Kassenbuch." .. endung
end

-- Das Spiel fuehrt kein Spieljahr; es ergibt sich aus dem fortlaufenden Tag
-- und der Monatslaenge. Ohne Jahr liegen Monat 7 aus zwei Jahren uebereinander.
function AOKassenbuch.zeitstempel()
    local e = umgebung()
    local jahr, monat, tag, stunde, minute = 1, 1, 0, 0, 0
    if e ~= nil then
        if type(e.currentPeriod) == "number" then
            monat = math.floor(e.currentPeriod)
        end
        if type(e.currentHour) == "number" then
            stunde = math.floor(e.currentHour)
        end
        if type(e.currentMinute) == "number" then
            minute = math.floor(e.currentMinute)
        end
        if e.getDayInPeriodFromDay ~= nil and type(e.currentMonotonicDay) == "number" then
            local d = e:getDayInPeriodFromDay(e.currentMonotonicDay)
            if type(d) == "number" then
                tag = math.floor(d)
            end
        end
        if type(e.currentYear) == "number" then
            jahr = math.floor(e.currentYear)
        elseif type(e.currentMonotonicDay) == "number" and type(e.daysPerPeriod) == "number"
                and e.daysPerPeriod > 0 then
            jahr = math.floor((e.currentMonotonicDay - 1) / (e.daysPerPeriod * 12)) + 1
        end
    end
    return jahr, monat, tag, string.format("%02d:%02d", stunde, minute)
end

function AOKassenbuch.kontostand(farmId)
    if g_farmManager == nil or g_farmManager.getFarmById == nil then
        return nil
    end
    local farm = g_farmManager:getFarmById(farmId)
    if type(farm) ~= "table" or farm.getBalance == nil then
        return nil
    end
    local wert = farm:getBalance()
    if type(wert) == "number" then
        return wert
    end
    return nil
end

-- Klartext zur Gruppe, in der Sprache des Servers.
function AOKassenbuch.gruppeText(gruppe)
    local schluessel = "ao_buch_kredit"
    if gruppe ~= "kredit" and AOBericht ~= nil and AOBericht.GRUPPEN ~= nil then
        for _, g in ipairs(AOBericht.GRUPPEN) do
            if g.id == gruppe then
                schluessel = g.label
                break
            end
        end
    end
    if AOSettingsPage ~= nil and AOSettingsPage.getText ~= nil then
        return AOSettingsPage.getText(schluessel)
    end
    return gruppe
end

function AOKassenbuch.zeilenText(kategorie, gruppe)
    local schluessel = AOKassenbuch.KATEGORIE_TEXT[kategorie]
    if schluessel ~= nil and AOSettingsPage ~= nil and AOSettingsPage.getText ~= nil then
        return AOSettingsPage.getText(schluessel)
    end
    return AOKassenbuch.gruppeText(gruppe)
end

function AOKassenbuch.gruppeFuer(moneyType, betrag)
    if AOBericht == nil or AOBericht.gruppeFuer == nil then
        return betrag >= 0 and "sonstEin" or "sonstAus"
    end
    -- Kredit ist fuer den Jahresvergleich keine Einnahme, im Kassenbuch aber
    -- eine Bewegung auf dem Konto und gehoert deshalb mit hinein.
    local gruppe = AOBericht.gruppeFuer(moneyType, betrag)
    if gruppe == nil then
        return "kredit"
    end
    return gruppe
end

-- Zeilen --------------------------------------------------------------------

function AOKassenbuch.neueZeile(farmId, kategorie, gruppe, betrag, jahr, monat, tag, zeit, istSumme)
    -- Zu einer Tagessumme passt kein Kontostand, die Buchungen liegen ueber
    -- den ganzen Tag verteilt.
    local konto = nil
    if istSumme ~= true then
        konto = AOKassenbuch.kontostand(farmId)
    end

    table.insert(AOKassenbuch.zeilen, {
        farmId    = farmId,
        jahr      = jahr,
        monat     = monat,
        tag       = tag,
        zeit      = zeit,
        gruppe    = gruppe,
        kategorie = kategorie,
        text      = AOKassenbuch.zeilenText(kategorie, gruppe),
        betrag    = betrag,
        konto     = konto,
        summe     = istSumme == true,
    })
    AOKassenbuch.monatAddieren(farmId, jahr, monat, gruppe, betrag)

    while #AOKassenbuch.zeilen > AOKassenbuch.MAX_ZEILEN do
        table.remove(AOKassenbuch.zeilen, 1)
    end
    AOKassenbuch.schmutzig = true
end

function AOKassenbuch.monatAddieren(farmId, jahr, monat, gruppe, betrag)
    local hof = AOKassenbuch.monate[farmId]
    if hof == nil then
        hof = {}
        AOKassenbuch.monate[farmId] = hof
    end
    local schluessel = (jahr or 1) * 100 + (monat or 1)
    local werte = hof[schluessel]
    if werte == nil then
        werte = {}
        hof[schluessel] = werte
    end
    werte[gruppe] = (werte[gruppe] or 0) + betrag
end

-- Alles vor dem vorigen Spieljahr fliegt raus, Zeilen wie Monatssummen.
function AOKassenbuch.aufraeumen(jahr)
    local grenze = (jahr - 1) * 100
    for _, hof in pairs(AOKassenbuch.monate) do
        for schluessel in pairs(hof) do
            if schluessel < grenze then
                hof[schluessel] = nil
            end
        end
    end

    local behalten = {}
    for _, z in ipairs(AOKassenbuch.zeilen) do
        if (z.jahr or 1) >= jahr - 1 then
            table.insert(behalten, z)
        end
    end
    if #behalten ~= #AOKassenbuch.zeilen then
        AOKassenbuch.zeilen = behalten
        AOKassenbuch.schmutzig = true
    end
end

function AOKassenbuch.sammle(farmId, kategorie, gruppe, betrag)
    local jahr, monat, tag = AOKassenbuch.zeitstempel()
    local hof = AOKassenbuch.tagessummen[farmId]
    if hof == nil then
        hof = {}
        AOKassenbuch.tagessummen[farmId] = hof
    end
    local eintrag = hof[kategorie]
    if eintrag == nil then
        eintrag = { gruppe = gruppe, betrag = 0, jahr = jahr, monat = monat, tag = tag }
        hof[kategorie] = eintrag
    end
    eintrag.betrag = eintrag.betrag + betrag
end

-- Tagessummen des abgelaufenen Tages als Zeilen ablegen.
function AOKassenbuch.summenAbschliessen()
    local _, _, _, zeit = AOKassenbuch.zeitstempel()
    for farmId, hof in pairs(AOKassenbuch.tagessummen) do
        for kategorie, eintrag in pairs(hof) do
            if eintrag.betrag ~= 0 then
                AOKassenbuch.neueZeile(farmId, kategorie, eintrag.gruppe, eintrag.betrag,
                    eintrag.jahr, eintrag.monat, eintrag.tag, zeit, true)
            end
        end
    end
    AOKassenbuch.tagessummen = {}
end

function AOKassenbuch.tagPruefen()
    local tag = AgrarOekonomie.getTag()
    if AOKassenbuch.letzterTag == nil then
        AOKassenbuch.letzterTag = tag
        return
    end
    if tag == AOKassenbuch.letzterTag then
        return
    end
    AOKassenbuch.letzterTag = tag
    AOKassenbuch.summenAbschliessen()

    local jahr = AOKassenbuch.zeitstempel()
    if jahr ~= AOKassenbuch.letztesJahr then
        AOKassenbuch.letztesJahr = jahr
        AOKassenbuch.aufraeumen(jahr)
    end
    AOKassenbuch.schreiben()
end

-- Aufgerufen vom Geld-Hook in AgrarOekonomie.lua, mit dem Betrag, der wirklich
-- auf dem Konto landet.
function AOKassenbuch.buche(farmId, moneyType, betrag)
    if not AOKassenbuch.bereit or AgrarOekonomie.CFG.buchAktiv ~= true then
        return
    end
    if betrag == nil or betrag == 0 or not AgrarOekonomie.istSpielerFarm(farmId) then
        return
    end

    AOKassenbuch.tagPruefen()

    local kategorie = AgrarOekonomie.getStatistik(moneyType) or "other"
    local gruppe    = AOKassenbuch.gruppeFuer(moneyType, betrag)
    local schwelle  = math.max(0, AgrarOekonomie.CFG.buchSchwelle or 0)

    local eigene = AOKassenbuch.EIGENE[AOKassenbuch.quelle or ""]
    if eigene ~= nil then
        kategorie = eigene
    elseif AOKassenbuch.DAUERPOSTEN[kategorie] == true or math.abs(betrag) < schwelle then
        AOKassenbuch.sammle(farmId, kategorie, gruppe, betrag)
        return
    end

    local jahr, monat, tag, zeit = AOKassenbuch.zeitstempel()
    AOKassenbuch.neueZeile(farmId, kategorie, gruppe, betrag, jahr, monat, tag, zeit, false)
end

-- Datei ---------------------------------------------------------------------

local function zahl(wert)
    if wert == nil then
        return ""
    end
    -- Komma als Dezimaltrennzeichen, damit die Tabelle direkt rechnet
    return (string.gsub(string.format("%.2f", wert), "%.", ","))
end

function AOKassenbuch.csvZeile(z)
    local felder = {
        tostring(z.jahr), tostring(z.monat), tostring(z.tag), z.zeit, tostring(z.farmId),
        z.gruppe, z.kategorie, z.text, zahl(z.betrag), zahl(z.konto),
        z.summe and "Tagessumme" or "Buchung",
    }
    return table.concat(felder, ";")
end

-- FS25 laesst bei io.open nur den Modus "w" zu (Logzeile "only write mode").
-- Angehaengt werden kann also nicht, die Datei wird jedes Mal komplett neu
-- geschrieben. Der bestaendige Teil ist deshalb die XML, die CSV ist nur die
-- Ausgabe fuer die Tabellenkalkulation.
function AOKassenbuch.csvSchreiben(ohnePruefung)
    if type(io) ~= "table" or type(io.open) ~= "function" then
        return false
    end
    local pfad = AOKassenbuch.pfad("csv", ohnePruefung)
    if pfad == nil then
        return false
    end

    local datei = io.open(pfad, "w")
    if datei == nil then
        return false
    end

    local teile = { AOKassenbuch.KOPFZEILE }
    for _, z in ipairs(AOKassenbuch.zeilen) do
        table.insert(teile, AOKassenbuch.csvZeile(z))
    end
    datei:write(table.concat(teile, "\n") .. "\n")
    datei:close()
    return true
end

function AOKassenbuch.xmlSchreiben(ohnePruefung)
    local pfad = AOKassenbuch.pfad("xml", ohnePruefung)
    if pfad == nil or XMLFile == nil then
        return false
    end

    local wurzel = "farmEconomyKassenbuch"
    local xml    = XMLFile.create("aoKassenbuchXML", pfad, wurzel)
    if xml == nil then
        return false
    end

    local i = 0
    for _, z in ipairs(AOKassenbuch.zeilen) do
        local k = string.format("%s.buchung(%d)", wurzel, i)
        xml:setInt(k .. "#hof", z.farmId or 1)
        xml:setInt(k .. "#jahr", z.jahr or 1)
        xml:setInt(k .. "#monat", z.monat or 1)
        xml:setInt(k .. "#tag", z.tag or 0)
        xml:setString(k .. "#zeit", z.zeit or "")
        xml:setString(k .. "#gruppe", z.gruppe or "")
        xml:setString(k .. "#kategorie", z.kategorie or "")
        xml:setString(k .. "#text", z.text or "")
        xml:setFloat(k .. "#betrag", z.betrag or 0)
        if z.konto ~= nil then
            xml:setFloat(k .. "#kontostand", z.konto)
        end
        if z.summe then
            xml:setBool(k .. "#tagessumme", true)
        end
        i = i + 1
    end

    local m = 0
    for farmId, hof in pairs(AOKassenbuch.monate) do
        for schluessel, werte in pairs(hof) do
            local k = string.format("%s.monat(%d)", wurzel, m)
            xml:setInt(k .. "#hof", farmId)
            xml:setInt(k .. "#jahr", math.floor(schluessel / 100))
            xml:setInt(k .. "#monat", schluessel % 100)
            local n = 0
            for gruppe, betrag in pairs(werte) do
                local kw = string.format("%s.wert(%d)", k, n)
                xml:setString(kw .. "#gruppe", gruppe)
                xml:setFloat(kw .. "#betrag", betrag)
                n = n + 1
            end
            m = m + 1
        end
    end

    xml:save()
    xml:delete()
    return true
end

function AOKassenbuch.hofText()
    local hoefe = {}
    for _, z in ipairs(AOKassenbuch.zeilen) do
        hoefe[z.farmId] = true
    end
    local liste = {}
    for id in pairs(hoefe) do
        table.insert(liste, id)
    end
    table.sort(liste)
    local namen = {}
    for _, id in ipairs(liste) do
        local name = nil
        if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
            local farm = g_farmManager:getFarmById(id)
            if type(farm) == "table" and type(farm.name) == "string" and farm.name ~= "" then
                name = farm.name
            end
        end
        table.insert(namen, name or tostring(id))
    end
    return table.concat(namen, ", ")
end

function AOKassenbuch.schreiben(ohnePruefung)
    if not AgrarOekonomie.istServer() then
        return
    end
    AOKassenbuch.xmlSchreiben(ohnePruefung)
    AOKassenbuch.csvGeht = AOKassenbuch.csvSchreiben(ohnePruefung)
    if AOKassenbuchSeite ~= nil and AOKassenbuchSeite.schreiben ~= nil then
        AOKassenbuchSeite.schreiben(AOKassenbuch.zeilen,
            AOKassenbuch.pfad("html", ohnePruefung), AOKassenbuch.hofText())
    end
    AOKassenbuch.schmutzig = false
    AOKassenbuch.seitSchreiben = 0
end

function AOKassenbuch.laden()
    AOKassenbuch.zeilen = {}
    AOKassenbuch.monate = {}

    local pfad = AOKassenbuch.pfad("xml")
    if pfad == nil or XMLFile == nil or XMLFile.loadIfExists == nil then
        return
    end
    local xml = XMLFile.loadIfExists("aoKassenbuchXML", pfad)
    if xml == nil then
        return
    end

    local wurzel = "farmEconomyKassenbuch"
    local i = 0
    while true do
        local k      = string.format("%s.buchung(%d)", wurzel, i)
        local betrag = xml:getFloat(k .. "#betrag", nil)
        if betrag == nil then
            break
        end
        table.insert(AOKassenbuch.zeilen, {
            farmId    = xml:getInt(k .. "#hof", 1),
            jahr      = xml:getInt(k .. "#jahr", 1),
            monat     = xml:getInt(k .. "#monat", 1),
            tag       = xml:getInt(k .. "#tag", 0),
            zeit      = xml:getString(k .. "#zeit", ""),
            gruppe    = xml:getString(k .. "#gruppe", ""),
            kategorie = xml:getString(k .. "#kategorie", ""),
            text      = xml:getString(k .. "#text", ""),
            betrag    = betrag,
            konto     = xml:getFloat(k .. "#kontostand", nil),
            summe     = xml:getBool(k .. "#tagessumme", false),
        })
        i = i + 1
    end

    local m = 0
    while true do
        local k    = string.format("%s.monat(%d)", wurzel, m)
        local jahr = xml:getInt(k .. "#jahr", nil)
        if jahr == nil then
            break
        end
        local farmId = xml:getInt(k .. "#hof", 1)
        local monat  = xml:getInt(k .. "#monat", 1)
        local n = 0
        while true do
            local kw     = string.format("%s.wert(%d)", k, n)
            local gruppe = xml:getString(kw .. "#gruppe", nil)
            if gruppe == nil then
                break
            end
            AOKassenbuch.monatAddieren(farmId, jahr, monat, gruppe, xml:getFloat(kw .. "#betrag", 0))
            n = n + 1
        end
        m = m + 1
    end
    xml:delete()

    -- Aeltere Kassenbuecher haben nur Zeilen, die Summen werden einmal daraus
    -- nachgerechnet.
    if m == 0 then
        for _, z in ipairs(AOKassenbuch.zeilen) do
            AOKassenbuch.monatAddieren(z.farmId, z.jahr, z.monat, z.gruppe, z.betrag)
        end
    end
end

function AOKassenbuch.speichern()
    AOKassenbuch.summenAbschliessen()
    -- letzte Gelegenheit vor dem Beenden, deshalb ohne Ordner-Pruefung
    AOKassenbuch.schreiben(true)
end

-- Paket fuer die Anzeige ----------------------------------------------------

-- Reihenfolge der Gruppen im Netzwerk-Paket: die des Jahresvergleichs,
-- dahinter der Kredit. Beide Seiten muessen dieselbe Liste haben.
function AOKassenbuch.gruppenIds()
    if AOKassenbuch.gruppenIdsCache ~= nil then
        return AOKassenbuch.gruppenIdsCache
    end
    local ids = {}
    if AOBericht ~= nil and AOBericht.GRUPPEN ~= nil then
        for _, g in ipairs(AOBericht.GRUPPEN) do
            table.insert(ids, g.id)
        end
    end
    table.insert(ids, "kredit")
    AOKassenbuch.gruppenIdsCache = ids
    return ids
end

function AOKassenbuch.gruppenIndex(id)
    for i, g in ipairs(AOKassenbuch.gruppenIds()) do
        if g == id then
            return i
        end
    end
    return nil
end

-- Nur Server: alle Monatssummen des Hofes und je Monat die juengsten
-- Buchungen. Damit kann das Fenster blaettern, ohne neu zu fragen.
function AOKassenbuch.erstellePaket(farmId)
    local ids = AOKassenbuch.gruppenIds()
    local jahr, monat = AOKassenbuch.zeitstempel()
    local paket = { jahr = jahr, monat = monat, monate = {} }

    local proSchluessel = {}
    local function eintrag(schluessel)
        local m = proSchluessel[schluessel]
        if m == nil then
            m = { jahr = math.floor(schluessel / 100), monat = schluessel % 100, werte = {}, letzte = {} }
            for i = 1, #ids do
                m.werte[i] = 0
            end
            proSchluessel[schluessel] = m
            table.insert(paket.monate, m)
        end
        return m
    end
    local function addiere(m, gruppe, betrag)
        local i = AOKassenbuch.gruppenIndex(gruppe)
        if i ~= nil then
            m.werte[i] = m.werte[i] + betrag
        end
    end

    -- den laufenden Monat gibt es immer, auch ohne Buchung
    eintrag(jahr * 100 + monat)
    for schluessel, werte in pairs(AOKassenbuch.monate[farmId] or {}) do
        local m = eintrag(schluessel)
        for gruppe, betrag in pairs(werte) do
            addiere(m, gruppe, betrag)
        end
    end
    -- der laufende Tag steht noch nicht in den Monatssummen
    for _, e in pairs(AOKassenbuch.tagessummen[farmId] or {}) do
        addiere(eintrag((e.jahr or 1) * 100 + (e.monat or 1)), e.gruppe, e.betrag)
    end

    for i = #AOKassenbuch.zeilen, 1, -1 do
        local z = AOKassenbuch.zeilen[i]
        if z.farmId == farmId then
            local m = proSchluessel[(z.jahr or 1) * 100 + (z.monat or 1)]
            if m ~= nil and #m.letzte < AOKassenbuch.MAX_LETZTE then
                local kategorie = ""
                if AOKassenbuch.KATEGORIE_TEXT[z.kategorie] ~= nil then
                    kategorie = z.kategorie
                end
                table.insert(m.letzte, {
                    zeit      = z.zeit or "",
                    gruppe    = AOKassenbuch.gruppenIndex(z.gruppe) or 0,
                    betrag    = z.betrag or 0,
                    summe     = z.summe == true,
                    kategorie = kategorie,
                })
            end
        end
    end

    -- neuester Monat zuerst
    table.sort(paket.monate, function(a, b)
        return a.jahr * 100 + a.monat > b.jahr * 100 + b.monat
    end)
    return paket
end

-- Vom Fenster aufgerufen: eigenes Paket holen. Server rechnet sofort,
-- Client fragt beim Server an; die Antwort ruft empfange().
function AOKassenbuch.anfordern()
    local farmId = nil
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        farmId = g_currentMission:getFarmId()
    end
    if type(farmId) ~= "number" or farmId < 1 then
        return
    end

    if AgrarOekonomie.istServer() then
        AOKassenbuch.paket = AOKassenbuch.erstellePaket(farmId)
        return
    end

    if g_client ~= nil and g_client.getServerConnection ~= nil and AOKassenbuchEvent ~= nil then
        local conn = g_client:getServerConnection()
        if conn ~= nil and conn.sendEvent ~= nil then
            conn:sendEvent(AOKassenbuchEvent.new(true, farmId, nil))
        end
    end
end

function AOKassenbuch.empfange(farmId, paket)
    AOKassenbuch.paket = paket
    if AOKassenbuchDialog ~= nil and AOKassenbuchDialog.aktualisiereOffenes ~= nil then
        AOKassenbuchDialog.aktualisiereOffenes()
    end
end

-- Konsole -------------------------------------------------------------------

-- Auch auf dem Client angemeldet: dort schreibt das Kassenbuch nichts, aber
-- "Command not found" waere die unverstaendlichste Antwort darauf.
function AOKassenbuch.befehlStatus(_)
    if not AgrarOekonomie.istServer() then
        return AOKassenbuch.LOG ..
            "Kassenbuch: Geschrieben wird nur auf dem Server, in dessen Spielstand-Ordner. " ..
            "Am Client gibt es keine Datei."
    end

    AOKassenbuch.speichern()

    local offen = 0
    for _, hof in pairs(AOKassenbuch.tagessummen) do
        for _ in pairs(hof) do
            offen = offen + 1
        end
    end
    local monate = 0
    for _, hof in pairs(AOKassenbuch.monate) do
        for _ in pairs(hof) do
            monate = monate + 1
        end
    end

    local zeilen = {
        AOKassenbuch.LOG .. "Kassenbuch:",
        string.format("  aktiv=%s  Schwelle fuer Einzelzeilen=%s",
            tostring(AgrarOekonomie.CFG.buchAktiv),
            AgrarOekonomie.formatGeld(AgrarOekonomie.CFG.buchSchwelle or 0)),
        string.format("  Tabelle: %s%s", tostring(AOKassenbuch.pfad("csv", true)),
            AOKassenbuch.csvGeht and "" or "  (nicht schreibbar)"),
        string.format("  Bestand: %s", tostring(AOKassenbuch.pfad("xml", true))),
        string.format("  Seite:   %s", tostring(AOKassenbuch.pfad("html", true))),
        string.format("  Zeilen: %d  offene Tagesposten: %d  Monate: %d", #AOKassenbuch.zeilen, offen, monate),
    }
    return table.concat(zeilen, "\n")
end

-- Start ---------------------------------------------------------------------

function AOKassenbuch:loadMap(name)
    if addConsoleCommand ~= nil then
        addConsoleCommand("aoKassenbuch", "Schreibt das Kassenbuch und zeigt den Dateipfad.",
            "befehlStatus", AOKassenbuch)
    end

    if AOKassenbuchDialog ~= nil and g_dedicatedServerInfo == nil then
        AOKassenbuchDialog.installiereTastenHook()
        AOKassenbuchDialog.registriereTaste()
        if g_client ~= nil then
            AOKassenbuchDialog.laden()
        end
    end

    if not AgrarOekonomie.istServer() then
        Logging.info(AOKassenbuch.LOG .. "Kassenbuch: Client, es schreibt nur der Server.")
        return
    end

    AOKassenbuch.laden()
    AOKassenbuch.letzterTag  = AgrarOekonomie.getTag()
    AOKassenbuch.letztesJahr = AOKassenbuch.zeitstempel()
    AOKassenbuch.aufraeumen(AOKassenbuch.letztesJahr)

    if not AOKassenbuch.speicherHook and FSCareerMissionInfo ~= nil
            and FSCareerMissionInfo.saveToXMLFile ~= nil then
        FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
            FSCareerMissionInfo.saveToXMLFile,
            function() AOKassenbuch.speichern() end)
        AOKassenbuch.speicherHook = true
    end

    AOKassenbuch.bereit = true
    Logging.info(AOKassenbuch.LOG .. "Kassenbuch bereit (aktiv=%s, %d Buchungen aus dem Spielstand, Datei %s).",
        tostring(AgrarOekonomie.CFG.buchAktiv), #AOKassenbuch.zeilen,
        tostring(AOKassenbuch.pfad("csv", true)))
end

-- Der Tageswechsel kann auch ohne Buchung kommen, deshalb der eigene Takt.
function AOKassenbuch:update(dt)
    if not AOKassenbuch.bereit then
        return
    end
    AOKassenbuch.takt = AOKassenbuch.takt + dt
    if AOKassenbuch.takt < AOKassenbuch.TAKT_MS then
        return
    end
    AOKassenbuch.takt = 0
    AOKassenbuch.tagPruefen()

    -- neue Buchungen sollen nicht bis zum naechsten Speichern warten
    AOKassenbuch.seitSchreiben = AOKassenbuch.seitSchreiben + AOKassenbuch.TAKT_MS
    if AOKassenbuch.schmutzig and AOKassenbuch.seitSchreiben >= AOKassenbuch.SCHREIB_MS then
        AOKassenbuch.schreiben()
    end
end

function AOKassenbuch:deleteMap()
    AOKassenbuch.bereit      = false
    AOKassenbuch.zeilen      = {}
    AOKassenbuch.tagessummen = {}
    AOKassenbuch.monate      = {}
    AOKassenbuch.letzterTag  = nil
    AOKassenbuch.letztesJahr = nil
    AOKassenbuch.quelle      = nil
    AOKassenbuch.takt        = 0
    AOKassenbuch.schmutzig   = false
    AOKassenbuch.seitSchreiben = 0
end

addModEventListener(AOKassenbuch)
