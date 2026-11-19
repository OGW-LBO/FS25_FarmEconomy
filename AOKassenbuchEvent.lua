-- AOKassenbuchEvent.lua
-- Der Client fragt sein Kassenbuch an, der Server schickt das Paket aus
-- AOKassenbuch.erstellePaket zurueck.
-- OGW

AOKassenbuchEvent = {}
local AOKassenbuchEvent_mt = Class(AOKassenbuchEvent, Event)

InitEventClass(AOKassenbuchEvent, "AOKassenbuchEvent")

function AOKassenbuchEvent.emptyNew()
    return Event.new(AOKassenbuchEvent_mt)
end

function AOKassenbuchEvent.new(anfrage, farmId, paket)
    local self = AOKassenbuchEvent.emptyNew()
    self.anfrage = (anfrage == true)
    self.farmId  = farmId or 0
    self.paket   = paket
    return self
end

function AOKassenbuchEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.anfrage)
    streamWriteInt32(streamId, self.farmId)
    if self.anfrage then
        return
    end

    local p   = self.paket
    local ids = AOKassenbuch.gruppenIds()

    streamWriteInt32(streamId, p.jahr or 1)
    streamWriteInt32(streamId, p.monat or 1)
    streamWriteInt32(streamId, #ids)
    streamWriteInt32(streamId, #p.monate)
    for _, m in ipairs(p.monate) do
        streamWriteInt32(streamId, m.jahr)
        streamWriteInt32(streamId, m.monat)
        for i = 1, #ids do
            streamWriteFloat32(streamId, m.werte[i] or 0)
        end
        streamWriteInt32(streamId, #m.letzte)
        for _, e in ipairs(m.letzte) do
            streamWriteString(streamId, e.zeit)
            streamWriteInt32(streamId, e.gruppe)
            streamWriteFloat32(streamId, e.betrag)
            streamWriteBool(streamId, e.summe)
            streamWriteString(streamId, e.kategorie)
        end
    end
end

function AOKassenbuchEvent:readStream(streamId, connection)
    self.anfrage = streamReadBool(streamId)
    self.farmId  = streamReadInt32(streamId)

    if not self.anfrage then
        local p = { monate = {} }
        p.jahr  = streamReadInt32(streamId)
        p.monat = streamReadInt32(streamId)

        local anzahlGruppen = streamReadInt32(streamId)
        local anzahlMonate  = streamReadInt32(streamId)
        for j = 1, anzahlMonate do
            local m = { werte = {}, letzte = {} }
            m.jahr  = streamReadInt32(streamId)
            m.monat = streamReadInt32(streamId)
            for i = 1, anzahlGruppen do
                m.werte[i] = streamReadFloat32(streamId)
            end
            local anzahlLetzte = streamReadInt32(streamId)
            for i = 1, anzahlLetzte do
                m.letzte[i] = {
                    zeit      = streamReadString(streamId),
                    gruppe    = streamReadInt32(streamId),
                    betrag    = streamReadFloat32(streamId),
                    summe     = streamReadBool(streamId),
                    kategorie = streamReadString(streamId),
                }
            end
            p.monate[j] = m
        end

        -- bei falscher Anzahl ist trotzdem alles gelesen, nur verworfen
        if anzahlGruppen == #AOKassenbuch.gruppenIds() then
            self.paket = p
        else
            Logging.warning("[AgrarOekonomie] Kassenbuch verworfen: Server sendet %d Gruppen, erwartet %d. " ..
                "Laeuft auf Server und Client dieselbe Mod-Version?",
                anzahlGruppen, #AOKassenbuch.gruppenIds())
        end
    end

    self:run(connection)
end

function AOKassenbuchEvent:run(connection)
    -- getIsServer() == true heisst: wir sind der Client
    local empfaengerIstClient = connection:getIsServer()

    if self.anfrage then
        if not empfaengerIstClient and self.farmId > 0 then
            local paket = nil
            if AOKassenbuch ~= nil and AOKassenbuch.erstellePaket ~= nil then
                paket = AOKassenbuch.erstellePaket(self.farmId)
            end
            if paket ~= nil then
                connection:sendEvent(AOKassenbuchEvent.new(false, self.farmId, paket))
            end
        end
    elseif empfaengerIstClient and self.paket ~= nil then
        AOKassenbuch.empfange(self.farmId, self.paket)
    end
end
