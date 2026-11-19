-- AOZins.lua
-- Guthabenzins, einmal im Spielmonat (ausgeloest von AOGrundsteuer.monatswechsel).
-- Verzinst wird Kontostand minus Kredit, gestaffelt: bis zinsGrenze1 voll,
-- bis zinsGrenze2 halb, darueber nichts.
-- OGW

AOZins = {}

AOZins.LOG      = "[AgrarOekonomie] "
AOZins.MOD_NAME = g_currentModName

AOZins.moneyType     = nil
AOZins.inGutschrift  = false
AOZins.letzte        = {}   -- [farmId] = { basis, zins } der letzten Gutschrift

-- Eigene Buchungsart. Server und Clients registrieren gleich in loadMap,
-- damit die Kennung im MP passt.
function AOZins.registriereMoneyType()
    if AOZins.moneyType ~= nil then
        return
    end
    if MoneyType ~= nil and MoneyType.register ~= nil then
        AOZins.moneyType = MoneyType.register("other", "ao_finance_zins", AOZins.MOD_NAME)
    end
end

function AOZins.berechne(geld, kredit)
    local cfg   = AgrarOekonomie.CFG
    local basis = (geld or 0) - (kredit or 0)
    if basis <= 0 then
        return 0, basis
    end

    local satz = math.max(0, cfg.zinsSatz or 0)
    local g1   = math.max(0, cfg.zinsGrenze1 or 0)
    local g2   = math.max(g1, cfg.zinsGrenze2 or 0)

    local voll = math.min(basis, g1)
    local halb = math.max(0, math.min(basis, g2) - g1)

    local proJahr = voll * satz + halb * satz * 0.5
    return proJahr / 12.0, basis
end

function AOZins.verzinse()
    local cfg = AgrarOekonomie.CFG
    if not cfg.zinsAktiv or not AgrarOekonomie.istServer() then
        return
    end
    if g_farmManager == nil or g_farmManager.getFarms == nil
            or g_currentMission == nil or g_currentMission.addMoney == nil then
        return
    end

    AOZins.registriereMoneyType()
    local mt = AOZins.moneyType
    if mt == nil and MoneyType ~= nil then
        mt = MoneyType.OTHER
    end

    local farms = g_farmManager:getFarms()
    if type(farms) ~= "table" then
        return
    end

    for _, farm in pairs(farms) do
        local farmId = type(farm) == "table" and farm.farmId or nil
        if farmId ~= nil and AgrarOekonomie.istSpielerFarm(farmId) then
            local geld   = tonumber(farm.money) or 0
            local kredit = tonumber(farm.loan) or 0
            local zins, basis = AOZins.berechne(geld, kredit)
            zins = math.floor(zins + 0.5)

            if zins > 0 then
                -- zaehlt nicht als Einnahme fuer die Bremse
                AOZins.inGutschrift = true
                g_currentMission:addMoney(zins, farmId, mt, true)
                AOZins.inGutschrift = false

                if g_currentMission.showMoneyChange ~= nil then
                    g_currentMission:showMoneyChange(mt, nil, nil, farmId)
                end

                AOZins.letzte[farmId] = { basis = basis, zins = zins }
                Logging.info(AOZins.LOG ..
                    "Guthabenzins Farm %d: Konto %s, Kredit %s, verzinst %s -> %s gutgeschrieben.",
                    farmId, AgrarOekonomie.formatGeld(geld), AgrarOekonomie.formatGeld(kredit),
                    AgrarOekonomie.formatGeld(basis), AgrarOekonomie.formatGeld(zins))
            elseif cfg.debug then
                Logging.info(AOZins.LOG ..
                    "Guthabenzins Farm %d: nichts faellig (Konto %s, Kredit %s).",
                    farmId, AgrarOekonomie.formatGeld(geld), AgrarOekonomie.formatGeld(kredit))
            end
        end
    end
end

-- fuer aoStatus
function AOZins.statusZeile()
    local cfg = AgrarOekonomie.CFG
    return string.format("  Guthabenzins: aktiv=%s  Satz=%.2f %%/Jahr  voll bis %s, halb bis %s",
        tostring(cfg.zinsAktiv), (cfg.zinsSatz or 0) * 100,
        AgrarOekonomie.formatGeld(cfg.zinsGrenze1 or 0),
        AgrarOekonomie.formatGeld(cfg.zinsGrenze2 or 0))
end

function AOZins:loadMap(name)
    AOZins.registriereMoneyType()
    Logging.info(AOZins.LOG .. "Guthabenzins bereit (aktiv=%s).",
        tostring(AgrarOekonomie.CFG.zinsAktiv))
end

addModEventListener(AOZins)
