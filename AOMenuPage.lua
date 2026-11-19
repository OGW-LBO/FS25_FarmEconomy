-- AOMenuPage.lua
-- Eigener Unter-Tab unter ESC -> Allgemeine Einstellungen mit allen Reglern.
-- Welche Regler es gibt, steht in AOSettingsPage.ABSCHNITTE.
-- OGW

AOMenuPage = {}
local AOMenuPage_mt = Class(AOMenuPage, FrameElement)
local modDirectory  = g_currentModDirectory

AOMenuPage.LOG = "[AgrarOekonomie] "

-- fuer die GUI-Callbacks
g_AOMenuPage = nil

local function getPage()
    return g_AOMenuPage
end

function AOMenuPage.new()
    local self = FrameElement.new(nil, AOMenuPage_mt)
    self.controls = {}
    self.dynamischeKoepfe = {}   -- Kopfzeilen, deren Text zur Laufzeit wechselt
    self.injiziert = false
    return self
end

-- paging.state ist der Index in der Liste, nicht die Seitennummer - die
-- steht in paging.texts. Bei ausgeblendeten oder fremden Tabs weichen sie ab.
function AOMenuPage.istUnserTab(sf)
    if sf == nil or InGameMenuSettingsFrame == nil then
        return false
    end

    local ziel = InGameMenuSettingsFrame.SUB_CATEGORY ~= nil
        and InGameMenuSettingsFrame.SUB_CATEGORY.AGRAR_OEKONOMIE or nil
    local paging = sf.subCategoryPaging
    if ziel == nil or paging == nil then
        return false
    end

    if paging.texts ~= nil and paging.texts[paging.state] ~= nil then
        return tonumber(paging.texts[paging.state]) == ziel
    end
    return paging.state == ziel
end

local function t(key)
    if AOSettingsPage ~= nil and AOSettingsPage.getText ~= nil then
        return AOSettingsPage.getText(key)
    end
    return key or ""
end

-- SP und Host immer, sonst nur Admins. Der Server prueft beim Empfang nochmal.
function AOMenuPage.darfAendern()
    if g_currentMission == nil then
        return true
    end
    if g_currentMission.getIsServer ~= nil and g_currentMission:getIsServer() then
        return true
    end
    return g_currentMission.isMasterUser == true
end

function AOMenuPage.getKopfzeile()
    if AOMenuPage.darfAendern() then
        return t("ao_tabTitle")
    end
    return t("ao_tabTitle") .. "  (" .. t("ao_ui_nurAdmin") .. ")"
end


-- Aufbau -----------------------------------------------------------------------

function AOMenuPage:registerAndInject()
    if self.injiziert then
        return
    end

    if g_gui == nil or g_gui.loadGui == nil then
        Logging.warning(AOMenuPage.LOG .. "loadGui fehlgeschlagen: g_gui nicht verfuegbar.")
        return
    end
    g_gui:loadGui(
        Utils.getFilename("gui/AOMenu.xml", modDirectory),
        "AOMenuPage",
        self)

    local settingsFrame = g_inGameMenu ~= nil and g_inGameMenu.pageSettings or nil
    if settingsFrame == nil then
        Logging.warning(AOMenuPage.LOG .. "pageSettings nicht verfuegbar.")
        return
    end

    local seite = self.aoPage
    local tab   = self.aoTab
    if seite == nil or tab == nil then
        Logging.warning(AOMenuPage.LOG .. "aoPage/aoTab nicht gefunden (GUI-XML fehlerhaft?).")
        return
    end

    -- lieber gar nicht einbauen als halb
    if settingsFrame.subCategoryPages == nil or settingsFrame.subCategoryPages[1] == nil
            or settingsFrame.subCategoryPages[1].parent == nil
            or settingsFrame.subCategoryBox == nil
            or settingsFrame.subCategoryTabs == nil
            or settingsFrame.subCategoryPaging == nil
            or InGameMenuSettingsFrame == nil
            or InGameMenuSettingsFrame.SUB_CATEGORY == nil
            or InGameMenuSettingsFrame.HEADER_SLICES == nil
            or InGameMenuSettingsFrame.HEADER_TITLES == nil then
        Logging.warning(AOMenuPage.LOG .. "Tab-Einbau fehlgeschlagen: Einstellungs-Frame unvollstaendig.")
        return
    end

    if tab.setText ~= nil then
        tab:setText(t("ao_tabTitle"))
    end

    -- nur Klonvorlagen
    if self.aoSectionPrefab ~= nil then self.aoSectionPrefab:setVisible(false) end
    if self.aoRowPrefab     ~= nil then self.aoRowPrefab:setVisible(false)     end

    -- Zeilen abwechselnd hinterlegen
    local function updateAlternating(layout)
        if layout == nil or InGameMenuSettingsFrame == nil then
            return
        end
        local farben = InGameMenuSettingsFrame.COLOR_ALTERNATING
        if farben == nil then
            return
        end
        local wechsel = true
        for _, container in ipairs(layout.elements or {}) do
            if container.name == "sectionHeader" then
                wechsel = true
            elseif container.getIsVisibleNonRec == nil
                    or container:getIsVisibleNonRec() then
                if container.setImageColor ~= nil and type(farben[wechsel]) == "table" then
                    container:setImageColor(nil, unpack(farben[wechsel]))
                end
                wechsel = not wechsel
            end
        end
        if layout.invalidateLayout ~= nil then
            layout:invalidateLayout()
        end
    end
    self._updateAlternating = updateAlternating

    self:baueZeilen()

    -- FocusManager braucht den Frame-Namen
    self.name = settingsFrame.name

    -- sonst stehen sie als leere Zeilen da
    if self.aoRowPrefab ~= nil and self.aoRowPrefab.delete ~= nil then
        self.aoRowPrefab:delete()
        self.aoRowPrefab = nil
    end
    if self.aoSectionPrefab ~= nil and self.aoSectionPrefab.delete ~= nil then
        self.aoSectionPrefab:delete()
        self.aoSectionPrefab = nil
    end

    updateAlternating(self.aoLayout)

    -- Tab hinten anhaengen
    local position = #settingsFrame.subCategoryPages + 1

    local function einfuegen(element, ziel, pos)
        if element.parent ~= nil then
            element.parent:removeElement(element)
        end
        table.insert(ziel.elements, pos, element)
        element.parent = ziel
    end

    einfuegen(seite, settingsFrame.subCategoryPages[1].parent, position)
    einfuegen(tab,   settingsFrame.subCategoryBox,             position)

    table.insert(settingsFrame.subCategoryPages, position, seite)
    table.insert(settingsFrame.subCategoryTabs,  position, tab)

    -- Reiter ist beim Laden leer und schmal, erst setText + updateSize geben
    -- ihm die volle Breite
    if tab.setText ~= nil then
        tab:setText(t("ao_tabTitle"))
    end
    if tab.updateSize ~= nil then
        tab:updateSize()
    end

    local hintergrund = nil
    if tab.elements ~= nil then
        for _, kind in ipairs(tab.elements) do
            if kind.name == "background" then
                hintergrund = kind
                break
            end
        end
    end
    if hintergrund ~= nil and hintergrund.setSize ~= nil and tab.size ~= nil then
        hintergrund:setSize(tab.size[1], tab.size[2])
    end

    if settingsFrame.subCategoryBox ~= nil and settingsFrame.subCategoryBox.invalidateLayout ~= nil then
        settingsFrame.subCategoryBox:invalidateLayout()
    end

    InGameMenuSettingsFrame.SUB_CATEGORY.AGRAR_OEKONOMIE = position

    -- Slice braucht die Form "prefix.id", leer gibt eine Warnung. Also ein
    -- vorhandenes Symbol leihen.
    local slices = InGameMenuSettingsFrame.HEADER_SLICES
    local slice  = ""
    for _, vorhanden in ipairs(slices) do
        if type(vorhanden) == "string"
                and string.find(vorhanden, ".", 1, true) ~= nil then
            slice = vorhanden
            break
        end
    end
    if slice == "" then
        Logging.info(AOMenuPage.LOG ..
            "Kein gueltiger Header-Slice gefunden - Kopfzeile bleibt ohne Symbol.")
    end

    table.insert(slices, position, slice)

    -- HEADER_TITLES wird im g_i18n des Basisspiels gesucht, unser Schluessel
    -- fehlt dort. Deshalb ein vorhandener Schluessel; zu sehen ist er nie,
    -- weil update() unten die Kopfzeile ueberschreibt.
    local titles = InGameMenuSettingsFrame.HEADER_TITLES
    local titel  = "ao_tabTitle"
    for _, vorhanden in ipairs(titles) do
        if type(vorhanden) == "string" and vorhanden ~= "" then
            titel = vorhanden
            break
        end
    end

    -- Notnagel bei leerer Liste, wirkt aber nur im eigenen g_i18n
    if titel == "ao_tabTitle" and g_i18n ~= nil and g_i18n.setText ~= nil then
        g_i18n:setText("ao_tabTitle", t("ao_tabTitle"))
    end

    table.insert(titles, position, titel)

    if settingsFrame.updateAbsolutePosition ~= nil then
        settingsFrame:updateAbsolutePosition()
    end

    -- FocusManager: getDescendants kurz auf unsere Seite umbiegen, damit
    -- exposeControlsAsFields unsere Regler findet
    local aktuelleGui   = FocusManager.currentGui
    local getDescendants = settingsFrame.getDescendants

    if settingsFrame.exposeControlsAsFields ~= nil and seite.getDescendants ~= nil then
        settingsFrame.getDescendants = function() return seite:getDescendants() end
        settingsFrame:exposeControlsAsFields(settingsFrame.name)
        settingsFrame.getDescendants = getDescendants
    end

    if seite.setTarget ~= nil then
        seite:setTarget(settingsFrame, seite.target)
    end
    if tab.setTarget ~= nil then
        tab:setTarget(settingsFrame,   tab.target)
    end

    if FocusManager.setGui ~= nil and FocusManager.removeElement ~= nil
            and FocusManager.loadElementFromCustomValues ~= nil then
        FocusManager:setGui(settingsFrame.name)
        FocusManager:removeElement(seite)
        FocusManager:removeElement(tab)
        FocusManager:loadElementFromCustomValues(seite)
        FocusManager:loadElementFromCustomValues(tab)
        FocusManager:setGui(aktuelleGui)
    end

    local selbst = self

    -- Server kann inzwischen etwas geaendert haben
    settingsFrame.onFrameOpen = Utils.appendedFunction(
        settingsFrame.onFrameOpen,
        function()
            selbst:populate()
            if selbst.aoLayout ~= nil and selbst.aoLayout.invalidateLayout ~= nil then
                selbst.aoLayout:invalidateLayout()
            end
        end)

    -- Kopfzeile wird jeden Frame neu gesetzt, also hier drueberschreiben
    settingsFrame.update = Utils.appendedFunction(
        settingsFrame.update,
        function(sf)
            if AOMenuPage.istUnserTab(sf) then
                if sf.categoryHeaderText ~= nil and sf.categoryHeaderText.setText ~= nil then
                    sf.categoryHeaderText:setText(AOMenuPage.getKopfzeile())
                end
            end
        end)

    settingsFrame.subCategoryPaging.onClickCallback = Utils.overwrittenFunction(
        settingsFrame.subCategoryPaging.onClickCallback,
        function(pagingElem, superFunc, state)
            local ret = superFunc(pagingElem, state)
            local wert = pagingElem.texts ~= nil and pagingElem.texts[state] or nil
            if wert ~= nil and tonumber(wert) == InGameMenuSettingsFrame.SUB_CATEGORY.AGRAR_OEKONOMIE then
                selbst:onTabOpen(settingsFrame)
            end
            return ret
        end)

    self.injiziert = true
    Logging.info(AOMenuPage.LOG .. "Eigener Einstellungs-Tab eingefuegt (Position %d, %d Regler).",
        position, #self.controls)
end

-- Zeilen ------------------------------------------------------------------------

function AOMenuPage:baueZeilen()
    if AOSettingsPage == nil or self.aoRowPrefab == nil or self.aoLayout == nil then
        Logging.warning(AOMenuPage.LOG .. "Vorlagen oder Definition fehlen - keine Regler erstellt.")
        return
    end

    local selbst = self
    local nummer = 0

    local function abschnitt(gruppe)
        local prefab = selbst.aoSectionPrefab
        if prefab == nil then
            return
        end
        local kopf = prefab:clone(selbst.aoLayout)
        if kopf == nil then
            return
        end
        kopf:setVisible(true)
        kopf:setText(t(gruppe.titel))
        kopf.focusId = FocusManager:serveAutoFocusId()

        -- Automatik-Kopf, Text kommt in populate()
        if gruppe.dynamisch then
            table.insert(selbst.dynamischeKoepfe, kopf)
            if AOAutomatik ~= nil and AOAutomatik.getKopfText ~= nil then
                if kopf.setText ~= nil then
                    kopf:setText(AOAutomatik.getKopfText())
                end
            end
        end
    end

    local function zeile(eintrag)
        local modul = AOSettings.getModul(eintrag.modul)
        local cfg   = modul ~= nil and modul.getCfg() or nil

        -- Modul nicht geladen
        if cfg == nil or cfg[eintrag.key] == nil then
            return
        end

        local box = selbst.aoRowPrefab:clone(selbst.aoLayout)
        if box == nil then
            return
        end

        nummer = nummer + 1
        box:setVisible(true)
        AOUIHelper.updateFocusIds(box)

        local id           = string.format("AO_%d", nummer)
        local callbackName = string.format("AO_onChange_%d", nummer)
        box.id = id .. "Box"

        local werte, texte = AOSettingsPage.baueWerte(eintrag)

        local option = box.elements[1]
        if option ~= nil then
            option.id              = id
            option.focusOnHighlight = true
            option.target          = selbst

            -- raiseCallback erwartet hier eine Funktion, ein Name tut nichts
            option.onClickCallback = function(_, newState)
                local ziel = selbst[callbackName]
                if ziel ~= nil then
                    ziel(selbst, newState)
                end
            end

            option:setDisabled(false)

            -- Tooltip
            if option.elements ~= nil and option.elements[1] ~= nil then
                if option.elements[1].setText ~= nil then
                    option.elements[1]:setText(t(eintrag.tipp))
                end
            end

            if option.setTexts ~= nil and texte ~= nil then
                option:setTexts(texte)
            end
            if option.setState ~= nil then
                option:setState(AOSettingsPage.findeIndex(werte, cfg[eintrag.key]))
            end
        end

        local label = box.elements[2]
        if label ~= nil then
            label:setVisible(true)
            label:setText(t(eintrag.label))
        end

        local gemerkterEintrag = eintrag
        local gemerkteWerte    = werte
        selbst[callbackName] = function(_, newState)
            if not AOMenuPage.darfAendern() then
                return
            end
            local neu = gemerkteWerte[newState]
            if neu == nil then
                return
            end
            AOSettings.applyValue(gemerkterEintrag.modul, gemerkterEintrag.key, neu)
            AOSettings.onLocalChange()
        end

        box.aoEintrag = eintrag
        box.aoWerte   = werte
        table.insert(selbst.controls, box)
    end

    -- Feste Plaetze fuer einzelne Produktionen, die Zahl aendert sich ja
    -- im Spiel. Belegt werden sie in fuelleProduktionen().
    local function produktionsZeilen()
        if AOProduktion == nil then
            return
        end
        local werte, texte = {}, {}
        for i, w in ipairs(AOProduktion.EINZEL_WERTE) do
            werte[i] = w
            if w == 0 then
                texte[i] = t("ao_opt_wieAlle")
            else
                texte[i] = string.format("x%.2f", w)
            end
        end

        for platz = 1, AOProduktion.MAX_ZEILEN do
            local box = selbst.aoRowPrefab:clone(selbst.aoLayout)
            if box == nil then
                return
            end
            nummer = nummer + 1
            AOUIHelper.updateFocusIds(box)

            local id           = string.format("AO_%d", nummer)
            local callbackName = string.format("AO_onChange_%d", nummer)
            box.id = id .. "Box"

            local option = box.elements[1]
            if option ~= nil then
                option.id               = id
                option.focusOnHighlight = true
                option.target           = selbst
                option.onClickCallback  = function(_, newState)
                    local ziel = selbst[callbackName]
                    if ziel ~= nil then
                        ziel(selbst, newState)
                    end
                end
                option:setDisabled(false)
                if option.elements ~= nil and option.elements[1] ~= nil
                        and option.elements[1].setText ~= nil then
                    option.elements[1]:setText(t("ao_ui_prodEinzel_t"))
                end
                if option.setTexts ~= nil then
                    option:setTexts(texte)
                end
            end

            local gemerkteBox = box
            selbst[callbackName] = function(_, newState)
                if not AOMenuPage.darfAendern() then
                    return
                end
                local pp  = gemerkteBox.aoProduktion
                local neu = werte[newState]
                if pp == nil or neu == nil then
                    return
                end
                AOProduktion.setzeEinzel(pp, neu)
            end

            box.aoProdPlatz = platz
            box.aoWerte     = werte
            box:setVisible(false)
            table.insert(selbst.controls, box)
            table.insert(selbst.prodZeilen, box)
        end
    end

    selbst.prodZeilen = {}

    for _, gruppe in ipairs(AOSettingsPage.ABSCHNITTE) do
        abschnitt(gruppe)
        for _, eintrag in ipairs(gruppe.eintraege) do
            zeile(eintrag)
        end
        if gruppe.produktionen then
            produktionsZeilen()
        end
    end
end

function AOMenuPage:fuelleProduktionen()
    if AOProduktion == nil or self.prodZeilen == nil then
        return
    end
    local eigene = AOProduktion.getEigene()
    if #eigene > #self.prodZeilen then
        Logging.info(AOMenuPage.LOG .. "%d Produktionen, im Reiter Platz fuer %d - der Rest " ..
            "folgt dem gemeinsamen Faktor.", #eigene, #self.prodZeilen)
    end
    for platz, box in ipairs(self.prodZeilen) do
        local pp = eigene[platz]
        box.aoProduktion = pp
        if pp == nil then
            box:setVisible(false)
        else
            box:setVisible(true)
            local label = box.elements[2]
            if label ~= nil and label.setText ~= nil then
                label:setVisible(true)
                label:setText(AOProduktion.getName(pp))
            end
            local option = box.elements[1]
            if option ~= nil and option.setState ~= nil then
                local einzel = AOProduktion.getEinzel(pp) or 0
                option:setState(AOSettingsPage.findeIndex(box.aoWerte, einzel))
            end
        end
    end
end

-- Auffrischen ------------------------------------------------------------------

function AOMenuPage:populate()
    if AOAutomatik ~= nil and AOAutomatik.getKopfText ~= nil then
        for _, kopf in ipairs(self.dynamischeKoepfe or {}) do
            if kopf ~= nil and kopf.setText ~= nil then
                kopf:setText(AOAutomatik.getKopfText())
            end
        end
    end

    -- Admin-Login waehrend der Sitzung moeglich
    local gesperrt = not AOMenuPage.darfAendern()

    for _, box in ipairs(self.controls) do
        local eintrag = box.aoEintrag
        if box.elements ~= nil and box.elements[1] ~= nil
                and box.elements[1].setDisabled ~= nil then
            box.elements[1]:setDisabled(gesperrt)
        end
        if eintrag ~= nil and box.elements ~= nil and box.elements[1] ~= nil then
            local modul = AOSettings.getModul(eintrag.modul)
            local cfg   = modul ~= nil and modul.getCfg() or nil
            if cfg ~= nil and cfg[eintrag.key] ~= nil and box.elements[1].setState ~= nil then
                box.elements[1]:setState(
                    AOSettingsPage.findeIndex(box.aoWerte, cfg[eintrag.key]))
            end
        end
    end

    self:fuelleProduktionen()
end

function AOMenuPage:onTabOpen(settingsFrame)
    if settingsFrame ~= nil then
        if settingsFrame.updateAbsolutePosition ~= nil then
            settingsFrame:updateAbsolutePosition()
        end
        if settingsFrame.categoryHeaderText ~= nil
                and settingsFrame.categoryHeaderText.setText ~= nil then
            settingsFrame.categoryHeaderText:setText(AOMenuPage.getKopfzeile())
        end
    end
    self:populate()
    if self.aoLayout ~= nil and self.aoLayout.invalidateLayout ~= nil then
        self.aoLayout:invalidateLayout()
    end
    if self._updateAlternating ~= nil then
        self._updateAlternating(self.aoLayout)
    end
end

-- Tab-Button -------------------------------------------------------------------

function AOMenuPage:onClickAoTab()
    local seite = getPage()
    if seite == nil then
        return
    end

    local sf = g_inGameMenu ~= nil and g_inGameMenu.pageSettings or nil
    if sf == nil or InGameMenuSettingsFrame == nil or InGameMenuSettingsFrame.SUB_CATEGORY == nil then
        return
    end

    -- setState will den Paging-State, nicht die Seitennummer
    local ziel   = InGameMenuSettingsFrame.SUB_CATEGORY.AGRAR_OEKONOMIE
    local state  = ziel
    local paging = sf.subCategoryPaging
    if paging ~= nil and paging.texts ~= nil then
        for st, txt in ipairs(paging.texts) do
            if tonumber(txt) == ziel then
                state = st
                break
            end
        end
    end

    if paging == nil or paging.setState == nil or state == nil then
        return
    end
    paging:setState(state, true)
    seite:onTabOpen(sf)
end
