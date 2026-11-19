-- ReparaturOekonomieMain.lua
-- Haengt reparaturOekonomie an alle Fahrzeugtypen mit wearable und bringt die
-- Konsolenbefehle zum Testen mit (roStatus, roConfig, roReloadConfig).
-- OGW

ReparaturOekonomieMain = {}

ReparaturOekonomieMain.MOD_NAME = g_currentModName
ReparaturOekonomieMain.SPEC_NAME = "reparaturOekonomie"
ReparaturOekonomieMain.LOG = "[ReparaturOekonomie] "
ReparaturOekonomieMain.befehleRegistriert = false

function ReparaturOekonomieMain.erweitereFahrzeugtypen(typeManager)
    if typeManager == nil or typeManager.typeName ~= "vehicle" then
        return
    end

    local vollerName = string.format("%s.%s",
        tostring(ReparaturOekonomieMain.MOD_NAME), ReparaturOekonomieMain.SPEC_NAME)

    local anzahl = 0

    for typeName, typeEntry in pairs(typeManager:getTypes()) do
        if typeEntry ~= nil and typeEntry.specializationsByName ~= nil then
            -- Nur Typen mit Verschleiss, und nur einmal
            if typeEntry.specializationsByName["wearable"] ~= nil
                and typeEntry.specializationsByName[vollerName] == nil then

                if typeManager:addSpecialization(typeName, vollerName) then
                    anzahl = anzahl + 1
                end
            end
        end
    end

    Logging.info(ReparaturOekonomieMain.LOG .. "Spezialisierung an %d Fahrzeugtypen angehaengt.", anzahl)
end

if TypeManager ~= nil and TypeManager.validateTypes ~= nil then
    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes,
        ReparaturOekonomieMain.erweitereFahrzeugtypen)
else
    Logging.error(ReparaturOekonomieMain.LOG .. "TypeManager.validateTypes nicht gefunden - Mod bleibt wirkungslos.")
end

-- Konsole ---------------------------------------------------------------------

function ReparaturOekonomieMain.getFahrzeug()
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        local fahrzeug = g_localPlayer:getCurrentVehicle()
        if fahrzeug ~= nil then
            return fahrzeug
        end
    end

    if g_currentMission ~= nil and g_currentMission.controlledVehicle ~= nil then
        return g_currentMission.controlledVehicle
    end

    return nil
end

function ReparaturOekonomieMain.holeGeprueftesFahrzeug()
    local fahrzeug = ReparaturOekonomieMain.getFahrzeug()

    if fahrzeug == nil then
        return nil, "Kein Fahrzeug. Bitte einsteigen und den Befehl erneut ausfuehren."
    end

    if fahrzeug.roGetDaten == nil then
        return nil, "Die Mod greift bei diesem Fahrzeug nicht (keine Verschleiss-Spezialisierung)."
    end

    return fahrzeug, nil
end

function ReparaturOekonomieMain:consoleStatus()
    local fahrzeug, fehler = ReparaturOekonomieMain.holeGeprueftesFahrzeug()
    if fahrzeug == nil then
        return fehler
    end

    local cfg = ReparaturOekonomie.CFG
    local daten = fahrzeug:roGetDaten()
    local faktor = fahrzeug:roGetFaktor()
    local anteil, stufe, wert = fahrzeug:roGetBewertung()
    local stunden = ReparaturOekonomie.getStunden(fahrzeug)

    local neupreis = 0
    if fahrzeug.getPrice ~= nil then
        neupreis = fahrzeug:getPrice() or 0
    end
    local restwert = ReparaturOekonomie.getRestwert(fahrzeug, neupreis)
    local basis = cfg.bewertungNachRestwert and "Restwert" or "Neupreis"

    local klasse = ReparaturOekonomie.getKlasse(fahrzeug)
    local klasseTempo = ReparaturOekonomie.getKlasseTempo(fahrzeug)
    local klasseNeukauf = ReparaturOekonomie.getKlasseNeukauf(fahrzeug)

    local preis = 0
    if fahrzeug.getRepairPrice ~= nil then
        preis = fahrzeug:getRepairPrice() or 0
    end

    local schaden = 0
    if fahrzeug.getDamageAmount ~= nil then
        schaden = fahrzeug:getDamageAmount() or 0
    end

    local name = "?"
    if fahrzeug.getFullName ~= nil then
        local voll = fahrzeug:getFullName()
        if voll ~= nil then
            name = voll
        end
    end

    local stufenText = "ok"
    if stufe == 1 then
        stufenText = "teuer"
    elseif stufe == 2 then
        stufenText = "unwirtschaftlich"
    end

    local zeilen = {
        "=== ReparaturOekonomie ===========================",
        string.format("Fahrzeug            : %s", name),
        string.format("Neupreis            : %d", neupreis),
        string.format("Restwert (Alter+Bh) : %s", restwert ~= nil and string.format("%d", restwert) or "n/v"),
        string.format("Bewertungswert      : %d  (Basis: %s)", wert, basis),
        string.format("Klasse              : %s  (Tempo x%.2f, Neukauf x%.2f)", klasse, klasseTempo, klasseNeukauf),
        string.format("Betriebsstunden     : %.2f h  (Referenz %.0f h)", stunden, cfg.referenzStunden),
        string.format("Alter / Lebensdauer : %s / %s", tostring(fahrzeug.age), tostring(fahrzeug.lifetime)),
        string.format("Schaden             : %.1f %%", schaden * 100),
        string.format("Reparaturen         : %d", daten.anzahlReparaturen),
        string.format("Kosten gesamt       : %d", daten.kostenGesamt),
        "=== Rechenweg (Reparaturfaktor) ===",
        string.format("  Stundenanteil     : +%.3f", cfg.faktorStunden * math.min(stunden / math.max(cfg.referenzStunden, 1), 1)),
        string.format("  Historienanteil   : +%.3f", cfg.faktorProReparatur * daten.anzahlReparaturen),
        string.format("  Grundfaktor       : x%.2f", cfg.grundfaktorReparatur),
        string.format("  Gesamtfaktor      : x%.3f  (Deckel %.2f)", faktor, cfg.faktorMax),
        "=== Warnschwellen (bereits mit Klassenfaktor) ===",
        string.format("  Kostenanteil      : %.1f %%  (warnen %.0f %% / kritisch %.0f %%)",
            anteil * 100, cfg.warnAnteil * klasseNeukauf * 100, cfg.kritischAnteil * klasseNeukauf * 100),
        string.format("  Std-Backstop      : %s",
            (cfg.warnStunden > 0 or cfg.kritischStunden > 0)
                and string.format("warnen %.0f h / kritisch %.0f h", cfg.warnStunden * klasseNeukauf, cfg.kritischStunden * klasseNeukauf)
                or "aus"),
        string.format("  Untergrenze       : %s",
            (cfg.neukaufMindestNeupreis and cfg.neukaufMindestNeupreis > 0)
                and string.format("ab %d (%.0f %% Neupreis) - aktuell %s", cfg.neukaufMindestNeupreis * neupreis,
                    cfg.neukaufMindestNeupreis * 100,
                    (daten.kostenGesamt >= cfg.neukaufMindestNeupreis * neupreis) and "erreicht" or "NICHT erreicht -> bleibt ok")
                or "aus"),
        "=== Ergebnis ===",
        string.format("Reparaturpreis jetzt: %d", preis),
        string.format("Warnstufe           : %s", stufenText),
        "================================================="
    }

    return table.concat(zeilen, "\n")
end

function ReparaturOekonomieMain:consoleConfig(name, wert)
    local cfg = ReparaturOekonomie.CFG

    if name == nil then
        local zeilen = { "=== ReparaturOekonomie Konfiguration ===" }
        local namen = {}
        for k, _ in pairs(cfg) do
            table.insert(namen, k)
        end
        table.sort(namen)
        for _, k in ipairs(namen) do
            table.insert(zeilen, string.format("  %-22s = %s", k, tostring(cfg[k])))
        end
        table.insert(zeilen, "Aendern mit: roConfig <name> <wert>")
        return table.concat(zeilen, "\n")
    end

    if cfg[name] == nil then
        return string.format("Unbekannte Einstellung '%s'. Ohne Argumente aufrufen zeigt alle an.", tostring(name))
    end

    if wert == nil then
        return string.format("%s = %s", name, tostring(cfg[name]))
    end

    local neu
    if type(cfg[name]) == "boolean" then
        neu = (wert == "true" or wert == "1")
    else
        neu = tonumber(wert)
        if neu == nil then
            return string.format("'%s' ist keine Zahl.", tostring(wert))
        end
    end

    local alt = cfg[name]
    cfg[name] = neu

    -- speichern und im MP verteilen
    local hinweis = "gilt sofort"
    if ReparaturOekonomieSettings ~= nil and ReparaturOekonomieSettings.onLocalChange ~= nil then
        ReparaturOekonomieSettings.onLocalChange()
        hinweis = "gilt sofort, gespeichert und synchronisiert"
    end

    return string.format("%s: %s -> %s  (%s)",
        name, tostring(alt), tostring(neu), hinweis)
end

function ReparaturOekonomieMain:consoleReload()
    if ReparaturOekonomieSettings == nil or ReparaturOekonomieSettings.reload == nil then
        return "Einstellungs-Manager nicht bereit."
    end

    local ok, info = ReparaturOekonomieSettings.reload()
    if ok then
        return string.format("settings.xml neu geladen und synchronisiert.\nDatei: %s", tostring(info))
    else
        return tostring(info)
    end
end

function ReparaturOekonomieMain.registriereBefehle()
    if ReparaturOekonomieMain.befehleRegistriert then
        return
    end
    ReparaturOekonomieMain.befehleRegistriert = true

    if addConsoleCommand == nil then
        Logging.warning(ReparaturOekonomieMain.LOG .. "Konsolenbefehle nicht registriert: addConsoleCommand nicht verfuegbar")
        return
    end

    addConsoleCommand("roStatus", "Shows wear and cost values of the current vehicle",
        "consoleStatus", ReparaturOekonomieMain)
    addConsoleCommand("roConfig", "Shows or changes a mod setting",
        "consoleConfig", ReparaturOekonomieMain, "[name] [value]")
    addConsoleCommand("roReloadConfig", "Reloads settings.xml while the game is running",
        "consoleReload", ReparaturOekonomieMain)

    Logging.info(ReparaturOekonomieMain.LOG .. "Konsolenbefehle bereit: roStatus, roConfig, roReloadConfig")
end

ReparaturOekonomieMain.registriereBefehle()
