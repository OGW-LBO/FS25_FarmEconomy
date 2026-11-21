-- AOSettings.lua
-- Eine settings.xml und ein MP-Event fuer alle Module. Der Server speichert
-- und verteilt, Clients schicken nur Aenderungswuensche.
-- OGW

AOSettings = {}

AOSettings.LOG = "[AgrarOekonomie] "

AOSettings.settingsDir    = g_currentModSettingsDirectory
AOSettings.xmlFilename    = nil
AOSettings.initialisiert  = false

-- id ist das Praefix in XML und Event ("ao.preisFruechte"). Werte ohne meta-Eintrag
-- gehen ungeprueft durch.
AOSettings.MODULE = {
    {
        id     = "ao",
        titel  = "Agrar-Oekonomie",
        getCfg = function()
            return AgrarOekonomie ~= nil and AgrarOekonomie.CFG or nil
        end,
        meta = {
            { key = "preiseAktiv",        bool = true },
            { key = "preisFruechte",      min = 0.10, max = 1.50,    step = 0.05 },
            { key = "preisProdukte",      min = 0.10, max = 1.50,    step = 0.05 },
            { key = "grundsteuerAktiv",   bool = true },
            { key = "grundsteuerProJahr", min = 0.00, max = 0.20,    step = 0.005 },
            { key = "bremseAktiv",        bool = true },
            { key = "bremseAnteil",       min = 0.05, max = 1.00,    step = 0.05 },
            { key = "bremseFenster",      min = 1,    max = 30,      step = 1 },
            { key = "notbremseKonto",     min = 0,    max = 5000000, step = 10000 },
            { key = "karenzMonate",       min = 0,    max = 24,      step = 1 },
            { key = "verbrauchNurEigene", bool = true },
            { key = "verbrauchBindegarn", min = 0,    max = 100,     step = 0.5 },
            { key = "verbrauchNetz",      min = 0,    max = 100,     step = 0.5 },
            { key = "verbrauchFolie",     min = 0,    max = 100,     step = 0.5 },
            { key = "dieselAktiv",        bool = true },
            { key = "dieselFaktor",       min = 0.10, max = 4.00,    step = 0.05 },
            { key = "dieselFaktorFahrt",  min = 0.10, max = 4.00,    step = 0.05 },
            { key = "dieselProKwh",       min = 0.00, max = 0.60,    step = 0.01 },
            { key = "dieselLastkurve",    bool = true },
            { key = "dieselAnzeige",      bool = true },
            { key = "zinsAktiv",          bool = true },
            { key = "zinsSatz",           min = 0.00, max = 0.10,    step = 0.0025 },
            { key = "zinsGrenze1",        min = 0,    max = 50000000, step = 50000 },
            { key = "zinsGrenze2",        min = 0,    max = 50000000, step = 50000 },
            { key = "prodAktiv",          bool = true },
            { key = "prodFaktor",         min = 0.25, max = 10.0,    step = 0.25 },
            { key = "prodKosten",         min = 0,    max = 2,       step = 1 },
            { key = "buchAktiv",          bool = true },
            { key = "buchSchwelle",       min = 0,    max = 5000,    step = 50 },
            { key = "mkAktiv",            bool = true },
            { key = "meldungen",          bool = true },
            { key = "debug",              bool = true },
            { key = "autoAktiv",          bool = true },
            { key = "autoStufe",          min = 0,    max = 4,       step = 1 },
            { key = "autoZielMin",        min = 0,    max = 20000,   step = 100 },
            { key = "autoZielMax",        min = 0,    max = 20000,   step = 100 },
            { key = "autoSchritt",        min = 0.01, max = 0.50,    step = 0.01 },
            -- nur Anzeige, setzt der Server
            { key = "autoLetzteBilanz",   min = -1,   max = 1000000, step = 1 },
            { key = "autoLetzterFaktor",  min = -1,   max = 10,      step = 0.01 },
            { key = "autoPerioden",       min = 0,    max = 12,      step = 1 },
        },
    },
    {
        id     = "fuhrpark",
        titel  = "Fuhrpark-Steuer",
        getCfg = function()
            return FuhrparkSteuer ~= nil and FuhrparkSteuer.CFG or nil
        end,
        meta = {
            { key = "enabled",                bool = true },
            { key = "billingMode",            min = 0,   max = 1,     step = 1 },
            { key = "taxRatePerYear",         min = 0.0, max = 0.50,  step = 0.005 },
            { key = "upkeepRatePerYear",      min = 0.0, max = 0.50,  step = 0.005 },
            { key = "useResaleValue",         bool = true },
            { key = "rabattRuhend",           min = 0.0, max = 1.0,   step = 0.05 },
            { key = "rabattUnterstand",       min = 0.0, max = 1.0,   step = 0.05 },
            { key = "rabattMinAnteil",        min = 0.0, max = 1.0,   step = 0.05 },
            { key = "minCostPerVehicleMonth", min = 0,   max = 10000, step = 1 },
            { key = "ownedOnly",              bool = true },
            { key = "showNotification",       bool = true },
            { key = "showInInfoBox",          bool = true },
            { key = "daysPerMonth",           min = 1,   max = 60,    step = 1 },
        },
    },
    {
        id     = "reparatur",
        titel  = "Reparatur-Oekonomie",
        getCfg = function()
            return ReparaturOekonomie ~= nil and ReparaturOekonomie.CFG or nil
        end,
        meta = {
            { key = "grundfaktorReparatur",   min = 0.5,  max = 3.0,  step = 0.25 },
            { key = "faktorStunden",          min = 0.0,  max = 1.5,  step = 0.1 },
            { key = "referenzStunden",        min = 25,   max = 300,  step = 25 },
            { key = "faktorProReparatur",     min = 0.0,  max = 0.10, step = 0.01 },
            { key = "faktorAlter",            min = 0.0,  max = 1.0,  step = 0.1 },
            { key = "faktorMax",              min = 1.5,  max = 4.0,  step = 0.25 },
            { key = "grundfaktorLackieren",   min = 0.5,  max = 3.0,  step = 0.25 },
            { key = "tempoSchaden",           min = 0.25, max = 3.0,  step = 0.25 },
            { key = "tempoLack",              min = 0.25, max = 3.0,  step = 0.25 },
            { key = "warnAnteil",             min = 0.10, max = 0.90, step = 0.05 },
            { key = "kritischAnteil",         min = 0.15, max = 1.20, step = 0.05 },
            { key = "neukaufMindestNeupreis", min = 0.0,  max = 1.0,  step = 0.05 },
            { key = "warnStunden",            min = 0,    max = 1000, step = 5 },
            { key = "kritischStunden",        min = 0,    max = 1000, step = 5 },
            { key = "klasseTempoErnte",       min = 0.1,  max = 3.0,  step = 0.05 },
            { key = "klasseTempoMotor",       min = 0.1,  max = 3.0,  step = 0.05 },
            { key = "klasseTempoAnbau",       min = 0.1,  max = 3.0,  step = 0.05 },
            { key = "klasseNeukaufErnte",     min = 0.1,  max = 5.0,  step = 0.05 },
            { key = "klasseNeukaufMotor",     min = 0.1,  max = 5.0,  step = 0.05 },
            { key = "klasseNeukaufAnbau",     min = 0.1,  max = 5.0,  step = 0.05 },
        },
    },
    {
        id     = "helfer",
        titel  = "Helfer-Arbeitsmarkt",
        getCfg = function()
            return HelferLohn ~= nil and HelferLohn.CFG or nil
        end,
        meta = {
            { key = "aktiv",            bool = true },
            { key = "bezahlModus",      min = 0,   max = 1,       step = 1 },
            { key = "schwierigkeit",    min = 0,   max = 4,       step = 1 },
            { key = "lohnStufe",        min = 0,   max = 3,       step = 1 },
            { key = "faktorAzubi",      min = 0.0, max = 5.0,     step = 0.05 },
            { key = "faktorQuer",       min = 0.0, max = 5.0,     step = 0.05 },
            { key = "faktorAusgelernt", min = 0.0, max = 5.0,     step = 0.05 },
            { key = "faktorEigen",      min = 0.0, max = 5.0,     step = 0.05 },
            { key = "festLohn",         min = 0,   max = 1000000, step = 10 },
            { key = "zufallVerfuegbar", bool = true },
            { key = "marktMin",         min = 0.0, max = 3.0,     step = 0.05 },
            { key = "marktMax",         min = 0.0, max = 3.0,     step = 0.05 },
            { key = "festMarktBasis",   min = 0,   max = 1000000, step = 10 },
            { key = "preisLeicht",      min = 0,   max = 1000000, step = 10 },
            { key = "preisMittel",      min = 0,   max = 1000000, step = 10 },
            { key = "preisBoden",       min = 0,   max = 1000000, step = 10 },
            { key = "preisPressen",     min = 0,   max = 1000000, step = 10 },
            { key = "preisDreschen",    min = 0,   max = 1000000, step = 10 },
            { key = "preisHaeckseln",   min = 0,   max = 1000000, step = 10 },
            { key = "meldung",          bool = true },
            { key = "gratisBetrieb",    bool = true },
            { key = "nurBeiErfolg",     bool = true },
        },
    },
}

function AOSettings.istServer()
    if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil then
        return g_currentMission:getIsServer() == true
    end
    return g_server ~= nil
end

function AOSettings.getModul(id)
    for _, modul in ipairs(AOSettings.MODULE) do
        if modul.id == id then
            return modul
        end
    end
    return nil
end

function AOSettings.getMeta(modul, key)
    if modul == nil or modul.meta == nil then
        return nil
    end
    for _, m in ipairs(modul.meta) do
        if m.key == key then
            return m
        end
    end
    return nil
end

-- feste Reihenfolge, damit Server und Client gleich lesen
function AOSettings.sortedKeys()
    local liste = {}

    for _, modul in ipairs(AOSettings.MODULE) do
        local cfg = modul.getCfg()
        if cfg ~= nil then
            local keys = {}
            for k, v in pairs(cfg) do
                local t = type(v)
                if t == "number" or t == "boolean" then
                    keys[#keys + 1] = k
                end
            end
            table.sort(keys)
            for _, k in ipairs(keys) do
                liste[#liste + 1] = {
                    modulId = modul.id,
                    key     = k,
                    wireKey = modul.id .. "." .. k,
                }
            end
        end
    end

    return liste
end

-- nur lokal, ohne Sync
function AOSettings.applyValue(modulId, key, value)
    local modul = AOSettings.getModul(modulId)
    if modul == nil then
        return false
    end

    local cfg = modul.getCfg()
    if cfg == nil or cfg[key] == nil then
        return false
    end

    if type(cfg[key]) == "boolean" then
        cfg[key] = (value == true or value == 1 or value == "true" or value == "1")
        return true
    end

    local num = tonumber(value)
    if num == nil then
        return false
    end

    local meta = AOSettings.getMeta(modul, key)
    if meta ~= nil then
        if meta.min ~= nil then num = math.max(meta.min, num) end
        if meta.max ~= nil then num = math.min(meta.max, num) end
    end

    cfg[key] = num
    return true
end

-- "modul.key" oder nur "key" (dann das erste Modul, das ihn hat)
function AOSettings.findeSchluessel(name)
    if type(name) ~= "string" then
        return nil, nil
    end

    local punkt = string.find(name, ".", 1, true)
    if punkt ~= nil then
        local modulId = string.sub(name, 1, punkt - 1)
        local key     = string.sub(name, punkt + 1)
        local modul   = AOSettings.getModul(modulId)
        if modul ~= nil then
            local cfg = modul.getCfg()
            if cfg ~= nil and cfg[key] ~= nil then
                return modulId, key
            end
        end
        return nil, nil
    end

    for _, modul in ipairs(AOSettings.MODULE) do
        local cfg = modul.getCfg()
        if cfg ~= nil and cfg[name] ~= nil then
            return modul.id, name
        end
    end
    return nil, nil
end

function AOSettings.setzeWert(name, wert)
    local modulId, key = AOSettings.findeSchluessel(name)
    if modulId == nil then
        return false, string.format("Unbekannte Einstellung '%s'.", tostring(name))
    end

    if not AOSettings.applyValue(modulId, key, wert) then
        return false, string.format("Wert '%s' fuer '%s.%s' nicht gueltig.",
            tostring(wert), modulId, key)
    end

    AOSettings.onLocalChange()

    local cfg = AOSettings.getModul(modulId).getCfg()
    return true, string.format("%s.%s = %s", modulId, key, tostring(cfg[key]))
end

-- Speichern (nur Server bzw. SP) ----------------------------------------------

function AOSettings.getXmlFilename()
    if AOSettings.xmlFilename ~= nil then
        return AOSettings.xmlFilename
    end

    local dir = AOSettings.settingsDir
    if dir == nil then
        return nil
    end

    if createFolder ~= nil then
        createFolder(dir)
    end

    AOSettings.xmlFilename = dir .. "settings.xml"
    return AOSettings.xmlFilename
end

function AOSettings.save()
    if not AOSettings.istServer() then
        return
    end

    local filename = AOSettings.getXmlFilename()
    if filename == nil or XMLFile == nil then
        return
    end

    local xmlFile = XMLFile.create("aoSettingsXML", filename, "settings")
    if xmlFile == nil then
        return
    end

    for _, eintrag in ipairs(AOSettings.sortedKeys()) do
        local cfg  = AOSettings.getModul(eintrag.modulId).getCfg()
        local pfad = "settings." .. eintrag.modulId .. "." .. eintrag.key
        local v    = cfg[eintrag.key]
        if type(v) == "boolean" then
            xmlFile:setBool(pfad, v)
        elseif type(v) == "number" then
            xmlFile:setFloat(pfad, v)
        end
    end

    xmlFile:save()
    xmlFile:delete()
end

-- alte Einstellung karenzTage umrechnen; ueber 24 war es der alte Standard, dann 3 Monate
function AOSettings.migriereKarenz(xmlFile)
    if AgrarOekonomie == nil or AgrarOekonomie.CFG == nil then
        return
    end
    if xmlFile:getFloat("settings.ao.karenzMonate") ~= nil then
        return
    end

    local alt = xmlFile:getFloat("settings.ao.karenzTage")
    if alt == nil then
        return
    end

    local neu = alt
    if alt > 24 then
        neu = 3
    end
    AOSettings.applyValue("ao", "karenzMonate", neu)

    Logging.info(AOSettings.LOG .. "Migration: karenzTage=%s -> karenzMonate=%s (Einheit jetzt Spielmonate).",
        tostring(alt), tostring(AgrarOekonomie.CFG.karenzMonate))
end

-- bis 1.0 gab es nur an/aus; aus wird "gleich bleibend", an "voll mit"
function AOSettings.migriereProdKosten(xmlFile)
    if xmlFile:getFloat("settings.ao.prodKosten") ~= nil then
        return
    end
    local alt = xmlFile:getBool("settings.ao.prodKostenMit")
    if alt == nil then
        return
    end
    AOSettings.applyValue("ao", "prodKosten", alt and 2 or 0)
    Logging.info(AOSettings.LOG .. "Migration: prodKostenMit=%s -> prodKosten=%d.",
        tostring(alt), alt and 2 or 0)
end

function AOSettings.load()
    local filename = AOSettings.getXmlFilename()
    if filename == nil or XMLFile == nil then
        return
    end

    local xmlFile = XMLFile.loadIfExists("aoSettingsXML", filename)
    if xmlFile == nil then
        return
    end

    for _, eintrag in ipairs(AOSettings.sortedKeys()) do
        local cfg  = AOSettings.getModul(eintrag.modulId).getCfg()
        local pfad = "settings." .. eintrag.modulId .. "." .. eintrag.key
        if type(cfg[eintrag.key]) == "boolean" then
            local v = xmlFile:getBool(pfad)
            if v ~= nil then
                cfg[eintrag.key] = v
            end
        else
            local v = xmlFile:getFloat(pfad)
            if v ~= nil then
                AOSettings.applyValue(eintrag.modulId, eintrag.key, v)
            end
        end
    end

    AOSettings.migriereKarenz(xmlFile)
    AOSettings.migriereProdKosten(xmlFile)

    xmlFile:delete()
end

-- Multiplayer -----------------------------------------------------------------

function AOSettings.broadcast()
    if AOSettings.istServer() and g_server ~= nil and AOSettingsEvent ~= nil then
        if g_server.broadcastEvent ~= nil then
            g_server:broadcastEvent(AOSettingsEvent.new(true), false)
        end
    end
end

function AOSettings.onLocalChange()
    if AOSettings.istServer() then
        AOSettings.save()
        AOSettings.broadcast()
    elseif g_client ~= nil and AOSettingsEvent ~= nil and g_client.getServerConnection ~= nil then
        local conn = g_client:getServerConnection()
        if conn ~= nil and conn.sendEvent ~= nil then
            conn:sendEvent(AOSettingsEvent.new(true))
        end
    end
end

function AOSettings.onServerReceivedChange()
    AOSettings.save()
    AOSettings.broadcast()
end

function AOSettings.reload()
    if not AOSettings.istServer() then
        return false, "Nur der Server (bzw. Singleplayer) kann die settings.xml neu laden."
    end
    AOSettings.load()
    AOSettings.broadcast()
    return true, AOSettings.getXmlFilename()
end

function AOSettings.clientFrageServer()
    if AOSettingsEvent == nil then
        return
    end
    if g_client == nil or g_client.getServerConnection == nil then
        return
    end

    local conn = g_client:getServerConnection()
    if conn ~= nil and conn.sendEvent ~= nil then
        conn:sendEvent(AOSettingsEvent.new(false))
    end
end

function AOSettings:loadMap(name)
    if AOSettings.initialisiert then
        return
    end
    AOSettings.initialisiert = true

    local istServer = AOSettings.istServer()

    if istServer then
        AOSettings.load()
        AOSettings.save()

        if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
            FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
                FSCareerMissionInfo.saveToXMLFile,
                function() AOSettings.save() end)
        end
    else
        if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_LOADED ~= nil then
            g_messageCenter:subscribeOneshot(MessageType.CURRENT_MISSION_LOADED,
                AOSettings.clientFrageServer, AOSettings)
        else
            AOSettings.clientFrageServer()
        end
    end

    Logging.info(AOSettings.LOG .. "Einstellungen bereit (Server=%s).", tostring(istServer))
end

addModEventListener(AOSettings)

-- Die alten Module rufen noch ihre eigenen Settings-Tabellen auf, die gibt es hier als Shim.

local function baueShim(modulId)
    return {
        applyValue = function(key, value)
            local ok = AOSettings.applyValue(modulId, key, value)
            return ok
        end,
        onLocalChange = function()
            AOSettings.onLocalChange()
        end,
        reload = function()
            return AOSettings.reload()
        end,
        save = function()
            AOSettings.save()
        end,
        load = function()
            AOSettings.load()
        end,
        broadcast = function()
            AOSettings.broadcast()
        end,
        istServer = function()
            return AOSettings.istServer()
        end,
        getXmlFilename = function()
            return AOSettings.getXmlFilename()
        end,
    }
end

FuhrparkSteuerSettings      = baueShim("fuhrpark")
ReparaturOekonomieSettings  = baueShim("reparatur")
HelferLohnSettings          = baueShim("helfer")
