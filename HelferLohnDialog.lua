-- HelferLohnDialog.lua
-- Einstellungsfenster fuer den Helfer-Arbeitsmarkt. Gespeichert und gesynct
-- wird ueber HelferLohnSettings.
-- OGW

HelferLohnDialog = {}
local HelferLohnDialog_mt = Class(HelferLohnDialog, MessageDialog)

local MONEY_MAX  = 3000
local MONEY_STEP = 50

local function moneyValues()
    local v = {}
    for x = 0, MONEY_MAX, MONEY_STEP do
        v[#v + 1] = x
    end
    return v
end

local function moneyTexts(values)
    local t = {}
    for i, x in ipairs(values) do
        t[i] = HelferLohn.formatGeld(x)
    end
    return t
end

local function nearestIndex(values, cur)
    local bi, bd = 1, math.huge
    for i, x in ipairs(values) do
        local d = math.abs(x - (cur or 0))
        if d < bd then bd = d; bi = i end
    end
    return bi
end

local function exactIndex(values, cur)
    for i, x in ipairs(values) do
        if x == cur then return i end
    end
    return 1
end

-- im MP nur Admins, der Server prueft beim Empfang nochmal
local function darfAendern()
    if AOMenuPage ~= nil and AOMenuPage.darfAendern ~= nil then
        return AOMenuPage.darfAendern()
    end
    return true
end

function HelferLohnDialog.new(target, customMt)
    local self = HelferLohnDialog:superClass().new(target, customMt or HelferLohnDialog_mt)
    self.optInfo = {}
    self.chkKey  = {}
    return self
end

function HelferLohnDialog:onOpen()
    HelferLohnDialog:superClass().onOpen(self)
    self:buildControls()
end

function HelferLohnDialog:onClose()
    HelferLohnDialog:superClass().onClose(self)
end

function HelferLohnDialog:buildControls()
    self.optInfo = {}
    self.chkKey  = {}
    local T  = HelferLohn.getText
    local mv = moneyValues()
    local mt = moneyTexts(mv)

    local function setupMulti(el, key, values, texts, isMoney)
        if el == nil then return end
        if el.setTexts ~= nil then el:setTexts(texts) end
        local cfgWert = nil
        if HelferLohn.CFG ~= nil then cfgWert = HelferLohn.CFG[key] end
        local idx
        if isMoney then
            if type(cfgWert) ~= "number" then cfgWert = 0 end
            idx = nearestIndex(values, cfgWert)
        else
            idx = exactIndex(values, cfgWert)
        end
        if el.setState ~= nil then el:setState(idx, nil, true) end
        self.optInfo[el] = { key = key, values = values }
    end

    setupMulti(self.optModus, "bezahlModus", { 0, 1 },
        { T("hl_mStunde", "Stundenlohn"), T("hl_mFest", "Festpreis pro Auftrag") }, false)
    setupMulti(self.optSchwierigkeit, "schwierigkeit", { 0, 1, 2, 3, 4 },
        { T("hl_diffAuto", "Auto (nach Spiel-Wirtschaft)"), T("hl_diffLeicht", "Leicht (guenstig)"),
          T("hl_diffNormal", "Normal"), T("hl_diffSchwer", "Schwer (teuer)"), T("hl_diffEigen", "Eigen") }, false)
    setupMulti(self.optStufe, "lohnStufe", { 0, 1, 2, 3 },
        { T("hl_optAzubi", "Azubi (guenstig)"), T("hl_optQuer", "Quereinsteiger (normal)"),
          T("hl_optAusgelernt", "Ausgelernter (teuer)"), T("hl_optEigen", "Eigener Wert") }, false)
    setupMulti(self.optFestLohn,       "festLohn",       mv, mt, true)
    setupMulti(self.optPreisLeicht,    "preisLeicht",    mv, mt, true)
    setupMulti(self.optPreisMittel,    "preisMittel",    mv, mt, true)
    setupMulti(self.optPreisBoden,     "preisBoden",     mv, mt, true)
    setupMulti(self.optPreisPressen,   "preisPressen",   mv, mt, true)
    setupMulti(self.optPreisDreschen,  "preisDreschen",  mv, mt, true)
    setupMulti(self.optPreisHaeckseln, "preisHaeckseln", mv, mt, true)

    local function setupBool(el, key)
        if el == nil then return end
        if el.setIsChecked ~= nil and HelferLohn.CFG ~= nil then
            el:setIsChecked(HelferLohn.CFG[key] == true, true)
        end
        self.chkKey[el] = key
    end
    setupBool(self.chkAktiv,     "aktiv")
    setupBool(self.chkZufall,    "zufallVerfuegbar")
    setupBool(self.chkGratis,    "gratisBetrieb")
    setupBool(self.chkNurErfolg, "nurBeiErfolg")

    local gesperrt = not darfAendern()
    for el in pairs(self.optInfo) do
        if el.setDisabled ~= nil then el:setDisabled(gesperrt) end
    end
    for el in pairs(self.chkKey) do
        if el.setDisabled ~= nil then el:setDisabled(gesperrt) end
    end
    if self.dialogTitleElement ~= nil and self.dialogTitleElement.setText ~= nil then
        local titel = T("hl_menuTitle", "Helfer-Arbeitsmarkt")
        if gesperrt then
            titel = titel .. "  (" .. T("ao_ui_nurAdmin", "nur fuer Admins") .. ")"
        end
        self.dialogTitleElement:setText(titel)
    end

    self:applyRowColors()
end

-- ohne eigene Farbe sind die Zeilen weiss und der helle Text unlesbar
function HelferLohnDialog:applyRowColors()
    if self.hlLayout == nil or self.hlLayout.elements == nil then return end
    local cols = (InGameMenuSettingsFrame ~= nil and InGameMenuSettingsFrame.COLOR_ALTERNATING) or nil
    local alt = true
    for _, c in ipairs(self.hlLayout.elements) do
        if c.name == "sectionHeader" then
            alt = true
        elseif c.setImageColor ~= nil then
            if cols ~= nil and type(cols[alt]) == "table" then
                c:setImageColor(nil, unpack(cols[alt]))
            elseif alt then
                c:setImageColor(nil, 0, 0, 0, 0.0)
            else
                c:setImageColor(nil, 1, 1, 1, 0.07)
            end
            alt = not alt
        end
    end
    if self.hlLayout.invalidateLayout ~= nil then self.hlLayout:invalidateLayout() end
end

-- Callbacks ------------------------------------------------------------------

function HelferLohnDialog:onClickCheckbox(state, checkboxElement)
    if not darfAendern() then return end
    local key = self.chkKey and self.chkKey[checkboxElement]
    if key == nil or HelferLohnSettings == nil then return end
    local checked
    if CheckedOptionElement ~= nil and CheckedOptionElement.STATE_CHECKED ~= nil then
        checked = (state == CheckedOptionElement.STATE_CHECKED)
    else
        checked = (state == 2 or state == true)
    end
    HelferLohnSettings.applyValue(key, checked)
    HelferLohnSettings.onLocalChange()
end

function HelferLohnDialog:onClickMultiOption(state, optionElement)
    if not darfAendern() then return end
    local info = self.optInfo and self.optInfo[optionElement]
    if info == nil or HelferLohnSettings == nil then return end
    local v = info.values[state]
    if v == nil then return end
    HelferLohnSettings.applyValue(info.key, v)

    -- Preset setzt alle Festpreise, ein Preis von Hand schaltet auf "Eigen"
    local rebuild = false
    if info.key == "schwierigkeit" then
        if HelferLohn.applyDifficulty ~= nil then HelferLohn.applyDifficulty(v) end
        rebuild = true
    elseif HelferLohn.PREIS_BASIS ~= nil and HelferLohn.PREIS_BASIS[info.key] ~= nil then
        HelferLohnSettings.applyValue("schwierigkeit", HelferLohn.SCHWER_EIGEN)
        rebuild = true
    end

    HelferLohnSettings.onLocalChange()

    if rebuild then
        self:buildControls()
    end
end

function HelferLohnDialog:onClickBack()
    self:close()
    return true
end
