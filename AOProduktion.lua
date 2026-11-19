-- AOProduktion.lua
-- Produktionsgeschwindigkeit fuer alle Produktionen, einzelne Gebaeude koennen
-- einen eigenen Faktor bekommen. Die Kosten laufen auf Wunsch mit.
-- OGW

AOProduktion = {}

AOProduktion.LOG = "[AgrarOekonomie] "

AOProduktion.ZYKLEN = { "cyclesPerMonth", "cyclesPerHour", "cyclesPerMinute" }
AOProduktion.KOSTEN = { "costsPerActiveMonth", "costsPerActiveHour", "costsPerActiveMinute" }

-- Auswahl je Gebaeude, 0 = wie alle
AOProduktion.EINZEL_WERTE = { 0, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 5, 8, 10 }

AOProduktion.MAX_ZEILEN = 30

AOProduktion.proUid     = {}   -- Server: [uniqueId] = Faktor
AOProduktion.proObjekt  = {}   -- Client: [placeable] = Faktor, gekaufte Gebaeude haben hier keine uniqueId
AOProduktion.bereit     = false
AOProduktion.takt       = 0
AOProduktion.TAKT_MS    = 2000

function AOProduktion.getManager()
    if g_currentMission == nil then
        return nil
    end
    return g_currentMission.productionChainManager
end

function AOProduktion.getPlaceable(pp)
    if type(pp) == "table" and type(pp.owningPlaceable) == "table" then
        return pp.owningPlaceable
    end
    return nil
end

function AOProduktion.getUid(placeable)
    if placeable ~= nil and placeable.getUniqueId ~= nil then
        return placeable:getUniqueId()
    end
    return nil
end

function AOProduktion.getName(pp)
    if pp.getName ~= nil then
        local n = pp:getName()
        if type(n) == "string" and n ~= "" then
            return n
        end
    end
    local pl = AOProduktion.getPlaceable(pp)
    if pl ~= nil and pl.getName ~= nil then
        local n = pl:getName()
        if type(n) == "string" and n ~= "" then
            return n
        end
    end
    return "?"
end

-- nil = kein eigener Wert
function AOProduktion.getEinzel(pp)
    local pl = AOProduktion.getPlaceable(pp)
    if pl == nil then
        return nil
    end
    if AgrarOekonomie.istServer() then
        local uid = AOProduktion.getUid(pl)
        if uid ~= nil then
            return AOProduktion.proUid[uid]
        end
        return nil
    end
    return AOProduktion.proObjekt[pl]
end

function AOProduktion.getFaktor(pp)
    local cfg = AgrarOekonomie.CFG
    if not cfg.prodAktiv then
        return 1
    end
    local einzel = AOProduktion.getEinzel(pp)
    if type(einzel) == "number" and einzel > 0 then
        return einzel
    end
    return math.max(0.05, tonumber(cfg.prodFaktor) or 1)
end

-- Produktionen der eigenen Farm, nach Name sortiert
function AOProduktion.getEigene()
    local liste = {}
    local pcm = AOProduktion.getManager()
    if pcm == nil or g_currentMission == nil then
        return liste
    end
    local farmId = g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    local punkte = nil
    if farmId ~= nil and pcm.getProductionPointsForFarmId ~= nil then
        punkte = pcm:getProductionPointsForFarmId(farmId)
    end
    if type(punkte) ~= "table" then
        return liste
    end
    for _, pp in pairs(punkte) do
        if type(pp) == "table" and AOProduktion.getPlaceable(pp) ~= nil then
            table.insert(liste, pp)
        end
    end
    table.sort(liste, function(a, b)
        return AOProduktion.getName(a) < AOProduktion.getName(b)
    end)
    return liste
end

-- Anwenden --------------------------------------------------------------------

local function merkeOriginal(prod)
    if prod.aoOrig ~= nil then
        return
    end
    local orig = {}
    for _, feld in ipairs(AOProduktion.ZYKLEN) do
        if type(prod[feld]) == "number" then
            orig[feld] = prod[feld]
        end
    end
    for _, feld in ipairs(AOProduktion.KOSTEN) do
        if type(prod[feld]) == "number" then
            orig[feld] = prod[feld]
        end
    end
    prod.aoOrig = orig
end

-- Zyklen und Kosten werden alle skaliert, weil nicht klar ist, welches Feld
-- das Spiel tatsaechlich liest.
local function setzeProduktion(prod, faktor, kostenFaktor)
    if prod.aoOrig == nil then
        if faktor == 1 and kostenFaktor == 1 then
            return      -- noch nie angefasst
        end
        merkeOriginal(prod)
    end
    for _, feld in ipairs(AOProduktion.ZYKLEN) do
        local o = prod.aoOrig[feld]
        if o ~= nil then
            prod[feld] = o * faktor
        end
    end
    for _, feld in ipairs(AOProduktion.KOSTEN) do
        local o = prod.aoOrig[feld]
        if o ~= nil then
            prod[feld] = o * kostenFaktor
        end
    end
end

-- Voll mit heisst gleiche Kosten je Stueck. Bei der Wurzel wird die schnelle
-- Produktion je Stueck billiger, aber nicht so stark wie ganz ohne (x4 -> x2).
function AOProduktion.kostenFaktor(f)
    local art = math.floor((tonumber(AgrarOekonomie.CFG.prodKosten) or 2) + 0.5)
    if art <= 0 then
        return 1
    elseif art == 1 then
        return math.sqrt(f)
    end
    return f
end

-- Auch auf Clients, sonst zeigt das Produktionsmenue die alten Werte.
function AOProduktion.anwenden()
    local pcm = AOProduktion.getManager()
    if pcm == nil or type(pcm.productionPoints) ~= "table" then
        return
    end
    for _, pp in pairs(pcm.productionPoints) do
        if type(pp) == "table" and type(pp.productions) == "table" then
            local f = AOProduktion.getFaktor(pp)
            local k = AOProduktion.kostenFaktor(f)
            for _, prod in pairs(pp.productions) do
                if type(prod) == "table" then
                    setzeProduktion(prod, f, k)
                end
            end
        end
    end
end

-- Einzelwerte -----------------------------------------------------------------

-- Server setzt direkt, der Client schickt eine Anfrage. 0 = wie alle.
function AOProduktion.setzeEinzel(pp, faktor)
    local pl = AOProduktion.getPlaceable(pp)
    if pl == nil then
        return
    end
    faktor = tonumber(faktor) or 0
    if AgrarOekonomie.istServer() then
        AOProduktion.setzeEinzelServer(pl, faktor)
    else
        AOProduktion.proObjekt[pl] = (faktor > 0) and faktor or nil
        if g_client ~= nil and AOProduktionEvent ~= nil then
            g_client:getServerConnection():sendEvent(AOProduktionEvent.newAenderung(pl, faktor))
        end
    end
    AOProduktion.anwenden()
end

function AOProduktion.setzeEinzelServer(placeable, faktor)
    local uid = AOProduktion.getUid(placeable)
    if uid == nil then
        return
    end
    AOProduktion.proUid[uid] = (faktor > 0) and faktor or nil
    AOProduktion.anwenden()
    AOProduktion.verteile()
end

-- nur Server
function AOProduktion.getListe()
    local liste = {}
    local pcm = AOProduktion.getManager()
    if pcm == nil or type(pcm.productionPoints) ~= "table" then
        return liste
    end
    for _, pp in pairs(pcm.productionPoints) do
        local pl  = AOProduktion.getPlaceable(pp)
        local uid = AOProduktion.getUid(pl)
        local f   = uid ~= nil and AOProduktion.proUid[uid] or nil
        if pl ~= nil and f ~= nil then
            table.insert(liste, { placeable = pl, faktor = f })
        end
    end
    return liste
end

function AOProduktion.uebernehmeListe(liste)
    AOProduktion.proObjekt = {}
    for _, e in ipairs(liste) do
        if e.placeable ~= nil and type(e.faktor) == "number" and e.faktor > 0 then
            AOProduktion.proObjekt[e.placeable] = e.faktor
        end
    end
    AOProduktion.anwenden()
end

function AOProduktion.verteile()
    if not AgrarOekonomie.istServer() or AOProduktionEvent == nil then
        return
    end
    if g_server ~= nil and g_server.broadcastEvent ~= nil then
        g_server:broadcastEvent(AOProduktionEvent.newListe(), false)
    end
end

-- Spielstand (nur Server) -----------------------------------------------------

function AOProduktion.getStateFilename()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    local dir = g_currentMission.missionInfo.savegameDirectory
    if dir == nil then
        return nil
    end
    return dir .. "/FS25_FarmEconomy_produktion.xml"
end

function AOProduktion.speichern()
    if not AgrarOekonomie.istServer() or XMLFile == nil then
        return
    end
    local filename = AOProduktion.getStateFilename()
    if filename == nil then
        return
    end
    local xml = XMLFile.create("aoProdXML", filename, "farmEconomyProduktion")
    if xml == nil then
        return
    end
    local i = 0
    for uid, f in pairs(AOProduktion.proUid) do
        local key = string.format("farmEconomyProduktion.produktion(%d)", i)
        xml:setString(key .. "#uniqueId", uid)
        xml:setFloat(key .. "#faktor", f)
        i = i + 1
    end
    xml:save()
    xml:delete()
end

function AOProduktion.laden()
    local filename = AOProduktion.getStateFilename()
    if filename == nil or XMLFile == nil then
        return
    end
    local xml = XMLFile.loadIfExists("aoProdXML", filename)
    if xml == nil then
        return
    end
    local i = 0
    while true do
        local key = string.format("farmEconomyProduktion.produktion(%d)", i)
        local uid = xml:getString(key .. "#uniqueId")
        if uid == nil then
            break
        end
        local f = xml:getFloat(key .. "#faktor", 0)
        if f > 0 then
            AOProduktion.proUid[uid] = f
        end
        i = i + 1
    end
    xml:delete()
end

function AOProduktion.statusZeilen()
    local cfg = AgrarOekonomie.CFG
    local zeilen = {
        string.format("  Produktion: aktiv=%s  Faktor=%.2f  Kosten=%s (0 gleich, 1 Wurzel, 2 voll)",
            tostring(cfg.prodAktiv), cfg.prodFaktor or 1, tostring(cfg.prodKosten)),
    }
    local pcm = AOProduktion.getManager()
    if pcm ~= nil and type(pcm.productionPoints) == "table" then
        for _, pp in pairs(pcm.productionPoints) do
            local einzel = AOProduktion.getEinzel(pp)
            if einzel ~= nil then
                table.insert(zeilen, string.format("    %s: eigener Faktor %.2f",
                    AOProduktion.getName(pp), einzel))
            end
        end
    end
    return zeilen
end

-- Konsole: aoProdDump
function AOProduktion.befehlDump(_)
    local zeilen = { AOProduktion.LOG .. "Produktionen:" }
    for _, pp in ipairs(AOProduktion.getEigene()) do
        table.insert(zeilen, string.format("  %s  (Faktor %.2f)", AOProduktion.getName(pp),
            AOProduktion.getFaktor(pp)))
        for _, prod in pairs(pp.productions or {}) do
            if type(prod) == "table" then
                local teile = {}
                for _, feld in ipairs(AOProduktion.ZYKLEN) do
                    if type(prod[feld]) == "number" then
                        table.insert(teile, string.format("%s=%.4f", feld, prod[feld]))
                    end
                end
                for _, feld in ipairs(AOProduktion.KOSTEN) do
                    if type(prod[feld]) == "number" then
                        table.insert(teile, string.format("%s=%.4f", feld, prod[feld]))
                    end
                end
                table.insert(zeilen, string.format("    %s: %s", tostring(prod.id),
                    table.concat(teile, "  ")))
            end
        end
    end
    return table.concat(zeilen, "\n")
end

function AOProduktion:loadMap(name)
    if AgrarOekonomie.istServer() then
        AOProduktion.laden()
        if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
            FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
                FSCareerMissionInfo.saveToXMLFile,
                function() AOProduktion.speichern() end)
        end
    else
        -- Client holt die Einzelwerte nach dem Beitreten ab
        local function frage()
            if g_client ~= nil and g_client.getServerConnection ~= nil and AOProduktionEvent ~= nil then
                local conn = g_client:getServerConnection()
                if conn ~= nil and conn.sendEvent ~= nil then
                    conn:sendEvent(AOProduktionEvent.newAnfrage())
                end
            end
        end
        if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_LOADED ~= nil then
            g_messageCenter:subscribeOneshot(MessageType.CURRENT_MISSION_LOADED, frage, AOProduktion)
        else
            frage()
        end
    end
    if addConsoleCommand ~= nil then
        addConsoleCommand("aoProdDump", "Zeigt die Zyklen und Kosten der eigenen Produktionen.",
            "befehlDump", AOProduktion)
    end
    AOProduktion.bereit = true
    Logging.info(AOProduktion.LOG .. "Produktionsgeschwindigkeit bereit (aktiv=%s).",
        tostring(AgrarOekonomie.CFG.prodAktiv))
end

-- Alle 2 s neu anwenden, so sind auch gekaufte oder verkaufte Gebaeude dabei.
function AOProduktion:update(dt)
    if not AOProduktion.bereit then
        return
    end
    AOProduktion.takt = AOProduktion.takt + dt
    if AOProduktion.takt < AOProduktion.TAKT_MS then
        return
    end
    AOProduktion.takt = 0
    AOProduktion.anwenden()
end

function AOProduktion:deleteMap()
    AOProduktion.proUid    = {}
    AOProduktion.proObjekt = {}
    AOProduktion.bereit    = false
    if removeConsoleCommand ~= nil then
        removeConsoleCommand("aoProdDump")
    end
end

addModEventListener(AOProduktion)
