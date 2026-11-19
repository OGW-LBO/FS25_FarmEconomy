-- FuhrparkSteuerNotifyEvent.lua
-- Schickt die Abbuchungs-Meldung vom Server an alle Clients, damit Mitspieler
-- auch ein Popup bekommen.
-- OGW

FuhrparkSteuerNotifyEvent = {}
local FuhrparkSteuerNotifyEvent_mt = Class(FuhrparkSteuerNotifyEvent, Event)

InitEventClass(FuhrparkSteuerNotifyEvent, "FuhrparkSteuerNotifyEvent")

function FuhrparkSteuerNotifyEvent.emptyNew()
    return Event.new(FuhrparkSteuerNotifyEvent_mt)
end

function FuhrparkSteuerNotifyEvent.new(farmId, anzahl, betrag, jaehrlich)
    local self = FuhrparkSteuerNotifyEvent.emptyNew()
    self.farmId = farmId or 0
    self.anzahl = anzahl or 0
    self.betrag = betrag or 0
    self.jaehrlich = (jaehrlich == true)
    return self
end

function FuhrparkSteuerNotifyEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.anzahl)
    streamWriteFloat32(streamId, self.betrag)
    streamWriteBool(streamId, self.jaehrlich)
end

function FuhrparkSteuerNotifyEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.anzahl = streamReadInt32(streamId)
    self.betrag = streamReadFloat32(streamId)
    self.jaehrlich = streamReadBool(streamId)

    self:run(connection)
end

function FuhrparkSteuerNotifyEvent:run(connection)
    -- ob es die eigene Farm ist, prueft zeigeMeldung
    if FuhrparkSteuer ~= nil and FuhrparkSteuer.zeigeMeldung ~= nil then
        FuhrparkSteuer.zeigeMeldung(self.farmId, self.anzahl, self.betrag, self.jaehrlich)
    end
end
