-- BindegarnFolieVerbrauch.lua
-- Mehr Verbrauch an Bindegarn, Netz (beides consumableUsage) und Wickelfolie
-- (wrapUsage). Mehr Rollen kaufen heisst auch mehr Kosten.
-- OGW

BindegarnFolieVerbrauch = {}

BindegarnFolieVerbrauch.LOG = "[AgrarOekonomie] "

-- falls AgrarOekonomie.CFG fehlt
BindegarnFolieVerbrauch.FALLBACK_TWINE = 5.0
BindegarnFolieVerbrauch.FALLBACK_NET   = 5.0
BindegarnFolieVerbrauch.FALLBACK_WRAP  = 3.0

local function clampFactor(value, default)
    if value == nil or value ~= value then -- nil oder NaN
        return default
    end
    if value < 0 then
        return 0
    end
    if value > 100 then
        return 100
    end
    return value
end

local function getFaktor(schluessel, fallback)
    if AgrarOekonomie ~= nil and AgrarOekonomie.CFG ~= nil then
        return clampFactor(AgrarOekonomie.CFG[schluessel], fallback)
    end
    return fallback
end

function BindegarnFolieVerbrauch.getFaktorBindegarn()
    return getFaktor("verbrauchBindegarn", BindegarnFolieVerbrauch.FALLBACK_TWINE)
end

function BindegarnFolieVerbrauch.getFaktorNetz()
    return getFaktor("verbrauchNetz", BindegarnFolieVerbrauch.FALLBACK_NET)
end

function BindegarnFolieVerbrauch.getFaktorFolie()
    return getFaktor("verbrauchFolie", BindegarnFolieVerbrauch.FALLBACK_WRAP)
end

-- Auftrags- und Leihmaschinen ausnehmen. propertyState ist erst ab onPostLoad
-- gesetzt, deshalb haengt alles dort.
function BindegarnFolieVerbrauch.istBetroffen(vehicle)
    if vehicle == nil then
        return false
    end
    if AgrarOekonomie == nil or AgrarOekonomie.CFG == nil then
        return true
    end
    if AgrarOekonomie.CFG.verbrauchNurEigene ~= true then
        return true
    end
    if VehiclePropertyState == nil then
        return true      -- Zustand nicht ermittelbar -> wie bisher behandeln
    end

    local zustand = vehicle.propertyState
    if VehiclePropertyState.MISSION ~= nil and zustand == VehiclePropertyState.MISSION then
        return false
    end
    if VehiclePropertyState.LEASED ~= nil and zustand == VehiclePropertyState.LEASED then
        return false
    end
    return true
end

-- Presse: Rundballen = Netz, Quaderballen = Bindegarn

function BindegarnFolieVerbrauch.balerOnPostLoad(self, savegame)
    local spec = self.spec_baler
    if spec == nil or spec.baleTypes == nil then
        return
    end

    local betroffen = BindegarnFolieVerbrauch.istBetroffen(self)

    for _, baleType in ipairs(spec.baleTypes) do
        if baleType.consumableUsage ~= nil and baleType.consumableUsage > 0 then
            -- Original merken, sonst skaliert jede Aenderung den schon skalierten Wert
            if baleType.aoBasisVerbrauch == nil then
                baleType.aoBasisVerbrauch = baleType.consumableUsage
            end

            local faktor = 1.0
            if betroffen then
                faktor = BindegarnFolieVerbrauch.getFaktorBindegarn()
                if baleType.isRoundBale == true then
                    faktor = BindegarnFolieVerbrauch.getFaktorNetz()
                end
            end

            baleType.consumableUsage = baleType.aoBasisVerbrauch * faktor
        end
    end
end

-- Wickler: wrapUsage je Ballentyp

local function scaleWrapList(list, factor)
    if list == nil then
        return
    end
    for _, baleType in ipairs(list) do
        if baleType.wrapUsage ~= nil and baleType.wrapUsage > 0 then
            if baleType.aoBasisWrap == nil then
                baleType.aoBasisWrap = baleType.wrapUsage
            end
            baleType.wrapUsage = baleType.aoBasisWrap * factor
        end
    end
end

function BindegarnFolieVerbrauch.baleWrapperOnPostLoad(self, savegame)
    local spec = self.spec_baleWrapper
    if spec == nil then
        return
    end

    local faktor = 1.0
    if BindegarnFolieVerbrauch.istBetroffen(self) then
        faktor = BindegarnFolieVerbrauch.getFaktorFolie()
    end

    if spec.roundBaleWrapper ~= nil then
        scaleWrapList(spec.roundBaleWrapper.allowedBaleTypes, faktor)
    end
    if spec.squareBaleWrapper ~= nil then
        scaleWrapList(spec.squareBaleWrapper.allowedBaleTypes, faktor)
    end
end

if Baler ~= nil and Baler.onPostLoad ~= nil then
    Baler.onPostLoad = Utils.appendedFunction(Baler.onPostLoad,
        BindegarnFolieVerbrauch.balerOnPostLoad)
else
    Logging.warning(BindegarnFolieVerbrauch.LOG ..
        "Baler.onPostLoad nicht gefunden - Bindegarn/Netz-Anpassung inaktiv.")
end

if BaleWrapper ~= nil and BaleWrapper.onPostLoad ~= nil then
    BaleWrapper.onPostLoad = Utils.appendedFunction(BaleWrapper.onPostLoad,
        BindegarnFolieVerbrauch.baleWrapperOnPostLoad)
else
    Logging.warning(BindegarnFolieVerbrauch.LOG ..
        "BaleWrapper.onPostLoad nicht gefunden - Folien-Anpassung inaktiv.")
end
