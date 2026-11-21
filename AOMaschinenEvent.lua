-- AOMaschinenEvent.lua
-- Der Client fragt die Zahlen seines Fuhrparks fuer einen Zeitraum an, der
-- Server schickt das Paket aus AOMaschinenMain.erstellePaket zurueck.
-- OGW

AOMaschinenEvent = {}
local AOMaschinenEvent_mt = Class(AOMaschinenEvent, Event)

InitEventClass(AOMaschinenEvent, "AOMaschinenEvent")

AOMaschinenEvent.WAHLEN = { "jahr", "vorjahr", "gesamt" }

local function wahlNummer(wahl)
    for i, w in ipairs(AOMaschinenEvent.WAHLEN) do
        if w == wahl then
            return i
        end
    end
    return 1
end

function AOMaschinenEvent.emptyNew()
    return Event.new(AOMaschinenEvent_mt)
end

function AOMaschinenEvent.new(anfrage, farmId, wahl, paket)
    local self = AOMaschinenEvent.emptyNew()
    self.anfrage = (anfrage == true)
    self.farmId  = farmId or 0
    self.wahl    = wahl or "jahr"
    self.paket   = paket
    return self
end

function AOMaschinenEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.anfrage)
    streamWriteInt32(streamId, self.farmId)
    streamWriteUIntN(streamId, wahlNummer(self.wahl), 3)
    if self.anfrage then
        return
    end

    local p = self.paket
    streamWriteBool(streamId, p.aktiv == true)
    streamWriteInt32(streamId, #AOMaschinen.NETZ)
    streamWriteInt32(streamId, #p.eintraege)
    for _, r in ipairs(p.eintraege) do
        NetworkUtil.writeNodeObject(streamId, r.vehicle)
        streamWriteString(streamId, r.name or "?")
        streamWriteBool(streamId, r.geleast == true)
        streamWriteBool(streamId, r.motor == true)
        streamWriteBool(streamId, r.altbestand == true)
        for _, feld in ipairs(AOMaschinen.NETZ) do
            streamWriteFloat32(streamId, r[feld] or 0)
        end
        streamWriteInt32(streamId, #r.kraftstoff)
        for _, k in ipairs(r.kraftstoff) do
            streamWriteString(streamId, k.typ)
            streamWriteFloat32(streamId, k.liter)
            streamWriteFloat32(streamId, k.kosten)
        end
    end
end

function AOMaschinenEvent:readStream(streamId, connection)
    self.anfrage = streamReadBool(streamId)
    self.farmId  = streamReadInt32(streamId)
    self.wahl    = AOMaschinenEvent.WAHLEN[streamReadUIntN(streamId, 3)] or "jahr"

    if not self.anfrage then
        local p = { farmId = self.farmId, wahl = self.wahl, eintraege = {} }
        p.aktiv = streamReadBool(streamId)
        local anzahlFelder = streamReadInt32(streamId)
        local anzahl = streamReadInt32(streamId)
        for i = 1, anzahl do
            local r = { kraftstoff = {} }
            r.vehicle    = NetworkUtil.readNodeObject(streamId)
            r.name       = streamReadString(streamId)
            r.geleast    = streamReadBool(streamId)
            r.motor      = streamReadBool(streamId)
            r.altbestand = streamReadBool(streamId)
            for f = 1, anzahlFelder do
                local wert = streamReadFloat32(streamId)
                local feld = AOMaschinen.NETZ[f]
                if feld ~= nil then
                    r[feld] = wert
                end
            end
            local sorten = streamReadInt32(streamId)
            for k = 1, sorten do
                r.kraftstoff[k] = {
                    typ    = streamReadString(streamId),
                    liter  = streamReadFloat32(streamId),
                    kosten = streamReadFloat32(streamId),
                }
            end
            p.eintraege[i] = r
        end

        if anzahlFelder == #AOMaschinen.NETZ then
            self.paket = p
        else
            Logging.warning("[AgrarOekonomie] Fuhrpark verworfen: Server sendet %d Werte je Fahrzeug, erwartet %d. " ..
                "Laeuft auf Server und Client dieselbe Mod-Version?", anzahlFelder, #AOMaschinen.NETZ)
        end
    end

    self:run(connection)
end

function AOMaschinenEvent:run(connection)
    -- getIsServer() == true heisst: wir sind der Client
    local empfaengerIstClient = connection:getIsServer()

    if self.anfrage then
        if not empfaengerIstClient and self.farmId > 0 and AOMaschinenMain ~= nil
                and AOMaschinenMain.erstellePaket ~= nil then
            local paket = AOMaschinenMain.erstellePaket(self.farmId, self.wahl)
            connection:sendEvent(AOMaschinenEvent.new(false, self.farmId, self.wahl, paket))
        end
    elseif empfaengerIstClient and self.paket ~= nil and AOMaschinenMain ~= nil then
        AOMaschinenMain.empfange(self.paket)
    end
end
