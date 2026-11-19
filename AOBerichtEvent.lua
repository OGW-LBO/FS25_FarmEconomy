-- AOBerichtEvent.lua
-- Client fragt die Zahlen der Betriebsuebersicht an, der Server schickt das
-- Paket aus AOBericht.erstellePaket zurueck.
-- OGW

AOBerichtEvent = {}
local AOBerichtEvent_mt = Class(AOBerichtEvent, Event)

InitEventClass(AOBerichtEvent, "AOBerichtEvent")

function AOBerichtEvent.emptyNew()
    return Event.new(AOBerichtEvent_mt)
end

function AOBerichtEvent.new(anfrage, farmId, paket)
    local self = AOBerichtEvent.emptyNew()
    self.anfrage = (anfrage == true)
    self.farmId  = farmId or 0
    self.paket   = paket
    return self
end

function AOBerichtEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.anfrage)
    streamWriteInt32(streamId, self.farmId)
    if self.anfrage then
        return
    end

    local p = self.paket
    streamWriteInt32(streamId, p.von)
    streamWriteInt32(streamId, p.bis)
    streamWriteBool(streamId, p.vergleich == true)
    streamWriteBool(streamId, p.standVergleich == true)

    streamWriteInt32(streamId, #p.gruppen)
    for _, g in ipairs(p.gruppen) do
        streamWriteFloat32(streamId, g.jetzt or 0)
        streamWriteFloat32(streamId, g.vorjahr or 0)
    end

    streamWriteInt32(streamId, #p.stand)
    for i = 1, #p.stand do
        streamWriteFloat32(streamId, p.stand[i] or 0)
        streamWriteFloat32(streamId, p.standVorjahr[i] or 0)
    end
end

function AOBerichtEvent:readStream(streamId, connection)
    self.anfrage = streamReadBool(streamId)
    self.farmId  = streamReadInt32(streamId)

    if not self.anfrage then
        local p = {
            gruppen = {}, stand = {}, standVorjahr = {},
        }
        p.von            = streamReadInt32(streamId)
        p.bis            = streamReadInt32(streamId)
        p.vergleich      = streamReadBool(streamId)
        p.standVergleich = streamReadBool(streamId)

        local anzahlGruppen = streamReadInt32(streamId)
        for i = 1, anzahlGruppen do
            p.gruppen[i] = {
                jetzt   = streamReadFloat32(streamId),
                vorjahr = streamReadFloat32(streamId),
            }
        end

        local anzahlStand = streamReadInt32(streamId)
        for i = 1, anzahlStand do
            p.stand[i]        = streamReadFloat32(streamId)
            p.standVorjahr[i] = streamReadFloat32(streamId)
        end

        -- bei falscher Anzahl ist trotzdem alles gelesen, nur verworfen
        if anzahlGruppen == #AOBericht.GRUPPEN and anzahlStand == #AOBericht.STAND then
            self.paket = p
        else
            Logging.warning("[AgrarOekonomie] Betriebsuebersicht verworfen: Server sendet %d/%d Werte, " ..
                "erwartet %d/%d. Laeuft auf Server und Client dieselbe Mod-Version?",
                anzahlGruppen, anzahlStand, #AOBericht.GRUPPEN, #AOBericht.STAND)
        end
    end

    self:run(connection)
end

function AOBerichtEvent:run(connection)
    -- getIsServer() == true heisst: wir sind der Client
    local empfaengerIstClient = connection:getIsServer()

    if self.anfrage then
        if not empfaengerIstClient and self.farmId > 0 then
            local paket = nil
            if AOBericht ~= nil and AOBericht.erstellePaket ~= nil then
                paket = AOBericht.erstellePaket(self.farmId)
            end
            if paket ~= nil then
                connection:sendEvent(AOBerichtEvent.new(false, self.farmId, paket))
            else
                Logging.warning("[AgrarOekonomie] Betriebsuebersicht fuer Farm %d: %s",
                    self.farmId, "kein Paket erstellt")
            end
        end
    elseif empfaengerIstClient and self.paket ~= nil then
        AOBericht.empfange(self.farmId, self.paket)
    end
end
