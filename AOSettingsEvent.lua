-- AOSettingsEvent.lua
-- Gleicht die Einstellungen aller Module zwischen Server und Clients ab.
-- hasData = false ist nur die Anfrage eines Clients. Aenderungen von Clients
-- nimmt der Server nur von Admins an.
-- OGW

AOSettingsEvent = {}
local AOSettingsEvent_mt = Class(AOSettingsEvent, Event)

InitEventClass(AOSettingsEvent, "AOSettingsEvent")

function AOSettingsEvent.emptyNew()
    return Event.new(AOSettingsEvent_mt)
end

function AOSettingsEvent.new(hasData)
    local self = AOSettingsEvent.emptyNew()
    self.hasData = (hasData == true)
    return self
end

function AOSettingsEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.hasData)

    if not self.hasData then
        return
    end

    -- Anzahl vorweg, damit der Empfaenger bei abweichender Liste sauber abbricht
    local eintraege = AOSettings.sortedKeys()
    streamWriteInt32(streamId, #eintraege)

    for _, eintrag in ipairs(eintraege) do
        local modul = AOSettings.getModul(eintrag.modulId)
        local cfg   = modul ~= nil and modul.getCfg() or nil

        -- Nicht "cfg and cfg[key] or nil" schreiben: bei false kaeme nil raus
        -- und der Stream verrutscht.
        local v = nil
        if cfg ~= nil then
            v = cfg[eintrag.key]
        end

        -- Typ-Bit vorweg, so bestimmt immer der Sender das Format
        local istBool = (type(v) == "boolean")
        streamWriteBool(streamId, istBool)

        if istBool then
            streamWriteBool(streamId, v)
        else
            streamWriteFloat32(streamId, tonumber(v) or 0)
        end
    end
end

-- Admin-Pruefung, laeuft auf dem Server
function AOSettingsEvent.istAdmin(connection)
    if g_currentMission == nil or g_currentMission.userManager == nil then
        return false
    end
    local benutzerVerwaltung = g_currentMission.userManager
    if benutzerVerwaltung.getUserByConnection == nil then
        return false
    end
    local benutzer = benutzerVerwaltung:getUserByConnection(connection)
    if benutzer == nil or benutzer.getIsMasterUser == nil then
        return false
    end
    return benutzer:getIsMasterUser() == true
end

function AOSettingsEvent:readStream(streamId, connection)
    self.hasData = streamReadBool(streamId)
    self.abgelehnt = false

    -- Server nimmt nur Admin-Werte an, Client immer die vom Server
    local empfaengerIstServer = not connection:getIsServer()
    local uebernehmen = true
    if self.hasData and empfaengerIstServer then
        uebernehmen = AOSettingsEvent.istAdmin(connection)
        self.abgelehnt = not uebernehmen
    end

    if self.hasData then
        local anzahl    = streamReadInt32(streamId)
        local eintraege = AOSettings.sortedKeys()

        if anzahl ~= #eintraege then
            Logging.warning("[AgrarOekonomie] Einstellungs-Sync verworfen: Sender hat %d Werte, " ..
                "Empfaenger erwartet %d. Laeuft auf Server und Client dieselbe Mod-Version?",
                anzahl, #eintraege)
            return
        end

        for _, eintrag in ipairs(eintraege) do
            local modul = AOSettings.getModul(eintrag.modulId)
            local cfg   = modul ~= nil and modul.getCfg() or nil

            -- abgelehnte Werte trotzdem komplett lesen, sonst stimmt der Stream nicht
            local istBool = streamReadBool(streamId)

            if istBool then
                local b = streamReadBool(streamId)
                if uebernehmen and cfg ~= nil and cfg[eintrag.key] ~= nil then
                    cfg[eintrag.key] = b
                end
            else
                local v = streamReadFloat32(streamId)
                if uebernehmen then
                    AOSettings.applyValue(eintrag.modulId, eintrag.key, v)
                end
            end
        end
    end

    self:run(connection)
end

function AOSettingsEvent:run(connection)
    -- true = wir sind Client
    local empfaengerIstClient = connection:getIsServer()

    if self.hasData then
        if not empfaengerIstClient then
            if self.abgelehnt then
                -- kein Admin: gueltige Werte zurueck, damit sein Menue wieder stimmt
                Logging.info("[AgrarOekonomie] Einstellungsaenderung eines Spielers ohne " ..
                    "Admin-Rechte abgelehnt.")
                connection:sendEvent(AOSettingsEvent.new(true))
            else
                -- speichern und an alle verteilen
                AOSettings.onServerReceivedChange()
            end
        end
    else
        -- Anfrage, nur der Server antwortet
        if not empfaengerIstClient and g_server ~= nil then
            connection:sendEvent(AOSettingsEvent.new(true))
        end
    end
end
