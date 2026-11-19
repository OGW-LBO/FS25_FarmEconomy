-- ReparaturOekonomieWorkshop.lua
-- Hinweisfenster in der Werkstatt, wenn das gewaehlte Fahrzeug kritisch
-- teuer geworden ist. Laeuft nur lokal.
-- OGW

ReparaturOekonomieWorkshop = {}

ReparaturOekonomieWorkshop.LOG = "[ReparaturOekonomie] "
ReparaturOekonomieWorkshop.gehooked = false

local function holeText(name, standard)
    if g_i18n ~= nil and g_i18n.hasText ~= nil then
        if name ~= nil and g_i18n:hasText(name) then
            return g_i18n:getText(name)
        end
    end
    return standard
end

function ReparaturOekonomieWorkshop.onSetVehicle(screen, vehicle)
    if screen == nil or vehicle == nil then
        return
    end

    if vehicle.roGetBewertung == nil then
        return
    end

    -- je Fahrzeug nur einmal
    if screen.roLetztWarnung == vehicle then
        return
    end
    screen.roLetztWarnung = vehicle

    local anteil, stufe = vehicle:roGetBewertung()

    if type(anteil) ~= "number" then
        return
    end

    -- Stufe 1 steht schon in der Info-Box
    if stufe ~= 2 then
        return
    end

    local name = "?"
    if vehicle.getFullName ~= nil then
        local voll = vehicle:getFullName()
        if voll ~= nil then
            name = voll
        end
    end

    local vorlage = holeText("ro_werkstatt_kritisch",
        "%s\nDie aufsummierten Reparaturkosten liegen bei %d %% des Fahrzeugwerts. Ein Neukauf ist wahrscheinlich guenstiger als weiteres Reparieren.")
    local text = tostring(vorlage)
    -- kaputte Uebersetzung mit mehr als 2 Platzhaltern lieber roh zeigen
    if type(vorlage) == "string" then
        local ohneProzent = string.gsub(vorlage, "%%%%", "")
        local _, anzahlPlatzhalter = string.gsub(ohneProzent, "%%", "")
        if anzahlPlatzhalter <= 2 then
            text = string.format(vorlage, name, math.floor(anteil * 100 + 0.5))
        end
    end

    if InfoDialog ~= nil and InfoDialog.show ~= nil then
        local dialogTyp = nil
        if DialogElement ~= nil and DialogElement.TYPE_INFO ~= nil then
            dialogTyp = DialogElement.TYPE_INFO
        end
        InfoDialog.show(text, nil, nil, dialogTyp)
    else
        Logging.info(ReparaturOekonomieWorkshop.LOG .. tostring(text))
    end
end

function ReparaturOekonomieWorkshop.hook()
    if ReparaturOekonomieWorkshop.gehooked then
        return
    end
    if WorkshopScreen == nil or WorkshopScreen.setVehicle == nil then
        return
    end

    WorkshopScreen.setVehicle = Utils.appendedFunction(WorkshopScreen.setVehicle,
        ReparaturOekonomieWorkshop.onSetVehicle)

    ReparaturOekonomieWorkshop.gehooked = true
    Logging.info(ReparaturOekonomieWorkshop.LOG .. "Werkstatt-Hinweis aktiv.")
end

function ReparaturOekonomieWorkshop:loadMap(name)
    ReparaturOekonomieWorkshop.hook()
end

addModEventListener(ReparaturOekonomieWorkshop)
