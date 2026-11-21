-- AOAbgabenEvent.lua
-- Der Client fragt die Zahlen der Seite "Abgaben und Helfer" an, der Server
-- schickt sie in der Reihenfolge von AOAbgaben.FELDER zurueck.
-- OGW

AOAbgabenEvent = {}
local AOAbgabenEvent_mt = Class(AOAbgabenEvent, Event)

InitEventClass(AOAbgabenEvent, "AOAbgabenEvent")

function AOAbgabenEvent.emptyNew()
    return Event.new(AOAbgabenEvent_mt)
end

function AOAbgabenEvent.new(anfrage, farmId, paket)
    local self = AOAbgabenEvent.emptyNew()
    self.anfrage = (anfrage == true)
    self.farmId  = farmId or 0
    self.paket   = paket
    return self
end

function AOAbgabenEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.anfrage)
    streamWriteInt32(streamId, self.farmId)
    if self.anfrage then
        return
    end
    streamWriteInt32(streamId, #AOAbgaben.FELDER)
    for _, feld in ipairs(AOAbgaben.FELDER) do
        streamWriteFloat32(streamId, self.paket[feld] or 0)
    end
end

function AOAbgabenEvent:readStream(streamId, connection)
    self.anfrage = streamReadBool(streamId)
    self.farmId  = streamReadInt32(streamId)
    if not self.anfrage then
        local anzahl = streamReadInt32(streamId)
        local p = {}
        for i = 1, anzahl do
            local wert = streamReadFloat32(streamId)
            local feld = AOAbgaben.FELDER[i]
            if feld ~= nil then
                p[feld] = wert
            end
        end
        if anzahl == #AOAbgaben.FELDER then
            self.paket = p
        else
            Logging.warning("[AgrarOekonomie] Abgaben verworfen: Server sendet %d Werte, erwartet %d. " ..
                "Laeuft auf Server und Client dieselbe Mod-Version?", anzahl, #AOAbgaben.FELDER)
        end
    end
    self:run(connection)
end

function AOAbgabenEvent:run(connection)
    local empfaengerIstClient = connection:getIsServer()
    if self.anfrage then
        if not empfaengerIstClient and self.farmId > 0 then
            connection:sendEvent(AOAbgabenEvent.new(false, self.farmId, AOAbgaben.erstellePaket(self.farmId)))
        end
    elseif empfaengerIstClient and self.paket ~= nil then
        AOAbgaben.empfange(self.paket)
    end
end
