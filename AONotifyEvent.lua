-- AONotifyEvent.lua
-- Meldungen vom Server, angezeigt nur bei der betroffenen Farm (0 = alle).
-- Meist kommt statt Text ein l10n-Schluessel mit Werten, damit jeder Client
-- in seiner Sprache anzeigt:
--   "@schluessel|g:1234|n:5.5"   g Geld, f Faktor, n eine Stelle, i ganzzahlig, s Text
-- OGW

AONotifyEvent = {}
local AONotifyEvent_mt = Class(AONotifyEvent, Event)

InitEventClass(AONotifyEvent, "AONotifyEvent")

function AONotifyEvent.emptyNew()
    return Event.new(AONotifyEvent_mt)
end

function AONotifyEvent.new(farmId, text)
    local self = AONotifyEvent.emptyNew()
    self.farmId = farmId or 0
    self.text   = text or ""
    return self
end

function AONotifyEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteString(streamId, self.text)
end

function AONotifyEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.text   = streamReadString(streamId)
    self:run(connection)
end

function AONotifyEvent:run(connection)
    AONotifyEvent.zeigeLokal(self.farmId, self.text)
end

local function formatiereWert(teil)
    local typ, roh = string.match(teil, "^(%a):(.*)$")
    if typ == nil then
        return teil
    end

    local zahl = tonumber(roh)
    if typ == "g" and zahl ~= nil then
        if AgrarOekonomie ~= nil and AgrarOekonomie.formatGeld ~= nil then
            return AgrarOekonomie.formatGeld(zahl)
        end
        return string.format("%d", math.floor(zahl + 0.5))
    elseif typ == "f" and zahl ~= nil then
        return string.format("%.2f", zahl)
    elseif typ == "n" and zahl ~= nil then
        return string.format("%.1f", zahl)
    elseif typ == "i" and zahl ~= nil then
        return string.format("%d", math.floor(zahl + 0.5))
    end
    return roh
end

function AONotifyEvent.formatiere(text)
    if text == nil or string.sub(text, 1, 1) ~= "@" then
        return text
    end

    local teile = {}
    for teil in string.gmatch(string.sub(text, 2), "[^|]+") do
        table.insert(teile, teil)
    end
    local schluessel = table.remove(teile, 1)
    if schluessel == nil then
        return text
    end

    local vorlage = schluessel
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n.getText ~= nil then
        if g_i18n:hasText(schluessel) then
            local t = g_i18n:getText(schluessel)
            if type(t) == "string" then
                vorlage = t
            end
        end
    end

    local werte = {}
    for _, teil in ipairs(teile) do
        table.insert(werte, tostring(formatiereWert(teil)))
    end

    -- nur formatieren, wenn die Zahl der %s-Platzhalter passt
    local ohneProzent = string.gsub(vorlage, "%%%%", "")
    local alle        = select(2, string.gsub(ohneProzent, "%%", ""))
    local nurS        = select(2, string.gsub(ohneProzent, "%%s", ""))
    if alle ~= nurS or nurS ~= #werte then
        return vorlage
    end
    return string.format(vorlage, unpack(werte))
end

-- Wird auch direkt vom Server aufgerufen (Host, Singleplayer).
function AONotifyEvent.zeigeLokal(farmId, text)
    if AgrarOekonomie == nil or not AgrarOekonomie.CFG.meldungen then
        return
    end
    if g_currentMission == nil or text == nil or text == "" then
        return
    end

    if farmId ~= nil and farmId ~= 0 then
        local eigeneFarm = nil
        if g_currentMission.getFarmId ~= nil then
            eigeneFarm = g_currentMission:getFarmId()
        end
        if eigeneFarm ~= nil and eigeneFarm ~= farmId then
            return
        end
    end

    local anzeige = AONotifyEvent.formatiere(text)

    if FSBaseMission ~= nil and g_currentMission.hud ~= nil
            and g_currentMission.hud.addSideNotification ~= nil then
        g_currentMission.hud:addSideNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, anzeige, 8000)
    elseif FSBaseMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, anzeige)
    else
        Logging.info("[AgrarOekonomie] %s", tostring(anzeige))
    end
end
