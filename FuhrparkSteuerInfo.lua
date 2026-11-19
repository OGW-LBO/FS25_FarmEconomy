-- FuhrparkSteuerInfo.lua
-- Zeigt in der Fahrzeug-Infobox, was das Fahrzeug an Steuer/Abgaben kostet.
-- OGW

FuhrparkSteuerInfo = {}

function FuhrparkSteuerInfo.prerequisitesPresent(specializations)
    -- kommt eh nur an Typen mit wearable
    return true
end

function FuhrparkSteuerInfo.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", FuhrparkSteuerInfo.showInfo)
end

function FuhrparkSteuerInfo.getLabel()
    if g_i18n ~= nil and g_i18n.hasText ~= nil then
        if g_i18n:hasText("fs_infoLabel") then
            return g_i18n:getText("fs_infoLabel")
        end
    end
    return "Steuer/Abgaben"
end

function FuhrparkSteuerInfo:showInfo(superFunc, box)
    superFunc(self, box)

    if box == nil or box.addLine == nil then
        return
    end

    if FuhrparkSteuer == nil or FuhrparkSteuer.CFG == nil then
        return
    end
    local cfg = FuhrparkSteuer.CFG
    if not cfg.enabled or not cfg.showInInfoBox then
        return
    end

    if FuhrparkSteuer.istBesteuerbar == nil or not FuhrparkSteuer.istBesteuerbar(self) then
        return
    end

    local monat = FuhrparkSteuer.getMonatskosten(self)
    if monat == nil or monat <= 0 then
        return
    end

    local jaehrlich = (cfg.billingMode == 1)
    local betrag = jaehrlich and (monat * 12) or monat
    local einheit = jaehrlich and "/Jahr" or "/Monat"

    box:addLine(FuhrparkSteuerInfo.getLabel(),
        string.format("%s %s", FuhrparkSteuer.formatGeld(betrag), einheit))
end
