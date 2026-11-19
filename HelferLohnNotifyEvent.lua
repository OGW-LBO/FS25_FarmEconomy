-- HelferLohnNotifyEvent.lua
-- Verteilt die Helfer-Meldungen (Anheuern, Absage, Bezahlung) an alle Clients.
-- OGW

HelferLohnNotifyEvent = {}
local HelferLohnNotifyEvent_mt = Class(HelferLohnNotifyEvent, Event)

InitEventClass(HelferLohnNotifyEvent, "HelferLohnNotifyEvent")

function HelferLohnNotifyEvent.emptyNew()
    return Event.new(HelferLohnNotifyEvent_mt)
end

function HelferLohnNotifyEvent.new(farmId, text)
    local self = HelferLohnNotifyEvent.emptyNew()
    self.farmId = farmId or 0
    self.text = text or ""
    return self
end

function HelferLohnNotifyEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteString(streamId, self.text)
end

function HelferLohnNotifyEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.text = streamReadString(streamId)

    self:run(connection)
end

function HelferLohnNotifyEvent:run(connection)
    -- Farm-Pruefung steckt in zeigeMeldung
    if HelferLohn ~= nil and HelferLohn.zeigeMeldung ~= nil then
        HelferLohn.zeigeMeldung(self.farmId, self.text)
    end
end
