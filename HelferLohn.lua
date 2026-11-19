-- HelferLohn.lua
-- Lohnstufen und Arbeitsmarkt fuer den Helfer: beim Anheuern wird gewuerfelt,
-- ob zu dem Lohn ueberhaupt jemand kommt. Der Spiel-Lohn (MoneyType.AI) wird
-- skaliert bzw. im Festpreis-Modus durch einen Betrag am Auftragsende ersetzt.
-- OGW

HelferLohn = {}

HelferLohn.LOG = "[HelferLohn] "
HelferLohn.MOD_NAME = g_currentModName
HelferLohn.modDir = g_currentModDirectory

HelferLohn.DIALOG_NAME    = "HelferLohnDialogUI"
HelferLohn.DIALOG_XML     = "gui/HelferLohnDialog.xml"
HelferLohn.dialogLoaded   = false
HelferLohn.toggleRegistered = false

HelferLohn.MODUS_STUNDENLOHN = 0
HelferLohn.MODUS_FESTPREIS    = 1

HelferLohn.STUFE_AZUBI       = 0
HelferLohn.STUFE_QUER        = 1
HelferLohn.STUFE_AUSGELERNT  = 2
HelferLohn.STUFE_EIGEN       = 3

-- Preisniveau nur fuer die Festpreise, der Stundenlohn haengt eh am Spiel-Lohn
HelferLohn.SCHWER_AUTO   = 0
HelferLohn.SCHWER_LEICHT = 1
HelferLohn.SCHWER_NORMAL = 2
HelferLohn.SCHWER_SCHWER = 3
HelferLohn.SCHWER_EIGEN  = 4

-- Festpreise fuer "Normal"
HelferLohn.PREIS_BASIS = {
    festLohn       = 500,
    festMarktBasis = 400,
    preisLeicht    = 200,
    preisMittel    = 350,
    preisBoden     = 450,
    preisPressen   = 350,
    preisDreschen  = 650,
    preisHaeckseln = 750,
}
-- 1 leicht, 2 normal, 3 schwer
HelferLohn.SCHWER_FAKTOR = { [1] = 0.6, [2] = 1.0, [3] = 1.6 }

-- Einstellungen, werden per Settings-Event gesynct - daher nur Zahlen und Booleans
HelferLohn.CFG = {
    aktiv               = true,

    bezahlModus         = 0,     -- 0 Stundenlohn, 1 Festpreis pro Auftrag
    lohnStufe           = 1,     -- 0 Azubi, 1 Quereinsteiger, 2 Ausgelernter, 3 Eigen

    -- Faktoren auf den normalen Spiel-Lohn
    faktorAzubi         = 0.6,
    faktorQuer          = 1.0,
    faktorAusgelernt    = 1.6,
    faktorEigen         = 1.0,

    -- 0 Auto, 1 leicht, 2 normal, 3 schwer, 4 eigen (Preis von Hand geaendert)
    schwierigkeit       = 0,

    festLohn            = 500,

    zufallVerfuegbar    = true,

    -- Forderung des Helfers schwankt zwischen diesen Faktoren
    marktMin            = 0.4,
    marktMax            = 1.3,

    festMarktBasis      = 400,   -- wenn die Aufgabe nicht erkannt wird

    -- Fair-Preise je Aufgabe, darunter sagt der Helfer oft ab
    preisLeicht         = 200,   -- Maehen, Schwaden, Wenden
    preisMittel         = 350,   -- Saeen, Duengen, Spritzen, Walzen
    preisBoden          = 450,   -- Pfluegen, Grubbern, Mulchen, Steine
    preisPressen        = 350,   -- Ballen pressen/wickeln
    preisDreschen       = 650,
    preisHaeckseln      = 750,   -- auch Holzernte

    meldung             = true,

    -- Sprit und Betriebsmittel kosten nichts, solange der Helfer arbeitet
    gratisBetrieb       = true,

    -- Festpreis nur bei fertigem Auftrag, sonst zahlt man beim Neu-Anheuern
    -- eines haengenden Helfers jedes Mal den vollen Preis
    nurBeiErfolg        = true,
}

HelferLohn.bereit           = false
HelferLohn.hooksInstalliert = false
HelferLohn.befehleRegistriert = false
HelferLohn.moneyTypeCached  = nil
HelferLohn.moneyTypeGewarnt = false
HelferLohn.debug            = false  -- loggt alle Geldabgaenge

HelferLohn.trackedJobs        = {}   -- [job] = { farmId=, price=, fixed= }
HelferLohn.fixedActiveByFarm  = {}
HelferLohn.activeAIByFarm     = {}
HelferLohn.inFixedPayment     = false -- eigene Zahlung nicht selbst abfangen

-- Erkennung am angebauten Geraet, die erste passende Zeile gewinnt (teuerste oben)
HelferLohn.TASK_CATS = {
    { key = "haeckseln", cfg = "preisHaeckseln", l10n = "hl_taskHaeckseln",
      specs = { "spec_forageWagon", "spec_woodHarvester" } },
    { key = "dreschen",  cfg = "preisDreschen",  l10n = "hl_taskDreschen",
      specs = { "spec_combine" } },
    { key = "boden",     cfg = "preisBoden",     l10n = "hl_taskBoden",
      specs = { "spec_plow", "spec_cultivator", "spec_mulcher", "spec_stonePicker" } },
    { key = "pressen",   cfg = "preisPressen",   l10n = "hl_taskPressen",
      specs = { "spec_baler", "spec_baleWrapper" } },
    { key = "mittel",    cfg = "preisMittel",    l10n = "hl_taskMittel",
      specs = { "spec_sowingMachine", "spec_sprayer", "spec_roller" } },
    { key = "leicht",    cfg = "preisLeicht",    l10n = "hl_taskLeicht",
      specs = { "spec_mower", "spec_windrower", "spec_tedder" } },
}

function HelferLohn.istServer()
    if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil then
        local wert = g_currentMission:getIsServer()
        return wert == true
    end
    return g_server ~= nil
end

-- MoneyType.AI, falls es das nicht gibt nach dem Namen suchen
function HelferLohn.getHelperMoneyType()
    if HelferLohn.moneyTypeCached ~= nil then
        return HelferLohn.moneyTypeCached
    end
    if MoneyType == nil then
        return nil
    end
    local mt = nil
    if MoneyType.AI ~= nil then
        mt = MoneyType.AI
    else
        for k, v in pairs(MoneyType) do
            if type(k) == "string" then
                local up = string.upper(k)
                if up == "AI" or up == "WAGES" or string.find(up, "HELPER") ~= nil or string.find(up, "WAGE") ~= nil then
                    mt = v
                    break
                end
            end
        end
    end
    if mt == nil and not HelferLohn.moneyTypeGewarnt then
        HelferLohn.moneyTypeGewarnt = true
        Logging.warning(HelferLohn.LOG .. "Helfer-Geldtyp (MoneyType.AI) nicht gefunden - Lohn-Steuerung inaktiv, nur Verfuegbarkeit greift.")
    end
    HelferLohn.moneyTypeCached = mt
    return mt
end

-- Jede vorhandene Farm ausser Zuschauern (0) und der NPC-Farm von NachbarFelder
function HelferLohn.isHumanFarm(farmId)
    if type(farmId) ~= "number" or farmId < 1 then
        return false
    end
    if g_NachbarFelderManager ~= nil and g_NachbarFelderManager.farmId == farmId then
        return false
    end
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil
            and g_farmManager:getFarmById(farmId) == nil then
        return false
    end
    return true
end

function HelferLohn.getLocalFarmId()
    local m = g_currentMission
    if m ~= nil then
        if m.getFarmId ~= nil then
            local v = m:getFarmId()
            if v ~= nil then return v end
        end
        if m.playerFarmId ~= nil then return m.playerFarmId end
        if m.player ~= nil and m.player.farmId ~= nil then return m.player.farmId end
    end
    return 1
end

function HelferLohn.getOfferFactor()
    local cfg = HelferLohn.CFG
    if cfg.lohnStufe == HelferLohn.STUFE_AZUBI then
        return cfg.faktorAzubi
    elseif cfg.lohnStufe == HelferLohn.STUFE_AUSGELERNT then
        return cfg.faktorAusgelernt
    elseif cfg.lohnStufe == HelferLohn.STUFE_EIGEN then
        return cfg.faktorEigen
    end
    return cfg.faktorQuer
end

-- 1 leicht, 2 normal, 3 schwer
function HelferLohn.gameEconDifficulty()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if mi ~= nil then
        local d = mi.economicDifficulty or mi.difficulty
        if type(d) == "number" and d >= 1 and d <= 3 then
            return math.floor(d + 0.5)
        end
    end
    return 2
end

-- Setzt die Festpreise fuers Preset; false bei "eigen", da bleibt alles
function HelferLohn.applyDifficulty(level)
    local faktor
    if level == HelferLohn.SCHWER_AUTO then
        faktor = HelferLohn.SCHWER_FAKTOR[HelferLohn.gameEconDifficulty()]
    elseif level == HelferLohn.SCHWER_LEICHT then
        faktor = HelferLohn.SCHWER_FAKTOR[1]
    elseif level == HelferLohn.SCHWER_NORMAL then
        faktor = HelferLohn.SCHWER_FAKTOR[2]
    elseif level == HelferLohn.SCHWER_SCHWER then
        faktor = HelferLohn.SCHWER_FAKTOR[3]
    else
        return false
    end
    if faktor == nil then
        return false
    end
    for k, base in pairs(HelferLohn.PREIS_BASIS) do
        local v = math.floor((base * faktor) / 10 + 0.5) * 10  -- auf 10 EUR runden
        if HelferLohnSettings ~= nil and HelferLohnSettings.applyValue ~= nil then
            HelferLohnSettings.applyValue(k, v)
        else
            HelferLohn.CFG[k] = v
        end
    end
    return true
end

function HelferLohn.getStufeName()
    local cfg = HelferLohn.CFG
    local key
    if cfg.lohnStufe == HelferLohn.STUFE_AZUBI then
        key = "hl_stufeAzubi"
    elseif cfg.lohnStufe == HelferLohn.STUFE_AUSGELERNT then
        key = "hl_stufeAusgelernt"
    elseif cfg.lohnStufe == HelferLohn.STUFE_EIGEN then
        key = "hl_stufeEigen"
    else
        key = "hl_stufeQuer"
    end
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return key
end

function HelferLohn.moneyTypeName(moneyType)
    if MoneyType ~= nil then
        for k, v in pairs(MoneyType) do
            if v == moneyType and type(k) == "string" then
                return k
            end
        end
    end
    if type(moneyType) == "table" then
        if moneyType.statistic ~= nil then
            return "stat:" .. tostring(moneyType.statistic)
        end
        if moneyType.title ~= nil then
            return "title:" .. tostring(moneyType.title)
        end
    end
    return tostring(moneyType)
end

function HelferLohn.formatGeld(betrag)
    if type(betrag) ~= "number" then
        betrag = tonumber(betrag) or 0
    end
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local txt = g_i18n:formatMoney(betrag, 0, true, true)
        if txt ~= nil then
            return txt
        end
    end
    return string.format("%d", math.floor(betrag + 0.5))
end

function HelferLohn.getText(key, fallback)
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return fallback or key
end

-- Aufgabe erkennen ----------------------------------------------------------

function HelferLohn.getJobVehicle(job)
    if job == nil then
        return nil
    end
    if job.vehicleParameter ~= nil and job.vehicleParameter.getVehicle ~= nil then
        local v = job.vehicleParameter:getVehicle()
        if v ~= nil then return v end
    end
    if job.getVehicle ~= nil then
        local v = job:getVehicle()
        if v ~= nil then return v end
    end
    if job.vehicle ~= nil then
        return job.vehicle
    end
    return nil
end

function HelferLohn.collectVehicles(vehicle, list, tiefe)
    if vehicle == nil or tiefe > 8 then
        return
    end
    list[#list + 1] = vehicle
    if vehicle.getAttachedImplements ~= nil then
        local imps = vehicle:getAttachedImplements()
        if type(imps) == "table" then
            for _, imp in pairs(imps) do
                if imp ~= nil and imp.object ~= nil then
                    HelferLohn.collectVehicles(imp.object, list, tiefe + 1)
                end
            end
        end
    end
end

-- liefert Kategorie, Fair-Preis und Anzeigename
function HelferLohn.detectTask(job)
    local cfg = HelferLohn.CFG
    local vehicle = HelferLohn.getJobVehicle(job)
    local liste = {}
    HelferLohn.collectVehicles(vehicle, liste, 0)

    for _, cat in ipairs(HelferLohn.TASK_CATS) do
        for _, fzg in ipairs(liste) do
            for _, spec in ipairs(cat.specs) do
                if fzg[spec] ~= nil then
                    local preis = cfg[cat.cfg] or cfg.festMarktBasis
                    return cat, preis, HelferLohn.getText(cat.l10n, cat.key)
                end
            end
        end
    end

    return nil, cfg.festMarktBasis, HelferLohn.getText("hl_taskStandard", "Arbeit")
end

-- Arbeitsmarkt ---------------------------------------------------------------

-- gibt verfuegbar, angebot, forderung, aufgabe zurueck
function HelferLohn.rollAvailable(job)
    local cfg = HelferLohn.CFG

    local spanne = cfg.marktMax - cfg.marktMin
    if spanne < 0 then spanne = 0 end
    -- ohne Zufall immer verfuegbar, Forderung brauchen wir trotzdem fuer die Meldung
    local faktor = cfg.marktMin
    if cfg.zufallVerfuegbar then
        faktor = cfg.marktMin + math.random() * spanne
    end

    if cfg.bezahlModus == HelferLohn.MODUS_FESTPREIS then
        local _, fairPreis, aufgabe = HelferLohn.detectTask(job)
        local forderung = fairPreis * faktor
        local ok = (not cfg.zufallVerfuegbar) or (cfg.festLohn >= forderung)
        return ok, cfg.festLohn, forderung, aufgabe
    end

    local angebot = HelferLohn.getOfferFactor()
    local ok = (not cfg.zufallVerfuegbar) or (angebot >= faktor)
    return ok, angebot, faktor, nil
end

-- Sprit, Saatgut, Duenger usw.
function HelferLohn.isOperatingCost(moneyType)
    local name = HelferLohn.moneyTypeName(moneyType)
    if name == nil then
        return false
    end
    local up = string.upper(name)
    if up == "AI" then
        return false
    end
    local muster = { "FUEL", "SEED", "FERTILIZER", "SPRAY", "LIME", "HERBICIDE", "PURCHASE" }
    for _, pat in ipairs(muster) do
        if string.find(up, pat, 1, true) ~= nil then
            return true
        end
    end
    return false
end

-- Meldungen ------------------------------------------------------------------

-- zeigt nur an, wenn es die eigene Farm betrifft
function HelferLohn.zeigeMeldung(farmId, text)
    if not HelferLohn.CFG.meldung then
        return
    end
    if farmId ~= nil and farmId ~= 0 and farmId ~= HelferLohn.getLocalFarmId() then
        return
    end
    if g_currentMission == nil then
        return
    end
    local gezeigt = false
    if g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil then
        local farbe = nil
        if FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_INFO ~= nil then
            farbe = FSBaseMission.INGAME_NOTIFICATION_INFO
        end
        if farbe ~= nil and type(text) == "string" then
            g_currentMission.hud:addSideNotification(farbe, text, 4000)
            gezeigt = true
        end
    end
    if not gezeigt and g_currentMission.showBlinkingWarning ~= nil and type(text) == "string" then
        g_currentMission:showBlinkingWarning(text, 4000)
    end
end

function HelferLohn.meldeAnAlle(farmId, text)
    if not HelferLohn.CFG.meldung then
        return
    end
    HelferLohn.zeigeMeldung(farmId, text)
    if HelferLohn.istServer() and g_server ~= nil and HelferLohnNotifyEvent ~= nil then
        if g_server.broadcastEvent ~= nil and HelferLohnNotifyEvent.new ~= nil then
            g_server:broadcastEvent(HelferLohnNotifyEvent.new(farmId or 0, text), false)
        end
    end
end

-- Hooks ----------------------------------------------------------------------

function HelferLohn.installHooks()
    if HelferLohn.hooksInstalliert then
        return
    end

    -- Anheuern: wuerfeln und Auftrag merken
    if AISystem ~= nil and AISystem.startJob ~= nil then
        AISystem.startJob = Utils.overwrittenFunction(AISystem.startJob,
            function(aiSystem, superFunc, job, startFarmId)
                if HelferLohn.debug then
                    Logging.info(HelferLohn.LOG .. "startJob: farmId=%s job=%s server=%s human=%s",
                        tostring(startFarmId), tostring(job), tostring(HelferLohn.istServer()),
                        tostring(HelferLohn.isHumanFarm(startFarmId)))
                end
                -- Auftraege ohne Fahrzeug laufen wie im Spiel
                if HelferLohn.CFG.aktiv and HelferLohn.istServer()
                   and job ~= nil and HelferLohn.isHumanFarm(startFarmId)
                   and HelferLohn.getJobVehicle(job) ~= nil then

                    local verfuegbar, angebot, forderung, aufgabe = HelferLohn.rollAvailable(job)
                    if HelferLohn.debug then
                        local fzg = HelferLohn.getJobVehicle(job)
                        Logging.info(HelferLohn.LOG .. "startJob-Entscheidung: fahrzeug=%s aufgabe=%s verfuegbar=%s angebot=%.2f forderung=%.2f modus=%s",
                            tostring(fzg), tostring(aufgabe), tostring(verfuegbar),
                            angebot or 0, forderung or 0, tostring(HelferLohn.CFG.bezahlModus))
                    end
                    if not verfuegbar then
                        if HelferLohn.CFG.bezahlModus == HelferLohn.MODUS_FESTPREIS then
                            HelferLohn.meldeAnAlle(startFarmId, string.format(
                                HelferLohn.getText("hl_keineHelferFest", "Kein Helfer fuer '%s' zu %s - gefordert ca. %s."),
                                tostring(aufgabe), HelferLohn.formatGeld(HelferLohn.CFG.festLohn),
                                HelferLohn.formatGeld(forderung)))
                        else
                            HelferLohn.meldeAnAlle(startFarmId,
                                HelferLohn.getText("hl_keineHelfer", "Kein Helfer zu diesem Lohn verfuegbar."))
                        end
                        return nil  -- Job startet nicht
                    end

                    HelferLohn.activeAIByFarm[startFarmId] = (HelferLohn.activeAIByFarm[startFarmId] or 0) + 1
                    local fixed = (HelferLohn.CFG.bezahlModus == HelferLohn.MODUS_FESTPREIS)
                    HelferLohn.trackedJobs[job] = { farmId = startFarmId, price = HelferLohn.CFG.festLohn, fixed = fixed }

                    if fixed then
                        HelferLohn.fixedActiveByFarm[startFarmId] = (HelferLohn.fixedActiveByFarm[startFarmId] or 0) + 1
                        HelferLohn.meldeAnAlle(startFarmId, string.format(
                            HelferLohn.getText("hl_eingestelltFest", "Helfer eingestellt: '%s' fuer %s."),
                            tostring(aufgabe), HelferLohn.formatGeld(HelferLohn.CFG.festLohn)))
                    else
                        HelferLohn.meldeAnAlle(startFarmId, string.format(
                            HelferLohn.getText("hl_eingestelltStunde", "Helfer eingestellt: %s (Stundenlohn x%.2f)."),
                            HelferLohn.getStufeName(), HelferLohn.getOfferFactor()))
                    end
                end

                return superFunc(aiSystem, job, startFarmId)
            end)
    else
        Logging.warning(HelferLohn.LOG .. "AISystem.startJob nicht gefunden - Verfuegbarkeit/Festpreis inaktiv.")
    end

    -- Auftragsende: Festpreis abrechnen
    if AISystem ~= nil and AISystem.stopJob ~= nil then
        AISystem.stopJob = Utils.overwrittenFunction(AISystem.stopJob,
            function(aiSystem, superFunc, job, aiMessage)
                local ret = superFunc(aiSystem, job, aiMessage)
                if HelferLohn.istServer() then
                    HelferLohn.settleJob(job, aiMessage)
                end
                return ret
            end)
    end

    -- Spiel-Lohn abfangen, damit nichts doppelt abgeht
    if FSBaseMission ~= nil and FSBaseMission.addMoney ~= nil then
        FSBaseMission.addMoney = Utils.overwrittenFunction(FSBaseMission.addMoney,
            function(mission, superFunc, amount, farmId, moneyType, ...)
                if HelferLohn.debug and amount ~= nil and amount < 0 then
                    Logging.info(HelferLohn.LOG .. "addMoney: betrag=%.2f farmId=%s moneyType=%s human=%s | aktiv=%s modus=%s faktor=%.2f mtMatch=%s aktiveFest=%s",
                        amount, tostring(farmId), HelferLohn.moneyTypeName(moneyType),
                        tostring(HelferLohn.isHumanFarm(farmId)),
                        tostring(HelferLohn.CFG.aktiv), tostring(HelferLohn.CFG.bezahlModus),
                        HelferLohn.getOfferFactor(),
                        tostring(moneyType == HelferLohn.getHelperMoneyType()),
                        tostring(HelferLohn.fixedActiveByFarm[farmId] or 0))
                end
                if HelferLohn.CFG.aktiv and not HelferLohn.inFixedPayment
                   and not HelferLohn.inTierHelfer
                   and amount ~= nil and amount < 0 and HelferLohn.isHumanFarm(farmId) then
                    local mt = HelferLohn.getHelperMoneyType()
                    if mt ~= nil and moneyType == mt then
                        if HelferLohn.CFG.bezahlModus == HelferLohn.MODUS_FESTPREIS then
                            if (HelferLohn.fixedActiveByFarm[farmId] or 0) > 0 then
                                if HelferLohn.debug then
                                    Logging.info(HelferLohn.LOG .. "-> Festpreis: Vanilla-Lohn %.2f unterdrueckt (Zahlung am Ende).", amount)
                                end
                                return  -- gezahlt wird am Ende
                            end
                        else
                            local f = HelferLohn.getOfferFactor()
                            if HelferLohn.debug then
                                Logging.info(HelferLohn.LOG .. "-> Stundenlohn: Lohn %.2f x %.2f = %.2f (ersetzt).", amount, f, amount * f)
                            end
                            return superFunc(mission, amount * f, farmId, moneyType, ...)
                        end
                    elseif HelferLohn.CFG.gratisBetrieb
                       and (HelferLohn.activeAIByFarm[farmId] or 0) > 0
                       and HelferLohn.isOperatingCost(moneyType) then
                        if HelferLohn.debug then
                            Logging.info(HelferLohn.LOG .. "-> Gratis-Helfer: Betriebskosten %.2f (%s) unterdrueckt.",
                                amount, HelferLohn.moneyTypeName(moneyType))
                        end
                        return
                    end
                end
                return superFunc(mission, amount, farmId, moneyType, ...)
            end)
    else
        Logging.warning(HelferLohn.LOG .. "FSBaseMission.addMoney nicht gefunden - Lohn-Steuerung inaktiv.")
    end

    HelferLohn.hooksInstalliert = true
    Logging.info(HelferLohn.LOG .. "Hooks installiert.")
end

-- StoppedByUser ist auch Typ OK, heisst aber entlassen
function HelferLohn.istErfolgreich(aiMessage)
    if aiMessage == nil or aiMessage.getType == nil or AIMessageType == nil then
        return false
    end
    if aiMessage:getType() ~= AIMessageType.OK then
        return false
    end
    if AIMessageSuccessStoppedByUser ~= nil and aiMessage.isa ~= nil
            and aiMessage:isa(AIMessageSuccessStoppedByUser) then
        return false
    end
    return true
end

function HelferLohn.settleJob(job, aiMessage)
    local t = HelferLohn.trackedJobs[job]
    if t == nil then
        return
    end
    HelferLohn.trackedJobs[job] = nil

    local aktiv = (HelferLohn.activeAIByFarm[t.farmId] or 1) - 1
    if aktiv < 0 then aktiv = 0 end
    HelferLohn.activeAIByFarm[t.farmId] = aktiv

    if not t.fixed then
        return
    end

    local rest = (HelferLohn.fixedActiveByFarm[t.farmId] or 1) - 1
    if rest < 0 then rest = 0 end
    HelferLohn.fixedActiveByFarm[t.farmId] = rest

    local mt = HelferLohn.getHelperMoneyType()
    if mt == nil or g_currentMission == nil or g_currentMission.addMoney == nil then
        return
    end

    if HelferLohn.CFG.nurBeiErfolg and not HelferLohn.istErfolgreich(aiMessage) then
        HelferLohn.meldeAnAlle(t.farmId,
            HelferLohn.getText("hl_abgebrochen", "Auftrag abgebrochen - kein Lohn faellig."))
        return
    end

    local preis = tonumber(t.price) or 0
    HelferLohn.inFixedPayment = true
    g_currentMission:addMoney(-math.abs(preis), t.farmId, mt, true, true)
    HelferLohn.inFixedPayment = false

    HelferLohn.meldeAnAlle(t.farmId, string.format(
        HelferLohn.getText("hl_bezahlt", "Helfer bezahlt: %s."),
        HelferLohn.formatGeld(t.price)))
end

-- Konsole ---------------------------------------------------------------------

function HelferLohn.registriereBefehle()
    if HelferLohn.befehleRegistriert or addConsoleCommand == nil then
        return
    end
    HelferLohn.befehleRegistriert = true
    addConsoleCommand("hlStatus", "Zeigt die aktuellen Helfer-Lohn-Einstellungen.", "cmdStatus", HelferLohn)
    addConsoleCommand("hlConfig", "Einstellung anzeigen/aendern: hlConfig [name] [wert]", "cmdConfig", HelferLohn)
    addConsoleCommand("hlReload", "settings.xml neu laden (Server).", "cmdReload", HelferLohn)
    addConsoleCommand("hlTest", "Wuerfelt 10x, ob ein Helfer zum aktuellen Lohn verfuegbar waere.", "cmdTest", HelferLohn)
    addConsoleCommand("hlDebug", "Diagnose-Protokoll an/aus: hlDebug [0|1]", "cmdDebug", HelferLohn)
    addConsoleCommand("hlDumpMoney", "Listet alle MoneyType-Kategorien (Diagnose).", "cmdDumpMoney", HelferLohn)
    addConsoleCommand("hlMenu", "Oeffnet/schliesst das Helfer-Panel (ohne Taste).", "cmdMenu", HelferLohn)
end

function HelferLohn.cmdMenu()
    HelferLohn.toggleMenu()
    return HelferLohn.LOG .. "Menue umgeschaltet (Alt+H bzw. hlMenu)."
end

-- Menue ----------------------------------------------------------------------

function HelferLohn.loadDialog()
    if HelferLohn.dialogLoaded then return true end
    if g_gui == nil or g_gui.guis == nil then return false end
    if g_gui.guis[HelferLohn.DIALOG_NAME] ~= nil then
        HelferLohn.dialogLoaded = true
        return true
    end
    if HelferLohnDialog == nil or HelferLohnDialog.new == nil then
        return false
    end
    local xmlPath = (HelferLohn.modDir or "") .. HelferLohn.DIALOG_XML
    if fileExists ~= nil and not fileExists(xmlPath) then
        Logging.warning(HelferLohn.LOG .. "Dialog-XML fehlt: %s", tostring(xmlPath))
        return false
    end
    if g_gui.loadGui == nil then
        return false
    end
    local controller = HelferLohnDialog.new()
    if controller ~= nil then
        g_gui:loadGui(xmlPath, HelferLohn.DIALOG_NAME, controller, false)
    end
    HelferLohn.dialogLoaded = (g_gui.guis[HelferLohn.DIALOG_NAME] ~= nil)
    return HelferLohn.dialogLoaded
end

function HelferLohn.toggleMenu()
    if g_gui == nil or g_currentMission == nil then return end
    if g_gui.currentGuiName == HelferLohn.DIALOG_NAME then
        if g_gui.showGui ~= nil then
            g_gui:showGui("")
        end
        return
    end
    if g_gui.currentGui ~= nil then return end  -- anderes Menue offen
    if not HelferLohn.loadDialog() then return end
    if g_gui.showDialog ~= nil then
        g_gui:showDialog(HelferLohn.DIALOG_NAME)
    end
end

-- Der Kontext wird im MP neu aufgebaut, daher jedes Mal alt weg und neu rein
function HelferLohn.registriereMenueTaste()
    if g_dedicatedServerInfo ~= nil then return end
    if g_inputBinding == nil or InputAction == nil or InputAction.HL_TOGGLE == nil then return end

    if HelferLohn.toggleEventId ~= nil then
        if g_inputBinding.removeActionEvent ~= nil then
            g_inputBinding:removeActionEvent(HelferLohn.toggleEventId)
        end
        HelferLohn.toggleEventId = nil
    end

    if g_inputBinding.registerActionEvent == nil then return end
    local success, id = g_inputBinding:registerActionEvent(InputAction.HL_TOGGLE, HelferLohn, HelferLohn.toggleMenu, false, true, false, true)
    if success then
        HelferLohn.toggleEventId = id
        HelferLohn.toggleRegistered = true
        if id ~= nil and g_inputBinding.setActionEventTextVisibility ~= nil then
            g_inputBinding:setActionEventTextVisibility(id, false)
        end
    end
end

function HelferLohn.cmdDebug(_, wert)
    if wert ~= nil and wert ~= "" then
        HelferLohn.debug = (wert == "1" or wert == "true" or wert == "on" or wert == "an")
    else
        HelferLohn.debug = not HelferLohn.debug
    end
    return HelferLohn.LOG .. "Diagnose-Protokoll = " .. tostring(HelferLohn.debug) .. " (Ausgabe in log.txt)"
end

function HelferLohn.cmdDumpMoney()
    local out = { HelferLohn.LOG .. "MoneyType-Kategorien:" }
    if MoneyType ~= nil then
        local namen = {}
        for k, v in pairs(MoneyType) do
            if type(k) == "string" and type(v) ~= "function" then
                namen[#namen + 1] = k
            end
        end
        table.sort(namen)
        for _, k in ipairs(namen) do
            local v = MoneyType[k]
            local stat = (type(v) == "table" and v.statistic ~= nil) and tostring(v.statistic) or "-"
            out[#out + 1] = string.format("  %s = %s (statistic=%s)", k, tostring(v), stat)
        end
    else
        out[#out + 1] = "  MoneyType ist nil!"
    end
    out[#out + 1] = "  => als Helfer-Lohn gewaehlt: " .. HelferLohn.moneyTypeName(HelferLohn.getHelperMoneyType())
    local txt = table.concat(out, "\n")
    Logging.info(txt)
    return txt
end

function HelferLohn.cmdStatus()
    local cfg = HelferLohn.CFG
    local modus = (cfg.bezahlModus == HelferLohn.MODUS_FESTPREIS) and "Festpreis" or "Stundenlohn"
    local zeilen = {
        HelferLohn.LOG .. "Status:",
        string.format("  aktiv=%s  modus=%s  stufe=%s", tostring(cfg.aktiv), modus, HelferLohn.getStufeName()),
        string.format("  StundenFaktor(aktuell)=%.2f  festLohn=%s", HelferLohn.getOfferFactor(), HelferLohn.formatGeld(cfg.festLohn)),
        string.format("  zufallVerfuegbar=%s  markt=%.2f..%.2f  gratisBetrieb=%s",
            tostring(cfg.zufallVerfuegbar), cfg.marktMin, cfg.marktMax, tostring(cfg.gratisBetrieb)),
        string.format("  Faktoren: Azubi=%.2f Quer=%.2f Ausgelernt=%.2f Eigen=%.2f",
            cfg.faktorAzubi, cfg.faktorQuer, cfg.faktorAusgelernt, cfg.faktorEigen),
        string.format("  Fair-Preise: leicht=%s mittel=%s boden=%s pressen=%s dreschen=%s haeckseln=%s standard=%s",
            HelferLohn.formatGeld(cfg.preisLeicht), HelferLohn.formatGeld(cfg.preisMittel),
            HelferLohn.formatGeld(cfg.preisBoden), HelferLohn.formatGeld(cfg.preisPressen),
            HelferLohn.formatGeld(cfg.preisDreschen), HelferLohn.formatGeld(cfg.preisHaeckseln),
            HelferLohn.formatGeld(cfg.festMarktBasis)),
    }
    return table.concat(zeilen, "\n")
end

function HelferLohn.cmdConfig(_, name, wert)
    if name == nil or name == "" then
        return HelferLohn.cmdStatus()
    end
    if HelferLohn.CFG[name] == nil then
        return HelferLohn.LOG .. "Unbekannte Einstellung: " .. tostring(name)
    end
    if wert == nil or wert == "" then
        return string.format("%s%s = %s", HelferLohn.LOG, name, tostring(HelferLohn.CFG[name]))
    end
    if HelferLohnSettings ~= nil then
        HelferLohnSettings.applyValue(name, wert)
        HelferLohnSettings.onLocalChange()
    end
    return string.format("%s%s -> %s", HelferLohn.LOG, name, tostring(HelferLohn.CFG[name]))
end

function HelferLohn.cmdReload()
    if HelferLohnSettings == nil then
        return HelferLohn.LOG .. "Settings-Manager nicht bereit."
    end
    local ok, info = HelferLohnSettings.reload()
    if ok then
        return HelferLohn.LOG .. "settings.xml neu geladen: " .. tostring(info)
    end
    return HelferLohn.LOG .. tostring(info)
end

function HelferLohn.cmdTest()
    local treffer = 0
    local modus = (HelferLohn.CFG.bezahlModus == HelferLohn.MODUS_FESTPREIS) and "Festpreis" or "Stundenlohn"
    local zeilen = { HelferLohn.LOG .. "Verfuegbarkeits-Test (" .. modus .. ", 10 Versuche, ohne erkannte Aufgabe = Standardpreis):" }
    for i = 1, 10 do
        local ok, angebot, forderung = HelferLohn.rollAvailable(nil)
        if ok then treffer = treffer + 1 end
        zeilen[#zeilen + 1] = string.format("  %2d: %s (Angebot=%.2f  Forderung=%.2f)",
            i, ok and "Helfer da" or "niemand", angebot or 0, forderung or 0)
    end
    zeilen[#zeilen + 1] = string.format("  => %d/10 verfuegbar.", treffer)
    return table.concat(zeilen, "\n")
end

-- Laden ----------------------------------------------------------------------

function HelferLohn:loadMap(name)
    if HelferLohn.bereit then
        return
    end
    HelferLohn.bereit = true

    HelferLohn.installHooks()
    HelferLohn.registriereBefehle()

    if g_dedicatedServerInfo == nil and g_client ~= nil then
        HelferLohn.loadDialog()
    end

    -- Taste im Spieler-Kontext anmelden, sonst ist sie im MP irgendwann weg
    if not HelferLohn.inputHookInstalliert and PlayerInputComponent ~= nil
       and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil then
        PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.overwrittenFunction(
            PlayerInputComponent.registerGlobalPlayerActionEvents,
            function(comp, superFunc, ...)
                local ret = superFunc(comp, ...)
                if g_client ~= nil and comp.player ~= nil and comp.player.isOwner then
                    HelferLohn.registriereMenueTaste()
                end
                return ret
            end)
        HelferLohn.inputHookInstalliert = true
    end

    -- Preset-Preise erst, wenn die Spiel-Schwierigkeit feststeht; nur Server
    if HelferLohn.istServer() and g_messageCenter ~= nil and MessageType ~= nil
       and MessageType.CURRENT_MISSION_LOADED ~= nil then
        g_messageCenter:subscribeOneshot(MessageType.CURRENT_MISSION_LOADED,
            function()
                if HelferLohn.applyDifficulty(HelferLohn.CFG.schwierigkeit) then
                    if HelferLohnSettings ~= nil and HelferLohnSettings.onLocalChange ~= nil then
                        HelferLohnSettings.onLocalChange()
                    end
                end
            end, HelferLohn)
    end

    Logging.info(HelferLohn.LOG .. "Bereit (Server=%s).", tostring(HelferLohn.istServer()))
end

-- Tier-Helfer buchen ebenfalls MoneyType.AI, die sollen beim Spiel-Lohn bleiben.
-- Muss beim Laden der Datei passieren, bevor die Placeable-Typen fertig sind.
if PlaceableHusbandryAnimalWorker ~= nil and PlaceableHusbandryAnimalWorker.performAnimalWorkerTask ~= nil then
    PlaceableHusbandryAnimalWorker.performAnimalWorkerTask = Utils.overwrittenFunction(
        PlaceableHusbandryAnimalWorker.performAnimalWorkerTask,
        function(placeable, superFunc, ...)
            HelferLohn.inTierHelfer = true
            local anzahl, kosten = superFunc(placeable, ...)
            HelferLohn.inTierHelfer = false
            return anzahl, kosten
        end)
end

addModEventListener(HelferLohn)
