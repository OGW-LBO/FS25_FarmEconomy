-- AOMod.lua
-- Einstieg fuer den Einstellungs-Tab. Die Skripte selbst laedt die modDesc,
-- hier wird nur der Tab angestossen, sobald der Spieler in der Welt ist.
-- OGW

AOMod = {}

AOMod.LOG          = "[AgrarOekonomie] "
AOMod.versuche     = 0
AOMod.MAX_VERSUCHE = 60      -- ~60 Frames Nachlauf, falls das Menue spaet kommt

function AOMod.initSeite()
    if AOMenuPage == nil then
        return
    end

    if g_AOMenuPage == nil then
        g_AOMenuPage = AOMenuPage.new()
    end

    if g_AOMenuPage ~= nil and g_AOMenuPage.registerAndInject ~= nil then
        g_AOMenuPage:registerAndInject()
    end

    -- Jahresvergleich zeigt FS25_FarmOverview unter Finanzen, kein eigener Reiter
end

function AOMod:loadMap(name)
    if g_dedicatedServer ~= nil then
        Logging.info(AOMod.LOG .. "Dedicated Server erkannt - Einstellungs-Tab wird nicht gebaut.")
        return
    end

    if g_messageCenter ~= nil and MessageType ~= nil and MessageType.OWN_PLAYER_ENTERED ~= nil then
        g_messageCenter:subscribeOneshot(MessageType.OWN_PLAYER_ENTERED, function()
            AOMod.initSeite()
        end, nil)
    else
        AOMod.initSeite()
    end
end

-- falls das Menue beim ersten Mal noch nicht da war
function AOMod:update(dt)
    if g_dedicatedServer ~= nil then
        return
    end
    if g_AOMenuPage ~= nil and g_AOMenuPage.injiziert then
        return
    end
    if AOMod.versuche >= AOMod.MAX_VERSUCHE then
        return
    end

    AOMod.versuche = AOMod.versuche + 1
    AOMod.initSeite()
end

addModEventListener(AOMod)
