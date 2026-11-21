-- AOHofPC.lua
-- Der Hof-PC: ein Fenster wie ein Rechner im Buero, auf dem Kassenbuch,
-- Fuhrpark, Abgaben und, falls installiert, Farm Overview als Programme
-- laufen. Hier stehen Rahmen, Startseite und das Oeffnen per Taste, die
-- uebrigen Seiten liegen in AOHofPCKasse, AOHofPCFuhrpark und AOHofPCAbgaben.
-- OGW

AOHofPC = {}
local AOHofPC_mt = Class(AOHofPC, MessageDialog)

AOHofPC.LOG    = "[AgrarOekonomie] "
AOHofPC.NAME   = "AOHofPCUI"
AOHofPC.XML    = "gui/AOHofPC.xml"
AOHofPC.FO_MOD = "FS25_FarmOverview"
AOHofPC.modDir = g_currentModDirectory

AOHofPC.START    = 1
AOHofPC.KASSE    = 2
AOHofPC.FUHRPARK = 3
AOHofPC.ABGABEN  = 4
AOHofPC.OVERVIEW = 5
AOHofPC.SEITEN   = 5

AOHofPC.geladen     = false
AOHofPC.tastenHook  = false
AOHofPC.tasteId     = nil
AOHofPC.offen       = nil
AOHofPC.letzteSeite = 1

AOHofPC.FARBE = {
    ein      = { 0.165, 0.471, 0.839, 1 },
    aus      = { 0.922, 0.408, 0.204, 1 },
    inv      = { 0.106, 0.686, 0.478, 1 },
    kredit   = { 0.384, 0.314, 0.839, 1 },
    neg      = { 0.890, 0.286, 0.282, 1 },
    grau     = { 0.62, 0.62, 0.62, 1 },
    weiss    = { 1, 1, 1, 1 },
    gut      = { 0.45, 0.80, 0.30, 1 },
    mittel   = { 0.95, 0.78, 0.25, 1 },
    akzent   = { 0.376, 0.659, 0.290, 1 },
    tabAktiv = { 0.376, 0.659, 0.290, 0.30 },
    tabRuhe  = { 1, 1, 1, 0.05 },
}

local STAND_INDEX = {}

local function standWert(paket, schluessel)
    if paket == nil or paket.stand == nil or AOBericht == nil or AOBericht.STAND == nil then
        return nil
    end
    if next(STAND_INDEX) == nil then
        for i, k in ipairs(AOBericht.STAND) do
            STAND_INDEX[k] = i
        end
    end
    local i = STAND_INDEX[schluessel]
    if i == nil then
        return nil
    end
    return paket.stand[i]
end
AOHofPC.standWert = standWert

function AOHofPC.t(schluessel)
    if AOSettingsPage ~= nil and AOSettingsPage.getText ~= nil then
        return AOSettingsPage.getText(schluessel)
    end
    return schluessel
end

function AOHofPC.vorlage(schluessel, ...)
    local text   = AOHofPC.t(schluessel)
    local werte  = { ... }
    local anzahl = select(2, string.gsub(text, "%%s", ""))
    if anzahl ~= #werte then
        return text
    end
    for i, w in ipairs(werte) do
        werte[i] = tostring(w)
    end
    return string.format(text, unpack(werte))
end

function AOHofPC.geld(betrag)
    if betrag == nil then
        return "-"
    end
    return AgrarOekonomie.formatGeld(betrag)
end

function AOHofPC.zahl(wert, stellen)
    if wert == nil then
        return "-"
    end
    if g_i18n ~= nil and g_i18n.formatNumber ~= nil then
        return g_i18n:formatNumber(wert, stellen or 0)
    end
    return string.format("%." .. tostring(stellen or 0) .. "f", wert)
end

function AOHofPC.text(element, text, farbe)
    if element == nil then
        return
    end
    if element.setText ~= nil then
        element:setText(text or "")
    end
    if farbe ~= nil and element.setTextColor ~= nil then
        element:setTextColor(farbe[1], farbe[2], farbe[3], farbe[4] or 1)
    end
end

function AOHofPC.zeigen(element, sichtbar)
    if element ~= nil and element.setVisible ~= nil then
        element:setVisible(sichtbar == true)
    end
end

function AOHofPC.farbe(element, farbe)
    if element ~= nil and element.setImageColor ~= nil and farbe ~= nil then
        element:setImageColor(nil, farbe[1], farbe[2], farbe[3], farbe[4] or 1)
    end
end

local function merkeMasse(element)
    if element.aoVoll == nil and element.size ~= nil and element.position ~= nil then
        element.aoVoll = { element.size[1], element.size[2] }
        element.aoX0 = element.position[1]
        element.aoY0 = element.position[2]
    end
    return element.aoVoll
end

function AOHofPC.breite(element, anteil)
    if element == nil or element.setSize == nil then
        return 0
    end
    local voll = merkeMasse(element)
    if voll == nil then
        return 0
    end
    anteil = math.max(0, math.min(1, anteil or 0))
    if anteil < 0.004 then
        element:setVisible(false)
        return 0
    end
    element:setVisible(true)
    element:setSize(voll[1] * anteil, voll[2])
    return voll[1] * anteil
end

function AOHofPC.hoehe(element, anteil)
    if element == nil or element.setSize == nil then
        return
    end
    local voll = merkeMasse(element)
    if voll == nil then
        return
    end
    anteil = math.max(0, math.min(1, anteil or 0))
    if anteil < 0.01 then
        element:setVisible(false)
        return
    end
    element:setVisible(true)
    element:setSize(voll[1], voll[2] * anteil)
    if element.setPosition ~= nil and element.aoY0 ~= nil then
        element:setPosition(element.position[1], element.aoY0 - voll[2] * (1 - anteil))
    end
end

function AOHofPC.verschiebe(element, versatz)
    if element == nil or element.setPosition == nil then
        return
    end
    merkeMasse(element)
    if element.aoX0 ~= nil then
        element:setPosition(element.aoX0 + versatz, element.position[2])
    end
end

function AOHofPC.optionen(element, texte, stand)
    if element == nil or element.setTexts == nil then
        return
    end
    if #texte == 0 then
        texte = { "-" }
    end
    element:setTexts(texte)
    if element.setState ~= nil then
        element:setState(math.max(1, math.min(stand or 1, #texte)), false)
    end
end

function AOHofPC.monatName(monat)
    if AOBericht ~= nil and AOBericht.monatsName ~= nil then
        return AOBericht.monatsName(monat)
    end
    return tostring(monat)
end

function AOHofPC.eigeneFarm()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        local farmId = g_currentMission:getFarmId()
        if type(farmId) == "number" and farmId >= 1 then
            return farmId
        end
    end
    return nil
end

function AOHofPC.foUmgebung()
    local env = nil
    if getfenv ~= nil then
        local global = getfenv(0)
        if type(global) == "table" then
            env = global[AOHofPC.FO_MOD]
        end
    end
    if env == nil then
        env = _G[AOHofPC.FO_MOD]
    end
    if type(env) == "table" and type(env.FruchtfolgeAdvisor) == "table"
            and type(env.FruchtfolgeAdvisor.getSectionRows) == "function" then
        return env
    end
    return nil
end

function AOHofPC.new(target, customMt)
    local self = MessageDialog.new(target, customMt or AOHofPC_mt)
    self.seite = AOHofPC.letzteSeite
    self.uhrTakt = 0
    self.foTakt = 0
    self.texturen = false
    self.kb = { ansicht = 1, gewaehlt = nil, zeitraeume = {} }
    self.fp = { wahl = 1, sort = 1, zeigen = 1, start = 0, auswahl = nil, liste = {} }
    self.fo = { bereich = 1, start = 0, zeilen = {}, aufgeklappt = {}, feldOffen = nil }
    return self
end

function AOHofPC:texturenSetzen()
    if self.texturen or Utils == nil or Utils.getFilename == nil then
        return
    end
    local weiss = Utils.getFilename("images/white.dds", AOHofPC.modDir or "")
    local monitor = Utils.getFilename("images/hofpc.dds", AOHofPC.modDir or "")
    if self.pcBild ~= nil and self.pcBild.setImageFilename ~= nil then
        self.pcBild:setImageFilename(monitor)
    end
    local dateien = {
        aoPcFlaeche     = weiss,
        aoPcPfeilHoch   = Utils.getFilename("images/pfeil_hoch.dds", AOHofPC.modDir or ""),
        aoPcPfeilRunter = Utils.getFilename("images/pfeil_runter.dds", AOHofPC.modDir or ""),
    }
    local function pruefe(element)
        local datei = dateien[element.profile or ""]
        if datei ~= nil and element.setImageFilename ~= nil then
            element:setImageFilename(datei)
        end
        for _, kind in ipairs(element.elements or {}) do
            pruefe(kind)
        end
    end
    if self.dialogElement ~= nil then
        pruefe(self.dialogElement)
    end
    self.texturen = true
end

function AOHofPC:onOpen()
    AOHofPC.superClass().onOpen(self)
    AOHofPC.offen = self
    self:texturenSetzen()

    self.foDa = AOHofPC.foUmgebung() ~= nil
    AOHofPC.zeigen(self.tab5, self.foDa)
    AOHofPC.zeigen(self.tabBg5, self.foDa)
    AOHofPC.zeigen(self.tabStrich5, self.foDa)
    if self.seite == AOHofPC.OVERVIEW and not self.foDa then
        self.seite = AOHofPC.START
    end

    self:kbVorbereiten()
    self:fpVorbereiten()
    self:foVorbereiten()
    self:zeigeSeite(self.seite)
end

function AOHofPC:onClose()
    AOHofPC.letzteSeite = self.seite
    AOHofPC.offen = nil
    AOHofPC.superClass().onClose(self)
end

function AOHofPC:onClickBack()
    self:close()
    return true
end

function AOHofPC.fenster(zustand, anzahl, zeilen)
    local letzter = math.max(0, anzahl - zeilen)
    zustand.start = math.max(0, math.min(zustand.start or 0, letzter))
    local seiten = math.max(1, math.ceil(anzahl / zeilen))
    local seite = math.floor(zustand.start / zeilen) + 1
    if zustand.start >= letzter then
        seite = seiten
    end
    return zustand.start, math.min(seite, seiten), seiten
end

function AOHofPC:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    local benutzt = AOHofPC:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
    if isDown and Input ~= nil and Input.isMouseButtonPressed ~= nil then
        local schritt = 0
        if Input.isMouseButtonPressed(Input.MOUSE_BUTTON_WHEEL_UP) then
            schritt = -1
        elseif Input.isMouseButtonPressed(Input.MOUSE_BUTTON_WHEEL_DOWN) then
            schritt = 1
        end
        if schritt ~= 0 then
            self:blaettern(schritt)
            benutzt = true
        end
    end
    return benutzt
end

function AOHofPC:onClickRollHoch()
    self:blaettern(-1)
end

function AOHofPC:onClickRollRunter()
    self:blaettern(1)
end

function AOHofPC:rollleiste(praefix, erstes, anzahl, zeilen)
    local mehr = anzahl > zeilen
    for _, teil in ipairs({ "Bahn", "Griff", "Hoch", "Runter", "KnopfHoch", "KnopfRunter" }) do
        AOHofPC.zeigen(self[praefix .. teil], mehr)
    end
    local griff = self[praefix .. "Griff"]
    if not mehr or griff == nil or griff.setSize == nil or griff.setPosition == nil then
        return
    end
    local voll = merkeMasse(griff)
    if voll == nil or griff.aoY0 == nil then
        return
    end
    local groesse = math.max(voll[2] * zeilen / anzahl, voll[2] * 0.08)
    local weg = (voll[2] - groesse) * math.min(1, erstes / math.max(1, anzahl - zeilen))
    griff:setSize(voll[1], groesse)
    griff:setPosition(griff.aoX0, griff.aoY0 - weg)
end

function AOHofPC.stallZurueck(dt)
    local w = AOHofPC.stallWache
    if w == nil or g_gui == nil then
        return
    end
    w.zeit = w.zeit + (dt or 0)
    if not w.offen then
        if g_gui.currentGuiName == "AnimalScreen" then
            w.offen = true
        elseif w.zeit > 3000 then
            AOHofPC.stallWache = nil
        end
        return
    end
    if g_gui.currentGuiName == "AnimalScreen" then
        w.zu = 0
        return
    end
    if g_gui.currentGui ~= nil and g_gui.currentGuiName ~= "InGameMenu" then
        AOHofPC.stallWache = nil
        return
    end
    w.zu = (w.zu or 0) + (dt or 0)
    if w.zu < 150 then
        return
    end
    AOHofPC.stallWache = nil
    if g_gui.currentGui ~= nil and g_gui.changeScreen ~= nil then
        g_gui:changeScreen(nil)
    end
    AOHofPC.umschalten()
end

function AOHofPC:blaettern(schritt)
    if self.seite == AOHofPC.KASSE then
        self.kb.start = (self.kb.start or 0) + schritt * 2
        self:fuelleKasse()
    elseif self.seite == AOHofPC.FUHRPARK then
        self.fp.start = (self.fp.start or 0) + schritt * 2
        self:fuelleFuhrpark()
    elseif self.seite == AOHofPC.OVERVIEW then
        self.fo.start = (self.fo.start or 0) + schritt * 3
        self:fuelleOverview()
    end
end

function AOHofPC:onClickTab(element)
    for i = 1, AOHofPC.SEITEN do
        if self["tab" .. i] == element then
            self:zeigeSeite(i)
            return
        end
    end
end

function AOHofPC:zeigeSeite(nr)
    self.seite = nr
    for i = 1, AOHofPC.SEITEN do
        AOHofPC.zeigen(self["seite" .. i], i == nr)
        AOHofPC.farbe(self["tabBg" .. i], i == nr and AOHofPC.FARBE.tabAktiv or AOHofPC.FARBE.tabRuhe)
        AOHofPC.zeigen(self["tabStrich" .. i], i == nr and (i ~= AOHofPC.OVERVIEW or self.foDa))
    end
    self:anfordern(nr)
    self:fuelle()
end

function AOHofPC:anfordern(nr)
    if nr == AOHofPC.START or nr == AOHofPC.KASSE then
        if AOKassenbuch ~= nil and AOKassenbuch.anfordern ~= nil then
            AOKassenbuch.anfordern()
        end
    end
    if nr == AOHofPC.START then
        if AOBericht ~= nil and AOBericht.anfordern ~= nil then
            AOBericht.anfordern()
        end
        if AOMaschinenMain ~= nil and AOMaschinenMain.anfordern ~= nil then
            AOMaschinenMain.anfordern("jahr")
        end
    end
    if nr == AOHofPC.START or nr == AOHofPC.ABGABEN then
        if AOAbgaben ~= nil and AOAbgaben.anfordern ~= nil then
            AOAbgaben.anfordern()
        end
    end
    if nr == AOHofPC.FUHRPARK then
        self:fpAnfordern()
    end
    if nr == AOHofPC.OVERVIEW then
        self:foAnfordern(true)
    end
end

function AOHofPC:fuelle()
    self:fuelleKopf()
    if self.seite == AOHofPC.START then
        self:fuelleStart()
    elseif self.seite == AOHofPC.KASSE then
        self:fuelleKasse()
    elseif self.seite == AOHofPC.FUHRPARK then
        self:fuelleFuhrpark()
    elseif self.seite == AOHofPC.ABGABEN then
        self:fuelleAbgaben()
    elseif self.seite == AOHofPC.OVERVIEW then
        self:fuelleOverview()
    end
end

function AOHofPC:update(dt)
    AOHofPC.superClass().update(self, dt)
    self.uhrTakt = self.uhrTakt + dt
    if self.uhrTakt >= 1000 then
        self.uhrTakt = 0
        self:fuelleKopf()
    end
    if self.seite == AOHofPC.OVERVIEW then
        self.foTakt = self.foTakt + dt
        if self.foTakt >= 10000 then
            self.foTakt = 0
            self:foAnfordern(false)
            self:fuelleOverview()
        end
    end
end

function AOHofPC.aktualisiereOffenes()
    if AOHofPC.offen ~= nil then
        AOHofPC.offen:fuelle()
    end
end

function AOHofPC.tageBisMonatswechsel()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil or type(env.daysPerPeriod) ~= "number" or type(env.currentDayInPeriod) ~= "number" then
        return nil
    end
    return math.max(0, env.daysPerPeriod - env.currentDayInPeriod)
end

function AOHofPC.wechselText(tage)
    if tage == nil then
        return "-"
    elseif tage == 0 then
        return AOHofPC.t("ao_pc_heuteNacht")
    elseif tage == 1 then
        return AOHofPC.t("ao_pc_morgenNacht")
    end
    return AOHofPC.vorlage("ao_pc_inTagen", tage)
end

function AOHofPC:fuelleKopf()
    local farmId = AOHofPC.eigeneFarm()
    local hof = ""
    if farmId ~= nil and g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if type(farm) == "table" and type(farm.name) == "string" then
            hof = farm.name
        end
    end
    AOHofPC.text(self.pcHof, hof)

    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then
        AOHofPC.text(self.pcUhr, "")
        return
    end
    local zeit = string.format("%02d:%02d", math.floor(env.currentHour or 0), math.floor(env.currentMinute or 0))
    AOHofPC.text(self.pcUhr, AOHofPC.vorlage("ao_pc_uhr",
        math.floor(env.currentDayInPeriod or 1), AOHofPC.monatName(env.currentPeriod or 1),
        math.floor(env.currentYear or 1), zeit))
end

local function monatsSummen(paket, jahr, monat)
    local ein, aus, inv = 0, 0, 0
    if paket == nil or AOKassenbuch == nil then
        return ein, aus, inv, false
    end
    local ids = AOKassenbuch.gruppenIds()
    local gefunden = false
    local werte = {}
    for _, m in ipairs(paket.monate or {}) do
        if m.jahr == jahr and (monat == nil or m.monat == monat) then
            gefunden = true
            for i = 1, #ids do
                werte[i] = (werte[i] or 0) + (m.werte[i] or 0)
            end
        end
    end
    for i, id in ipairs(ids) do
        local art = AOHofPC.gruppeArt(id)
        local betrag = werte[i] or 0
        if art == "ein" then
            ein = ein + betrag
        elseif art == "aus" then
            aus = aus + math.abs(betrag)
        elseif art == "inv" then
            inv = inv + math.abs(betrag)
        end
    end
    return ein, aus, inv, gefunden
end

function AOHofPC:fuelleStart()
    local F = AOHofPC.FARBE
    local kasse = AOKassenbuch ~= nil and AOKassenbuch.paket or nil
    local bericht = AOBericht ~= nil and AOBericht.paket or nil
    local maschinen = AOMaschinenMain ~= nil and AOMaschinenMain.paket or nil
    if maschinen ~= nil and maschinen.wahl ~= "jahr" then
        maschinen = nil
    end
    local abgaben = AOAbgaben ~= nil and AOAbgaben.paket or nil

    local geld, kredit = nil, nil
    local farmId = AOHofPC.eigeneFarm()
    if farmId ~= nil and g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if type(farm) == "table" then
            geld = tonumber(farm.money)
            kredit = tonumber(farm.loan)
        end
    end
    if geld == nil then
        geld = standWert(bericht, "geld")
    end
    if kredit == nil then
        kredit = standWert(bericht, "kredit")
    end

    AOHofPC.text(self.stLab1, AOHofPC.t("ao_pc_stKonto"), F.grau)
    AOHofPC.text(self.stWert1, AOHofPC.geld(geld), (geld or 0) >= 0 and F.weiss or F.neg)
    AOHofPC.text(self.stSub1, AOHofPC.vorlage("ao_pc_stKredit", AOHofPC.geld(kredit or 0)), F.grau)

    local vermoegen = standWert(bericht, "vermoegen")
    AOHofPC.text(self.stLab2, AOHofPC.t("ao_pc_stNetto"), F.grau)
    AOHofPC.text(self.stWert2, AOHofPC.geld(vermoegen), F.weiss)
    local sub = AOHofPC.t("ao_pc_stNettoSub")
    if bericht ~= nil and bericht.standVergleich and AOBericht.STAND ~= nil then
        local vor = nil
        for i, k in ipairs(AOBericht.STAND) do
            if k == "vermoegen" then
                vor = bericht.standVorjahr[i]
            end
        end
        if vor ~= nil and math.abs(vor) >= 1 and vermoegen ~= nil then
            sub = AOHofPC.vorlage("ao_pc_stVorjahr",
                string.format("%+d %%", math.floor((vermoegen - vor) / math.abs(vor) * 100 + 0.5)))
        end
    end
    AOHofPC.text(self.stSub2, sub, F.grau)

    local jahr, monat = 1, 1
    if kasse ~= nil then
        jahr, monat = kasse.jahr or 1, kasse.monat or 1
    end
    local einM, ausM = monatsSummen(kasse, jahr, monat)
    local einJ, ausJ, invJ = monatsSummen(kasse, jahr, nil)
    AOHofPC.text(self.stLab3, AOHofPC.t("ao_pc_stMonat"), F.grau)
    AOHofPC.text(self.stLab4, AOHofPC.t("ao_pc_stJahr"), F.grau)
    if kasse ~= nil then
        AOHofPC.text(self.stWert3, AOHofPC.geld(einM - ausM), einM - ausM >= 0 and F.gut or F.neg)
        AOHofPC.text(self.stSub3, AOHofPC.vorlage("ao_pc_stEinAus", AOHofPC.geld(einM), AOHofPC.geld(ausM)), F.grau)
        AOHofPC.text(self.stWert4, AOHofPC.geld(einJ - ausJ), einJ - ausJ >= 0 and F.gut or F.neg)
        AOHofPC.text(self.stSub4, AOHofPC.vorlage("ao_pc_stInvest", AOHofPC.geld(invJ)), F.grau)
    else
        AOHofPC.text(self.stWert3, "-", F.weiss)
        AOHofPC.text(self.stSub3, AOHofPC.t("ao_pc_laedt"), F.grau)
        AOHofPC.text(self.stWert4, "-", F.weiss)
        AOHofPC.text(self.stSub4, "", F.grau)
    end

    local posten = {
        { "ao_pc_stGeld", geld, F.ein },
        { "ao_pc_stFahrzeuge", standWert(bericht, "fahrzeuge"), F.inv },
        { "ao_pc_stGebaeude", standWert(bericht, "gebaeude"), F.inv },
        { "ao_pc_stLand", standWert(bericht, "land"), F.inv },
        { "ao_pc_stKreditPosten", kredit, F.kredit },
    }
    local groesster = 0
    for _, p in ipairs(posten) do
        groesster = math.max(groesster, math.abs(p[2] or 0))
    end
    for i, p in ipairs(posten) do
        AOHofPC.text(self["stVLab" .. i], AOHofPC.t(p[1]), F.weiss)
        AOHofPC.text(self["stVWert" .. i], AOHofPC.geld(p[2]), i == 5 and (p[2] or 0) > 0 and F.neg or F.weiss)
        AOHofPC.farbe(self["stVBalken" .. i], p[3])
        AOHofPC.breite(self["stVBalken" .. i], groesster > 0 and math.abs(p[2] or 0) / groesster or 0)
    end

    local blick = {}
    local feldHa, landHa = standWert(bericht, "feldHa"), standWert(bericht, "landHa")
    table.insert(blick, { "ao_pc_stFelder", feldHa ~= nil
        and AOHofPC.vorlage("ao_pc_stFelderWert", AOHofPC.zahl(feldHa, 1), AOHofPC.zahl(landHa or 0, 1)) or "-" })

    local anzahl, geleast, kosten, teuer = nil, 0, 0, nil
    if maschinen ~= nil then
        anzahl = #maschinen.eintraege
        for _, r in ipairs(maschinen.eintraege) do
            AOMaschinen.ableiten(r)
            kosten = kosten + r.summe
            if r.geleast then
                geleast = geleast + 1
            end
            if r.motor and r.stunden >= 1 and r.proStunde ~= nil
                    and (teuer == nil or r.proStunde > teuer.proStunde) then
                teuer = r
            end
        end
    end
    table.insert(blick, { "ao_pc_stMaschinen", anzahl ~= nil
        and AOHofPC.vorlage("ao_pc_stMaschinenWert", anzahl, geleast) or "-" })
    table.insert(blick, { "ao_pc_stMkJahr", maschinen ~= nil and AOHofPC.geld(kosten) or "-" })
    table.insert(blick, { "ao_pc_stTeuer", teuer ~= nil
        and AOHofPC.vorlage("ao_pc_stTeuerWert", teuer.name, AOHofPC.geld(teuer.proStunde)) or "-" })

    local faellig = nil
    if abgaben ~= nil then
        faellig = abgaben.gsNaechste
        if abgaben.fsMonateBis <= 1 then
            faellig = faellig + abgaben.fsNaechste
        end
    end
    table.insert(blick, { "ao_pc_stAbgaben", AOHofPC.geld(faellig) })
    local tage = AOHofPC.tageBisMonatswechsel()
    local wechsel = "-"
    if tage ~= nil then
        wechsel = AOHofPC.wechselText(tage)
    end
    table.insert(blick, { "ao_pc_stWechsel", wechsel })
    table.insert(blick, { "ao_pc_stHelfer", abgaben ~= nil and AOHofPC.zahl(abgaben.hlEinsatz) or "-" })
    table.insert(blick, { "ao_pc_stLohn", abgaben ~= nil and AOHofPC.geld(abgaben.hlJahr) or "-" })
    for i = 1, 8 do
        local b = blick[i]
        AOHofPC.text(self["stBLab" .. i], b ~= nil and AOHofPC.t(b[1]) or "", F.grau)
        AOHofPC.text(self["stBWert" .. i], b ~= nil and b[2] or "", F.weiss)
    end

    local monate = {}
    local j, m = jahr, monat
    for k = 6, 1, -1 do
        local ein, aus, _, da = monatsSummen(kasse, j, m)
        monate[k] = { jahr = j, monat = m, ein = ein, aus = aus, da = da }
        m = m - 1
        if m < 1 then
            j, m = j - 1, 12
        end
    end
    local hoch = 0
    for _, e in ipairs(monate) do
        hoch = math.max(hoch, e.ein, e.aus)
    end
    for k, e in ipairs(monate) do
        AOHofPC.hoehe(self["stEin" .. k], hoch > 0 and e.ein / hoch or 0)
        AOHofPC.hoehe(self["stAus" .. k], hoch > 0 and e.aus / hoch or 0)
        local text = AOHofPC.monatName(e.monat)
        local farbe = F.grau
        if e.da and (e.ein ~= 0 or e.aus ~= 0) then
            text = text .. "  " .. AOHofPC.geld(e.ein - e.aus)
            farbe = e.ein - e.aus >= 0 and F.gut or F.neg
        end
        AOHofPC.text(self["stMon" .. k], text, farbe)
    end
end

function AOHofPC.laden()
    if AOHofPC.geladen then
        return true
    end
    if g_gui == nil or g_gui.guis == nil then
        return false
    end
    if g_gui.guis[AOHofPC.NAME] ~= nil then
        AOHofPC.geladen = true
        return true
    end
    local pfad = (AOHofPC.modDir or "") .. AOHofPC.XML
    if fileExists ~= nil and not fileExists(pfad) then
        Logging.warning(AOHofPC.LOG .. "Hof-PC: XML fehlt (%s).", tostring(pfad))
        return false
    end
    if g_gui.loadGui == nil then
        return false
    end
    g_gui:loadGui(pfad, AOHofPC.NAME, AOHofPC.new(), false)
    AOHofPC.geladen = (g_gui.guis[AOHofPC.NAME] ~= nil)
    return AOHofPC.geladen
end

function AOHofPC.umschalten()
    if g_gui == nil or g_currentMission == nil then
        return
    end
    if g_gui.currentGuiName == AOHofPC.NAME then
        if g_gui.showGui ~= nil then
            g_gui:showGui("")
        end
        return
    end
    if g_gui.currentGui ~= nil then
        return
    end
    if not AOHofPC.laden() then
        return
    end
    if g_gui.showDialog ~= nil then
        g_gui:showDialog(AOHofPC.NAME)
    end
end

function AOHofPC.installiereTastenHook()
    if AOHofPC.tastenHook then
        return
    end
    if PlayerInputComponent == nil or PlayerInputComponent.registerGlobalPlayerActionEvents == nil then
        return
    end
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.overwrittenFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents,
        function(comp, superFunc, ...)
            local ret = superFunc(comp, ...)
            if g_client ~= nil and comp.player ~= nil and comp.player.isOwner then
                AOHofPC.registriereTaste()
            end
            return ret
        end)
    AOHofPC.tastenHook = true
end

function AOHofPC.registriereTaste()
    if g_dedicatedServerInfo ~= nil then
        return
    end
    if g_inputBinding == nil or InputAction == nil or InputAction.AO_BUCH == nil then
        return
    end
    if AOHofPC.tasteId ~= nil and g_inputBinding.removeActionEvent ~= nil then
        g_inputBinding:removeActionEvent(AOHofPC.tasteId)
        AOHofPC.tasteId = nil
    end
    if g_inputBinding.registerActionEvent == nil then
        return
    end
    local ok, id = g_inputBinding:registerActionEvent(InputAction.AO_BUCH, AOHofPC,
        AOHofPC.umschalten, false, true, false, true)
    if ok then
        AOHofPC.tasteId = id
    end
end
