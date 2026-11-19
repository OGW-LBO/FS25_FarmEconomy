-- AOProduktionEvent.lua
-- Einzelfaktoren je Produktionsgebaeude: ANFRAGE (Client beim Beitreten),
-- LISTE (Server an Clients), AENDERUNG (Client, nur Admins).
-- Placeables gehen als Netzwerk-Objekt raus, gekaufte haben am Client keine uniqueId.
-- OGW

AOProduktionEvent = {}
local AOProduktionEvent_mt = Class(AOProduktionEvent, Event)

InitEventClass(AOProduktionEvent, "AOProduktionEvent")

AOProduktionEvent.ANFRAGE   = 0
AOProduktionEvent.LISTE     = 1
AOProduktionEvent.AENDERUNG = 2

function AOProduktionEvent.emptyNew()
    return Event.new(AOProduktionEvent_mt)
end

function AOProduktionEvent.newAnfrage()
    local self = AOProduktionEvent.emptyNew()
    self.art = AOProduktionEvent.ANFRAGE
    return self
end

function AOProduktionEvent.newListe()
    local self = AOProduktionEvent.emptyNew()
    self.art   = AOProduktionEvent.LISTE
    self.liste = AOProduktion.getListe()
    return self
end

function AOProduktionEvent.newAenderung(placeable, faktor)
    local self = AOProduktionEvent.emptyNew()
    self.art       = AOProduktionEvent.AENDERUNG
    self.placeable = placeable
    self.faktor    = faktor
    return self
end

function AOProduktionEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.art, 2)

    if self.art == AOProduktionEvent.LISTE then
        local liste = self.liste or {}
        streamWriteUInt16(streamId, #liste)
        for _, e in ipairs(liste) do
            NetworkUtil.writeNodeObject(streamId, e.placeable)
            streamWriteFloat32(streamId, e.faktor or 0)
        end
    elseif self.art == AOProduktionEvent.AENDERUNG then
        NetworkUtil.writeNodeObject(streamId, self.placeable)
        streamWriteFloat32(streamId, self.faktor or 0)
    end
end

function AOProduktionEvent:readStream(streamId, connection)
    self.art = streamReadUIntN(streamId, 2)

    if self.art == AOProduktionEvent.LISTE then
        local anzahl = streamReadUInt16(streamId)
        self.liste = {}
        for _ = 1, anzahl do
            local pl = NetworkUtil.readNodeObject(streamId)
            local f  = streamReadFloat32(streamId)
            table.insert(self.liste, { placeable = pl, faktor = f })
        end
    elseif self.art == AOProduktionEvent.AENDERUNG then
        self.placeable = NetworkUtil.readNodeObject(streamId)
        self.faktor    = streamReadFloat32(streamId)
    end

    self:run(connection)
end

function AOProduktionEvent:run(connection)
    -- getIsServer() == true: wir sind Client
    local empfaengerIstClient = connection:getIsServer()

    if self.art == AOProduktionEvent.LISTE then
        if empfaengerIstClient then
            AOProduktion.uebernehmeListe(self.liste or {})
        end
        return
    end

    if empfaengerIstClient then
        return
    end

    if self.art == AOProduktionEvent.ANFRAGE then
        connection:sendEvent(AOProduktionEvent.newListe())
        return
    end

    if self.art == AOProduktionEvent.AENDERUNG then
        if AOSettingsEvent ~= nil and AOSettingsEvent.istAdmin ~= nil
                and not AOSettingsEvent.istAdmin(connection) then
            Logging.info("[AgrarOekonomie] Produktionsfaktor eines Spielers ohne Admin-Rechte abgelehnt.")
            connection:sendEvent(AOProduktionEvent.newListe())
            return
        end
        if self.placeable ~= nil then
            AOProduktion.setzeEinzelServer(self.placeable, self.faktor or 0)
        end
    end
end
