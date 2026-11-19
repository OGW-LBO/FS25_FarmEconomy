-- AgrarOekonomie.lua
-- Kern: Konfiguration der neuen Module, Geld-Hook fuer Verkaufspreise und
-- Einnahmen. Steuern laufen ueber vormerken(), dort sitzt die Bremse.
-- Die Preise haengen an der Finanzkategorie, nicht an Fruchtlisten - geht so auf jeder Map.
-- OGW

AgrarOekonomie = {}

AgrarOekonomie.LOG      = "[AgrarOekonomie] "
AgrarOekonomie.MOD_NAME = "AgrarOekonomie"

-- Die Altmodule bringen eigene CFG-Tabellen mit, die registriert AOSettings.
AgrarOekonomie.CFG = {
    -- Verkaufspreise ----------------------------------------------------
    -- Faktor auf den Erloes, 1.0 = unveraendert
    preiseAktiv        = true,
    preisFruechte      = 0.75,   -- Feldfruechte (harvestIncome)
    preisProdukte      = 0.75,   -- Produktionserzeugnisse (soldProducts)

    -- Grundsteuer -------------------------------------------------------
    grundsteuerAktiv   = false,
    grundsteuerProJahr = 0.02,   -- Anteil vom Landwert

    -- Sicherheitsbremse fuer alle Abbuchungen der Mod -------------------
    bremseAktiv        = true,
    bremseAnteil       = 0.25,     -- max. Anteil der Tageseinnahmen pro Spieltag
    bremseFenster      = 5,        -- Tage, ueber die die Einnahmen gemittelt werden
    notbremseKonto     = 50000,    -- darunter wird gar nicht mehr abgebucht
    -- vehicle.age zaehlt Monate, nicht Tage
    karenzMonate       = 3,        -- so viele Spielmonate sind Neufahrzeuge steuerfrei

    -- Bindegarn / Netz / Folie ------------------------------------------
    -- Leih- und Auftragsmaschinen ausnehmen: nachgekauftes Garn bleibt bei der Rueckgabe drin.
    verbrauchNurEigene = true,
    verbrauchBindegarn = 5.0,
    verbrauchNetz      = 5.0,
    verbrauchFolie     = 3.0,

    -- Spritverbrauch (DieselVerbrauch.lua) ------------------------------
    dieselAktiv        = false,    -- ab Werk aus, damit nichts ungefragt anders wird
    dieselFaktor       = 1.0,      -- ersetzt die Stufe des Spiels (bei der Arbeit)
    dieselFaktorFahrt  = 1.0,      -- dasselbe fuer Fahrten ohne Arbeit
    dieselProKwh       = 0.0,      -- Liter je kWh Nennleistung; 0 = Wert aus der Datei
    dieselLastkurve    = false,    -- eigene Lastkurve mit Wirkungsgrad
    dieselAnzeige      = true,     -- Verbrauch am Tacho (nur bei aktivem Modul)

    -- Guthabenzins (AOZins.lua) -----------------------------------------
    -- voller Satz bis Grenze 1, halber bis Grenze 2, darueber nichts
    zinsAktiv          = false,
    zinsSatz           = 0.02,     -- pro Jahr
    zinsGrenze1        = 500000,
    zinsGrenze2        = 2000000,

    -- Produktionsgeschwindigkeit (AOProduktion.lua) ---------------------
    prodAktiv          = false,
    prodFaktor         = 1.0,
    prodKosten         = 2,        -- laufende Kosten: 0 gleich, 1 Wurzel des Faktors, 2 voll mit

    -- Automatik (AOAutomatik.lua) ---------------------------------------
    -- stellt die Preisfaktoren einmal im Jahr auf den Ziel-Erloes je Hektar nach
    autoAktiv          = true,
    autoStufe          = 1,        -- 0 Leicht, 1 Normal, 2 Schwer, 3 Realistisch, 4 Eigene
    autoZielMin        = 2000,     -- EUR je Feldhektar/Jahr, nur bei Stufe Eigene
    autoZielMax        = 2700,
    autoSchritt        = 0.05,     -- groesste Faktor-Aenderung pro Jahr
    -- nur Anzeige, kommt vom Server
    autoLetzteBilanz   = -1,       -- EUR/ha nach Faktor, -1 = noch keine Bilanz
    autoLetzterFaktor  = -1,
    autoPerioden       = 0,        -- abgeschlossene Monate im laufenden Messjahr

    -- Kassenbuch (AOKassenbuch.lua) ------------------------------------
    -- Buchungen unter der Schwelle laufen in die Tagessumme ihrer Kategorie
    buchAktiv          = true,
    buchSchwelle       = 50,

    meldungen          = true,
    debug              = false,
}

-- Laufzeitzustand, wird weder gespeichert noch synchronisiert
AgrarOekonomie.einnahmen   = {}      -- [farmId] = { heute, lastDay, tage = {} }
AgrarOekonomie.abgebucht   = {}      -- [farmId] = Betrag, den die Mod heute schon nahm
AgrarOekonomie.hooksGesetzt = false
AgrarOekonomie.karenzHinweis = false

function AgrarOekonomie.istServer()
    if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil then
        return g_currentMission:getIsServer() == true
    end
    return g_server ~= nil
end

function AgrarOekonomie.getTag()
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        local d = g_currentMission.environment.currentDay
        if type(d) == "number" then
            return d
        end
    end
    return 0
end

function AgrarOekonomie.getFarmGeld(farmId)
    local geld = nil
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if type(farm) == "table" and type(farm.money) == "number" then
            geld = farm.money
        end
    end
    return geld
end

function AgrarOekonomie.formatGeld(betrag)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local txt = g_i18n:formatMoney(betrag, 0, true, true)
        if type(txt) == "string" then
            return txt
        end
    end
    return string.format("%d", math.floor((betrag or 0) + 0.5))
end

-- Nur Farmen mit Spielern belasten. NPC-Farms anderer Mods (NachbarFelder z.B.) bleiben aussen vor.
function AgrarOekonomie.istSpielerFarm(farmId)
    if farmId == nil or farmId <= 0 then
        return false
    end
    if FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID ~= nil
            and farmId == FarmManager.SPECTATOR_FARM_ID then
        return false
    end

    if g_farmManager == nil or g_farmManager.getFarmById == nil then
        return true
    end
    -- MP-Spielstand im SP: Farmen sind zusammengelegt, Fahrzeuge haben noch die alte farmId
    local farm = g_farmManager:getFarmById(farmId)
    if type(farm) ~= "table" then
        return false
    end

    -- ohne Spielerliste lieber true als jemanden zu verschonen
    local listeGefunden = false
    for _, feld in ipairs({ "players", "userIds", "activeUsers" }) do
        local liste = farm[feld]
        if type(liste) == "table" then
            listeGefunden = true
            if next(liste) ~= nil then
                return true
            end
        end
    end
    return not listeGefunden
end

-- MoneyType ist meist eine Tabelle mit .statistic, sonst Konstantenname suchen
function AgrarOekonomie.getStatistik(moneyType)
    if type(moneyType) == "table" and type(moneyType.statistic) == "string" then
        return moneyType.statistic
    end
    if MoneyType ~= nil then
        for k, v in pairs(MoneyType) do
            if v == moneyType and type(k) == "string" then
                return k
            end
        end
    end
    return nil
end

-- Einnahmen (Grundlage fuer die Bremse) -------------------------------------

function AgrarOekonomie.getEinnahmenDaten(farmId)
    local d = AgrarOekonomie.einnahmen[farmId]
    if d == nil then
        d = { heute = 0, lastDay = AgrarOekonomie.getTag(), tage = {} }
        AgrarOekonomie.einnahmen[farmId] = d
    end
    return d
end

function AgrarOekonomie.tageswechselPruefen(farmId)
    local d      = AgrarOekonomie.getEinnahmenDaten(farmId)
    local curDay = AgrarOekonomie.getTag()

    if curDay == d.lastDay then
        return
    end

    local fenster = math.max(1, math.floor(AgrarOekonomie.CFG.bremseFenster or 5))
    table.insert(d.tage, d.heute)
    while #d.tage > fenster do
        table.remove(d.tage, 1)
    end

    d.heute   = 0
    d.lastDay = curDay
    AgrarOekonomie.abgebucht[farmId] = 0
end

function AgrarOekonomie.merkeEinnahme(farmId, betrag)
    if not AgrarOekonomie.istSpielerFarm(farmId) or betrag == nil or betrag <= 0 then
        return
    end
    AgrarOekonomie.tageswechselPruefen(farmId)
    local d = AgrarOekonomie.getEinnahmenDaten(farmId)
    d.heute = d.heute + betrag
end

-- Ohne volle Tage zaehlt der laufende Tag, sonst blockiert die Bremse direkt nach dem Start.
function AgrarOekonomie.getTagesEinnahmen(farmId)
    local d = AgrarOekonomie.getEinnahmenDaten(farmId)

    local summe, anzahl = 0, 0
    for _, wert in ipairs(d.tage) do
        summe  = summe + wert
        anzahl = anzahl + 1
    end

    if anzahl == 0 then
        return d.heute
    end
    return summe / anzahl
end

-- Abbuchung -----------------------------------------------------------------

-- Grundsteuer und Fuhrparksteuer rechnen am selben Monatswechsel ab. Frueher
-- nahm sich, wer zuerst buchte, das ganze Tagesbudget. Jetzt wird erst
-- gesammelt und dann anteilig nach Forderung verteilt.
AgrarOekonomie.warteschlange  = {}   -- { farmId, betrag, moneyType, quelle, fertig }
AgrarOekonomie.schlangeFrisch = false
AgrarOekonomie.letzteKappung  = {}   -- [farmId] = { tag, gewollt, echt, grund }

-- Wie viel von "gewollt" heute noch abgebucht werden darf, und warum weniger.
function AgrarOekonomie.getSpielraum(farmId, gewollt)
    local cfg = AgrarOekonomie.CFG
    if not cfg.bremseAktiv then
        return gewollt, nil
    end

    local frei, grund = gewollt, nil

    -- Deckel: pro Spieltag nur ein Anteil der mittleren Einnahmen
    local schnitt = AgrarOekonomie.getTagesEinnahmen(farmId)
    if schnitt > 0 then
        local budget = schnitt * math.max(0, cfg.bremseAnteil or 0.25)
        local rest   = math.max(0, budget - (AgrarOekonomie.abgebucht[farmId] or 0))
        if rest < frei then
            frei, grund = rest, "deckel"
        end
    end

    -- Notbremse: nicht unter den Mindestkontostand
    local geld = AgrarOekonomie.getFarmGeld(farmId)
    if geld ~= nil then
        local spielraum = math.max(0, geld - (cfg.notbremseKonto or 0))
        if spielraum < frei then
            frei, grund = spielraum, "notbremse"
        end
    end

    return frei, grund
end

-- fertig(echt, gewollt) wird nach der Verteilung gerufen, auch mit echt = 0.
function AgrarOekonomie.vormerken(farmId, betrag, moneyType, quelle, fertig)
    if not AgrarOekonomie.istServer()
            or betrag == nil or betrag <= 0
            or not AgrarOekonomie.istSpielerFarm(farmId)
            or g_currentMission == nil or g_currentMission.addMoney == nil then
        if fertig ~= nil then
            fertig(0, betrag or 0)
        end
        return
    end
    table.insert(AgrarOekonomie.warteschlange, {
        farmId = farmId, betrag = betrag, moneyType = moneyType, quelle = quelle, fertig = fertig,
    })
    AgrarOekonomie.schlangeFrisch = true
end

function AgrarOekonomie.verteile()
    local schlange = AgrarOekonomie.warteschlange
    AgrarOekonomie.warteschlange = {}

    local proFarm, reihenfolge = {}, {}
    for _, p in ipairs(schlange) do
        local f = proFarm[p.farmId]
        if f == nil then
            f = { summe = 0, posten = {} }
            proFarm[p.farmId] = f
            table.insert(reihenfolge, p.farmId)
        end
        f.summe = f.summe + p.betrag
        table.insert(f.posten, p)
    end

    for _, farmId in ipairs(reihenfolge) do
        local f = proFarm[farmId]
        AgrarOekonomie.tageswechselPruefen(farmId)
        local frei, grund = AgrarOekonomie.getSpielraum(farmId, f.summe)
        local quote = (frei >= f.summe) and 1 or (frei / f.summe)

        local gebucht, teile = 0, {}
        for _, p in ipairs(f.posten) do
            local echt = p.betrag * quote
            if echt > 0 then
                -- das Kassenbuch fuehrt die Steuer dann als eigene Zeile
                if AOKassenbuch ~= nil then
                    AOKassenbuch.quelle = p.quelle
                end
                g_currentMission:addMoney(-echt, farmId, p.moneyType, true, true)
                if AOKassenbuch ~= nil then
                    AOKassenbuch.quelle = nil
                end
                gebucht = gebucht + echt
            end
            table.insert(teile, string.format("%s %s/%s", tostring(p.quelle),
                AgrarOekonomie.formatGeld(echt), AgrarOekonomie.formatGeld(p.betrag)))
            if p.fertig ~= nil then
                p.fertig(echt, p.betrag)
            end
        end
        AgrarOekonomie.abgebucht[farmId] = (AgrarOekonomie.abgebucht[farmId] or 0) + gebucht

        if quote < 1 then
            AgrarOekonomie.letzteKappung[farmId] = {
                tag = AgrarOekonomie.getTag(), gewollt = f.summe, echt = gebucht, grund = grund,
            }
            Logging.info(AgrarOekonomie.LOG .. "Bremse (%s) Farm %s: %s statt %s abgebucht (%s).",
                tostring(grund), tostring(farmId), AgrarOekonomie.formatGeld(gebucht),
                AgrarOekonomie.formatGeld(f.summe), table.concat(teile, ", "))
            AgrarOekonomie.meldeKappung(farmId, f.summe - gebucht, grund)
        end
    end
end

function AgrarOekonomie.meldeKappung(farmId, erlassen, grund)
    if not AgrarOekonomie.CFG.meldungen or AONotifyEvent == nil or erlassen < 1 then
        return
    end
    local key  = (grund == "notbremse") and "ao_msg_bremseKonto" or "ao_msg_bremseDeckel"
    local text = string.format("@%s|g:%.0f", key, erlassen)
    if g_server ~= nil and g_server.broadcastEvent ~= nil then
        g_server:broadcastEvent(AONotifyEvent.new(farmId, text), false)
    end
    AONotifyEvent.zeigeLokal(farmId, text)
end

-- Verteilt wird erst, wenn ein ganzer Durchlauf ohne neue Posten vergangen
-- ist. Die Steuern haengen an verschiedenen update-Schleifen, deren
-- Reihenfolge nicht feststeht.
function AgrarOekonomie:update(dt)
    if #AgrarOekonomie.warteschlange == 0 then
        return
    end
    if AgrarOekonomie.schlangeFrisch then
        AgrarOekonomie.schlangeFrisch = false
        return
    end
    AgrarOekonomie.verteile()
end

-- Verkaufspreise ------------------------------------------------------------

-- Tierprodukte, BGA, Holz, Ballen, Missionen usw. bleiben absichtlich draussen.
AgrarOekonomie.PREIS_KATEGORIEN = {
    harvestIncome = "preisFruechte",
    soldProducts  = "preisProdukte",
}

-- nil = Buchung nicht anfassen
function AgrarOekonomie.getPreisFaktor(moneyType)
    if not AgrarOekonomie.CFG.preiseAktiv then
        return nil
    end

    local statistik = AgrarOekonomie.getStatistik(moneyType)
    if statistik == nil then
        return nil
    end

    local schluessel = AgrarOekonomie.PREIS_KATEGORIEN[statistik]
    if schluessel == nil then
        return nil
    end

    local faktor = AgrarOekonomie.CFG[schluessel]
    if type(faktor) ~= "number" or faktor < 0 or faktor == 1.0 then
        return nil
    end
    return faktor
end

function AgrarOekonomie.installiereHooks()
    if AgrarOekonomie.hooksGesetzt then
        return
    end

    if FSBaseMission == nil or FSBaseMission.addMoney == nil then
        Logging.warning(AgrarOekonomie.LOG ..
            "FSBaseMission.addMoney nicht gefunden - Preise und Bremse inaktiv.")
        return
    end

    FSBaseMission.addMoney = Utils.overwrittenFunction(FSBaseMission.addMoney,
        function(mission, superFunc, amount, farmId, moneyType, ...)
            -- nur auf dem Server, sonst kuerzt der Client nochmal und der Faktor wirkt doppelt
            if AgrarOekonomie.istServer()
                    and amount ~= nil and amount > 0
                    and AgrarOekonomie.istSpielerFarm(farmId) then
                -- Automatik braucht den Erloes vor dem Faktor
                if AOAutomatik ~= nil and AOAutomatik.merkeErloes ~= nil then
                    AOAutomatik.merkeErloes(moneyType, amount)
                end
                local faktor = AgrarOekonomie.getPreisFaktor(moneyType)
                if faktor ~= nil then
                    if AgrarOekonomie.CFG.debug then
                        Logging.info(AgrarOekonomie.LOG ..
                            "Preis: %s %.2f -> %.2f (Farm %s)",
                            tostring(AgrarOekonomie.getStatistik(moneyType)),
                            amount, amount * faktor, tostring(farmId))
                    end
                    amount = amount * faktor
                end
                -- Zinsen zaehlen nicht als Einnahme, sonst hebt ein volles Konto das Bremsbudget
                if AOZins == nil or not AOZins.inGutschrift then
                    AgrarOekonomie.merkeEinnahme(farmId, amount)
                end
            end
            -- Bericht und Kassenbuch bekommen den Betrag nach dem Preisfaktor
            if amount ~= nil and AgrarOekonomie.istServer() then
                if AOBericht ~= nil and AOBericht.buche ~= nil then
                    AOBericht.buche(farmId, moneyType, amount)
                end
                if AOKassenbuch ~= nil and AOKassenbuch.buche ~= nil then
                    AOKassenbuch.buche(farmId, moneyType, amount)
                end
            end
            return superFunc(mission, amount, farmId, moneyType, ...)
        end)

    AgrarOekonomie.hooksGesetzt = true
    Logging.info(AgrarOekonomie.LOG .. "Geld-Hook installiert.")
end

-- Konsolenbefehle -----------------------------------------------------------

-- addConsoleCommand uebergibt zuerst das Zielobjekt, daher der Platzhalter _.
function AgrarOekonomie.befehlStatus(_)
    local cfg   = AgrarOekonomie.CFG
    local zeilen = {
        AgrarOekonomie.LOG .. "Status:",
        string.format("  Preise: aktiv=%s  Fruechte=%.2f  Produkte=%.2f",
            tostring(cfg.preiseAktiv), cfg.preisFruechte, cfg.preisProdukte),
        string.format("  Grundsteuer: aktiv=%s  Satz=%.3f/Jahr",
            tostring(cfg.grundsteuerAktiv), cfg.grundsteuerProJahr),
        string.format("  Bremse: aktiv=%s  Anteil=%.2f  Fenster=%d Tage  Notbremse=%s  Karenz=%d Monate",
            tostring(cfg.bremseAktiv), cfg.bremseAnteil, math.floor(cfg.bremseFenster),
            AgrarOekonomie.formatGeld(cfg.notbremseKonto), math.floor(cfg.karenzMonate)),
        string.format("  Verbrauch: Bindegarn=%.1fx  Netz=%.1fx  Folie=%.1fx",
            cfg.verbrauchBindegarn, cfg.verbrauchNetz, cfg.verbrauchFolie),
    }

    if AOAutomatik ~= nil and AOAutomatik.getStatusZeile ~= nil then
        local zeile = AOAutomatik.getStatusZeile()
        if type(zeile) == "string" then
            table.insert(zeilen, zeile)
        end
    end

    for farmId, _ in pairs(AgrarOekonomie.einnahmen) do
        table.insert(zeilen, string.format(
            "  Farm %s: Tageseinnahmen (Mittel) %s, heute von der Mod abgebucht %s",
            tostring(farmId),
            AgrarOekonomie.formatGeld(AgrarOekonomie.getTagesEinnahmen(farmId)),
            AgrarOekonomie.formatGeld(AgrarOekonomie.abgebucht[farmId] or 0)))
        local k = AgrarOekonomie.letzteKappung[farmId]
        if k ~= nil then
            table.insert(zeilen, string.format(
                "    zuletzt gekuerzt an Tag %d (%s): %s statt %s",
                k.tag, tostring(k.grund), AgrarOekonomie.formatGeld(k.echt),
                AgrarOekonomie.formatGeld(k.gewollt)))
        end
    end

    if AOZins ~= nil and AOZins.statusZeile ~= nil then
        table.insert(zeilen, AOZins.statusZeile())
        for farmId, z in pairs(AOZins.letzte) do
            table.insert(zeilen, string.format("    Farm %s: zuletzt %s auf %s",
                tostring(farmId), AgrarOekonomie.formatGeld(z.zins), AgrarOekonomie.formatGeld(z.basis)))
        end
    end
    if AOProduktion ~= nil and AOProduktion.statusZeilen ~= nil then
        for _, zeile in ipairs(AOProduktion.statusZeilen()) do
            table.insert(zeilen, zeile)
        end
    end

    return table.concat(zeilen, "\n")
end

function AgrarOekonomie.befehlConfig(_, name, wert)
    if name == nil or wert == nil then
        return AgrarOekonomie.LOG .. "Aufruf: aoConfig <Name> <Wert>"
    end
    if AOSettings == nil or AOSettings.setzeWert == nil then
        return AgrarOekonomie.LOG .. "Einstellungen noch nicht bereit."
    end

    -- nicht still umleiten, der alte Wert war in Tagen
    if name == "karenzTage" or name == "ao.karenzTage" then
        return AgrarOekonomie.LOG ..
            "karenzTage gibt es nicht mehr - bitte aoConfig karenzMonate <0-24> (Spielmonate)."
    end

    local ok, meldung = AOSettings.setzeWert(name, wert)
    return AgrarOekonomie.LOG .. tostring(meldung)
end

function AgrarOekonomie.befehlReload(_)
    if AOSettings == nil or AOSettings.reload == nil then
        return AgrarOekonomie.LOG .. "Einstellungen noch nicht bereit."
    end
    local ok, info = AOSettings.reload()
    if ok then
        return AgrarOekonomie.LOG .. "Einstellungen neu geladen: " .. tostring(info)
    end
    return AgrarOekonomie.LOG .. tostring(info)
end

function AgrarOekonomie:loadMap(name)
    AgrarOekonomie.installiereHooks()

    if addConsoleCommand ~= nil then
        addConsoleCommand("aoStatus", "Zeigt den Status der Agrar-Oekonomie.",
            "befehlStatus", AgrarOekonomie)
        addConsoleCommand("aoConfig", "Setzt einen Einstellungswert: aoConfig <Name> <Wert>.",
            "befehlConfig", AgrarOekonomie)
        addConsoleCommand("aoReload", "Laedt die settings.xml neu (nur Server).",
            "befehlReload", AgrarOekonomie)
    end

    Logging.info(AgrarOekonomie.LOG .. "Kern bereit (Server=%s).",
        tostring(AgrarOekonomie.istServer()))
end

addModEventListener(AgrarOekonomie)
