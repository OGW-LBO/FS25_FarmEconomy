-- AOUIHelper.lua
-- Klont Abschnitte und Auswahlzeilen in die Seite "Allgemeine Einstellungen".
-- OGW

AOUIHelper = {}

AOUIHelper.LOG = "[AgrarOekonomie] "

function AOUIHelper.updateFocusIds(element)
    if element == nil then
        return
    end
    element.focusId = FocusManager:serveAutoFocusId()
    if element.elements then
        for _, child in ipairs(element.elements) do
            AOUIHelper.updateFocusIds(child)
        end
    end
end

function AOUIHelper.createSection(settingsPage, titelText)
    if settingsPage == nil or settingsPage.generalSettingsLayout == nil then
        return nil
    end

    local layout = settingsPage.generalSettingsLayout

    for _, elem in ipairs(layout.elements) do
        if elem.name == "sectionHeader" then
            local section = elem:clone(layout)
            section:setText(titelText)
            section.focusId = FocusManager:serveAutoFocusId()
            if settingsPage.controlsList then
                table.insert(settingsPage.controlsList, section)
            end
            settingsPage.generalSettingsLayout:invalidateLayout()
            return section
        end
    end

    Logging.warning(AOUIHelper.LOG .. "Kein sectionHeader-Template gefunden.")
    return nil
end

function AOUIHelper.createChoiceElement(settingsPage, id, labelText, tooltipText, texts, target, callbackName)
    if settingsPage == nil then
        return nil
    end

    local template = settingsPage.multiVolumeVoiceBox
    if template == nil then
        Logging.warning(AOUIHelper.LOG .. "multiVolumeVoiceBox-Template nicht gefunden.")
        return nil
    end

    local box = template:clone(settingsPage.generalSettingsLayout)
    AOUIHelper.updateFocusIds(box)
    box.id = id .. "Box"

    local option = box.elements[1]
    if option == nil then
        Logging.warning(AOUIHelper.LOG .. "Kein option-Element in Box fuer %s.", tostring(id))
        return nil
    end

    option.id = id
    option.target = target

    -- Callback direkt als Funktion setzen, raiseCallback kann keine Namen aufloesen
    option.onClickCallback = function(_, newState)
        local ziel = target[callbackName]
        if ziel ~= nil then
            ziel(target, newState)
        end
    end

    option:setDisabled(false)

    -- FocusManager braucht hier den Namen des Settings-Frames
    target.name = settingsPage.name

    if box.elements[2] then
        box.elements[2]:setText(labelText)
    end
    if option.elements and option.elements[1] then
        option.elements[1]:setText(tooltipText)
    end

    option:setTexts(texts)

    if settingsPage.controlsList then
        table.insert(settingsPage.controlsList, box)
    end
    settingsPage.generalSettingsLayout:invalidateLayout()
    return box
end

-- fuer Tastatur und Controller
function AOUIHelper.registerFocusControls(controls)
    FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function(_, gui)
        for _, control in ipairs(controls) do
            local needsLoad = control.focusId == nil
                or FocusManager.currentFocusData == nil
                or FocusManager.currentFocusData.idToElementMapping == nil
                or not FocusManager.currentFocusData.idToElementMapping[control.focusId]
            if needsLoad then
                if FocusManager.loadElementFromCustomValues ~= nil then
                    FocusManager:loadElementFromCustomValues(control, nil, nil, false, false)
                else
                    Logging.warning(AOUIHelper.LOG .. "Focus-Load fehlgeschlagen fuer %s.",
                        tostring(control.id))
                end
            end
        end

        if g_gui ~= nil and g_gui.screenControllers ~= nil and InGameMenu ~= nil then
            local page = g_gui.screenControllers[InGameMenu].pageSettings
            if page ~= nil and page.generalSettingsLayout ~= nil then
                page.generalSettingsLayout:invalidateLayout()
            end
        end
    end)
end
