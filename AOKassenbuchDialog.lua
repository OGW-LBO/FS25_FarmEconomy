-- AOKassenbuchDialog.lua
-- Fenster, das zeigt wofuer das Geld geflossen ist: Rangliste der Gruppen mit
-- Balken und die letzten Buchungen, je Monat oder Jahr zum Durchblaettern.
-- Die Zahlen kommen aus AOKassenbuch, im Mehrspieler per AOKassenbuchEvent.
-- OGW

AOKassenbuchDialog = {}
local AOKassenbuchDialog_mt = Class(AOKassenbuchDialog, MessageDialog)

AOKassenbuchDialog.LOG         = "[AgrarOekonomie] "
AOKassenbuchDialog.NAME        = "AOKassenbuchDialogUI"
AOKassenbuchDialog.XML         = "gui/AOKassenbuchDialog.xml"
AOKassenbuchDialog.RANG_ZEILEN = 8
AOKassenbuchDialog.BUCH_ZEILEN = 12

-- beim Laden der Datei gueltig, spaeter nicht mehr
AOKassenbuchDialog.modDir   = g_currentModDirectory

AOKassenbuchDialog.geladen    = false
AOKassenbuchDialog.tastenHook = false
AOKassenbuchDialog.tasteId  = nil
AOKassenbuchDialog.offen    = nil

AOKassenbuchDialog.FARBE = {
    ein    = { 0.165, 0.471, 0.839, 1 },
    aus    = { 0.922, 0.408, 0.204, 1 },
    inv    = { 0.106, 0.686, 0.478, 1 },
    kredit = { 0.384, 0.314, 0.839, 1 },
    neg    = { 0.890, 0.286, 0.282, 1 },
    grau   = { 0.62, 0.62, 0.62, 1 },
    weiss  = { 1, 1, 1, 1 },
}

local function t(schluessel)
    if AOSettingsPage ~= nil and AOSettingsPage.getText ~= nil then
        return AOSettingsPage.getText(schluessel)
    end
    return schluessel
end

local function gruppeArt(id)
    if id == "kredit" then
        return "kredit"
    end
    if AOBericht ~= nil and AOBericht.GRUPPEN ~= nil then
        for _, g in ipairs(AOBericht.GRUPPEN) do
            if g.id == id then
                return g.art
            end
        end
    end
    return "aus"
end

local function gruppeLabel(id)
    if id == "kredit" then
        return t("ao_buch_kredit")
    end
    if AOBericht ~= nil and AOBericht.GRUPPEN ~= nil then
        for _, g in ipairs(AOBericht.GRUPPEN) do
            if g.id == id then
                return t(g.label)
            end
        end
    end
    return id
end

function AOKassenbuchDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or AOKassenbuchDialog_mt)
    self.ansicht   = 1      -- 1 Monat, 2 Jahr
    self.gewaehlt  = nil    -- Schluessel des Zeitraums, nil = der neueste
    self.zeitraeume = {}
    self.balkenMax = {}
    return self
end

function AOKassenbuchDialog:onOpen()
    AOKassenbuchDialog.superClass().onOpen(self)
    AOKassenbuchDialog.offen = self

    if self.optAnsicht ~= nil and self.optAnsicht.setTexts ~= nil then
        self.optAnsicht:setTexts({ t("ao_buch_ansMonat"), t("ao_buch_ansJahr") })
        if self.optAnsicht.setState ~= nil then
            self.optAnsicht:setState(self.ansicht, false)
        end
    end
    -- beim Oeffnen immer beim aktuellen Zeitraum anfangen
    self.gewaehlt = nil

    -- Volle Balkenbreite einmal merken, danach wird nur noch gekuerzt. Dazu
    -- die eigene weisse Textur setzen; ohne sie zeigt das Element ein Stueck
    -- der UI-Textur statt einer Flaeche.
    local textur = nil
    if Utils ~= nil and Utils.getFilename ~= nil then
        textur = Utils.getFilename("images/white.dds", AOKassenbuchDialog.modDir or "")
    end
    for i = 1, AOKassenbuchDialog.RANG_ZEILEN do
        local balken = self["rangBalken" .. i]
        if balken ~= nil then
            if self.balkenMax[i] == nil and balken.size ~= nil then
                self.balkenMax[i] = balken.size[1]
            end
            if textur ~= nil and balken.setImageFilename ~= nil and not self.texturGesetzt then
                balken:setImageFilename(textur)
            end
        end
    end
    self.texturGesetzt = true

    if AOKassenbuch ~= nil and AOKassenbuch.anfordern ~= nil then
        AOKassenbuch.anfordern()
    end
    self:fuelle()
end

function AOKassenbuchDialog:onClose()
    AOKassenbuchDialog.offen = nil
    AOKassenbuchDialog.superClass().onClose(self)
end

function AOKassenbuchDialog:onClickBack()
    self:close()
    return true
end

function AOKassenbuchDialog:onClickAnsicht(state)
    self.ansicht  = state
    self.gewaehlt = nil
    self:fuelle()
end

function AOKassenbuchDialog:onClickZeitraum(state)
    local z = self.zeitraeume[state]
    if z ~= nil then
        self.gewaehlt = z.schluessel
    end
    self:fuelle()
end

local function setzeText(element, text, farbe)
    if element == nil then
        return
    end
    if element.setText ~= nil then
        element:setText(text or "")
    end
    if farbe ~= nil and element.setTextColor ~= nil then
        element:setTextColor(farbe[1], farbe[2], farbe[3], farbe[4])
    end
end

-- Vorlage mit genau so vielen %s wie Werten, sonst die Vorlage selbst.
local function vorlage(schluessel, ...)
    local text   = t(schluessel)
    local werte  = { ... }
    local anzahl = select(2, string.gsub(text, "%%s", ""))
    if anzahl ~= #werte then
        return text
    end
    return string.format(text, unpack(werte))
end

local function monatText(monat)
    if AOBericht ~= nil and AOBericht.monatsName ~= nil then
        return AOBericht.monatsName(monat)
    end
    return tostring(monat)
end

local function jahrText(jahr)
    return vorlage("ao_buch_jahr", tostring(jahr))
end

-- Was sich mit den Pfeilen auswaehlen laesst: in der Monatsansicht jeder
-- Monat, der im Paket steht, in der Jahresansicht jedes Jahr. Neuestes zuerst.
function AOKassenbuchDialog:zeitraeumeBauen(paket)
    local liste, gesehen = {}, {}
    for _, m in ipairs(paket.monate or {}) do
        if self.ansicht == 2 then
            if not gesehen[m.jahr] then
                gesehen[m.jahr] = true
                table.insert(liste, { schluessel = m.jahr, jahr = m.jahr, text = jahrText(m.jahr) })
            end
        else
            table.insert(liste, {
                schluessel = m.jahr * 100 + m.monat, jahr = m.jahr, monat = m.monat,
                text = monatText(m.monat) .. ", " .. jahrText(m.jahr),
            })
        end
    end
    return liste
end

-- Summen je Gruppe ueber alle Monate, fuer die passt(m) wahr ist.
local function summieren(paket, anzahl, passt)
    local werte = {}
    for i = 1, anzahl do
        werte[i] = 0
    end
    local gefunden = false
    for _, m in ipairs(paket.monate or {}) do
        if passt(m) then
            gefunden = true
            for i = 1, anzahl do
                werte[i] = werte[i] + (m.werte[i] or 0)
            end
        end
    end
    return werte, gefunden
end

local function einAus(ids, werte)
    local ein, aus = 0, 0
    for i, id in ipairs(ids) do
        local art = gruppeArt(id)
        if art == "ein" then
            ein = ein + (werte[i] or 0)
        elseif art == "aus" then
            aus = aus + math.abs(werte[i] or 0)
        end
    end
    return ein, aus
end

local function prozent(neu, alt)
    if alt < 1 then
        return nil
    end
    return string.format("%+d %%", math.floor((neu - alt) / alt * 100 + 0.5))
end

-- Fusszeile: Vergleich mit dem Monat davor bzw. denselben Monaten des
-- Vorjahres. Gibt es nichts zum Vergleichen, der Hinweis auf die Datei.
function AOKassenbuchDialog:vergleich(paket, ids, z, werte)
    local alt, gefunden, schluessel, bezug = nil, false, nil, ""
    if z.monat ~= nil then
        local vj, vm = z.jahr, z.monat - 1
        if vm < 1 then
            vj, vm = vj - 1, 12
        end
        alt, gefunden = summieren(paket, #ids, function(m)
            return m.jahr == vj and m.monat == vm
        end)
        schluessel = "ao_buch_vglMonat"
        bezug = monatText(vm)
    elseif z.jahr == paket.jahr then
        -- das laufende Jahr ist noch nicht um, also nur bis zum selben Monat
        local bis = paket.monat or 12
        werte = summieren(paket, #ids, function(m)
            return m.jahr == z.jahr and m.monat <= bis
        end)
        alt, gefunden = summieren(paket, #ids, function(m)
            return m.jahr == z.jahr - 1 and m.monat <= bis
        end)
        schluessel = "ao_buch_vglJahr"
        bezug = jahrText(z.jahr - 1)
    end
    if not gefunden then
        return t("ao_buch_fussDatei")
    end

    local einNeu, ausNeu = einAus(ids, werte)
    local einAlt, ausAlt = einAus(ids, alt)
    local teile = {}
    local p = prozent(einNeu, einAlt)
    if p ~= nil then
        table.insert(teile, vorlage("ao_buch_vglEin", p))
    end
    p = prozent(ausNeu, ausAlt)
    if p ~= nil then
        table.insert(teile, vorlage("ao_buch_vglAus", p))
    end
    if #teile == 0 then
        return t("ao_buch_fussDatei")
    end
    return vorlage(schluessel, bezug, table.concat(teile, ", "))
end

-- Alles im Fenster neu beschriften. Ohne Paket bleibt es leer, aber heil.
function AOKassenbuchDialog:fuelle()
    local paket = nil
    if AOKassenbuch ~= nil then
        paket = AOKassenbuch.paket
    end
    if paket == nil then
        paket = { monate = {} }
    end

    local ids = AOKassenbuch.gruppenIds()

    -- Zeitraum: der gemerkte, sonst der neueste
    self.zeitraeume = self:zeitraeumeBauen(paket)
    local index = 1
    for i, z in ipairs(self.zeitraeume) do
        if z.schluessel == self.gewaehlt then
            index = i
        end
    end
    local gewaehlt = self.zeitraeume[index]
    if self.optZeitraum ~= nil and self.optZeitraum.setTexts ~= nil then
        local texte = {}
        for i, z in ipairs(self.zeitraeume) do
            texte[i] = z.text
        end
        if #texte == 0 then
            texte[1] = "-"
        end
        self.optZeitraum:setTexts(texte)
        if self.optZeitraum.setState ~= nil then
            self.optZeitraum:setState(index, false)
        end
    end

    local werte, letzte = {}, {}
    if gewaehlt ~= nil then
        werte = summieren(paket, #ids, function(m)
            if gewaehlt.monat ~= nil then
                return m.jahr == gewaehlt.jahr and m.monat == gewaehlt.monat
            end
            return m.jahr == gewaehlt.jahr
        end)
        -- Monate kommen neuester zuerst, ihre Buchungen ebenso
        for _, m in ipairs(paket.monate) do
            if m.jahr == gewaehlt.jahr and (gewaehlt.monat == nil or m.monat == gewaehlt.monat) then
                for _, e in ipairs(m.letzte or {}) do
                    if #letzte < AOKassenbuchDialog.BUCH_ZEILEN then
                        e.monat = m.monat
                        table.insert(letzte, e)
                    end
                end
            end
        end
    end

    -- Kopfzahlen
    local summen = { ein = 0, aus = 0, inv = 0, kredit = 0 }
    for i, id in ipairs(ids) do
        local betrag = werte[i] or 0
        local art    = gruppeArt(id)
        if art == "ein" or art == "kredit" then
            summen[art] = summen[art] + betrag
        else
            summen[art] = summen[art] + math.abs(betrag)
        end
    end
    local saldo = summen.ein - summen.aus - summen.inv + summen.kredit

    setzeText(self.labEin, t("ao_buch_ein"), AOKassenbuchDialog.FARBE.grau)
    setzeText(self.labAus, t("ao_buch_aus"), AOKassenbuchDialog.FARBE.grau)
    setzeText(self.labInv, t("ao_buch_inv"), AOKassenbuchDialog.FARBE.grau)
    setzeText(self.labSaldo, t("ao_buch_saldo"), AOKassenbuchDialog.FARBE.grau)
    setzeText(self.wertEin, AgrarOekonomie.formatGeld(summen.ein), AOKassenbuchDialog.FARBE.ein)
    setzeText(self.wertAus, AgrarOekonomie.formatGeld(summen.aus), AOKassenbuchDialog.FARBE.aus)
    setzeText(self.wertInv, AgrarOekonomie.formatGeld(summen.inv), AOKassenbuchDialog.FARBE.inv)
    setzeText(self.wertSaldo, AgrarOekonomie.formatGeld(saldo),
        saldo >= 0 and AOKassenbuchDialog.FARBE.ein or AOKassenbuchDialog.FARBE.neg)

    -- Rangliste: alles was Geld kostet, groesstes zuerst
    local posten = {}
    for i, id in ipairs(ids) do
        local betrag = werte[i] or 0
        local art    = gruppeArt(id)
        if (art == "aus" or art == "inv") and math.abs(betrag) >= 0.5 then
            table.insert(posten, { name = gruppeLabel(id), betrag = math.abs(betrag), art = art })
        end
    end
    table.sort(posten, function(a, b) return a.betrag > b.betrag end)

    local groesster = 0
    if posten[1] ~= nil then
        groesster = posten[1].betrag
    end

    for i = 1, AOKassenbuchDialog.RANG_ZEILEN do
        local p      = posten[i]
        local label  = self["rangLabel" .. i]
        local balken = self["rangBalken" .. i]
        local wert   = self["rangWert" .. i]
        if p == nil then
            setzeText(label, "")
            setzeText(wert, "")
            if balken ~= nil and balken.setVisible ~= nil then
                balken:setVisible(false)
            end
        else
            setzeText(label, p.name, AOKassenbuchDialog.FARBE.weiss)
            setzeText(wert, AgrarOekonomie.formatGeld(p.betrag), AOKassenbuchDialog.FARBE.weiss)
            if balken ~= nil then
                if balken.setVisible ~= nil then
                    balken:setVisible(true)
                end
                local anteil = 0
                if groesster > 0 then
                    anteil = p.betrag / groesster
                end
                local voll = self.balkenMax[i]
                if voll ~= nil and balken.setSize ~= nil and balken.size ~= nil then
                    balken:setSize(math.max(voll * 0.01, voll * anteil), balken.size[2])
                end
                local farbe = AOKassenbuchDialog.FARBE[p.art] or AOKassenbuchDialog.FARBE.aus
                if balken.setImageColor ~= nil then
                    balken:setImageColor(nil, farbe[1], farbe[2], farbe[3], farbe[4])
                end
            end
        end
    end

    -- Letzte Buchungen
    for i = 1, AOKassenbuchDialog.BUCH_ZEILEN do
        local e    = letzte[i]
        local zeit = self["buchZeit" .. i]
        local text = self["buchText" .. i]
        local wert = self["buchWert" .. i]
        if e == nil then
            setzeText(zeit, "")
            setzeText(text, "")
            setzeText(wert, "")
        else
            local name = t("ao_buch_unbekannt")
            if AOKassenbuch.KATEGORIE_TEXT[e.kategorie or ""] ~= nil then
                name = t(AOKassenbuch.KATEGORIE_TEXT[e.kategorie])
            elseif e.gruppe >= 1 and ids[e.gruppe] ~= nil then
                name = gruppeLabel(ids[e.gruppe])
            end
            -- Bei einer Tagessumme sagt die Uhrzeit nichts, dort steht das Wort
            local wann = e.zeit or ""
            if e.summe then
                wann = t("ao_buch_tagessumme")
            end
            wann = monatText(e.monat) .. " " .. wann
            setzeText(zeit, wann, AOKassenbuchDialog.FARBE.grau)
            setzeText(text, name, AOKassenbuchDialog.FARBE.weiss)
            setzeText(wert, AgrarOekonomie.formatGeld(e.betrag),
                e.betrag >= 0 and AOKassenbuchDialog.FARBE.ein or AOKassenbuchDialog.FARBE.neg)
        end
    end

    local fuss = t("ao_buch_leer")
    if gewaehlt ~= nil and (#posten > 0 or #letzte > 0 or summen.ein ~= 0) then
        fuss = self:vergleich(paket, ids, gewaehlt, werte)
    end
    setzeText(self.fussZeile, fuss, AOKassenbuchDialog.FARBE.grau)
end

-- Vom Event gerufen, wenn das Paket des Servers eintrifft.
function AOKassenbuchDialog.aktualisiereOffenes()
    if AOKassenbuchDialog.offen ~= nil then
        AOKassenbuchDialog.offen:fuelle()
    end
end

-- Fenster oeffnen -------------------------------------------------------------

function AOKassenbuchDialog.laden()
    if AOKassenbuchDialog.geladen then
        return true
    end
    if g_gui == nil or g_gui.guis == nil then
        return false
    end
    if g_gui.guis[AOKassenbuchDialog.NAME] ~= nil then
        AOKassenbuchDialog.geladen = true
        return true
    end

    local pfad = (AOKassenbuchDialog.modDir or "") .. AOKassenbuchDialog.XML
    if fileExists ~= nil and not fileExists(pfad) then
        Logging.warning(AOKassenbuchDialog.LOG .. "Kassenbuch-Fenster: XML fehlt (%s).", tostring(pfad))
        return false
    end
    if g_gui.loadGui == nil then
        return false
    end

    g_gui:loadGui(pfad, AOKassenbuchDialog.NAME, AOKassenbuchDialog.new(), false)
    AOKassenbuchDialog.geladen = (g_gui.guis[AOKassenbuchDialog.NAME] ~= nil)
    return AOKassenbuchDialog.geladen
end

function AOKassenbuchDialog.umschalten()
    if g_gui == nil or g_currentMission == nil then
        return
    end
    if g_gui.currentGuiName == AOKassenbuchDialog.NAME then
        if g_gui.showGui ~= nil then
            g_gui:showGui("")
        end
        return
    end
    if g_gui.currentGui ~= nil then
        return
    end
    if not AOKassenbuchDialog.laden() then
        return
    end
    if g_gui.showDialog ~= nil then
        g_gui:showDialog(AOKassenbuchDialog.NAME)
    end
end

-- Im Spieler-Kontext anmelden, sonst ist die Taste im MP irgendwann weg
-- (dasselbe Muster wie beim Helferfenster).
function AOKassenbuchDialog.installiereTastenHook()
    if AOKassenbuchDialog.tastenHook then
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
                AOKassenbuchDialog.registriereTaste()
            end
            return ret
        end)
    AOKassenbuchDialog.tastenHook = true
end

-- Im Mehrspieler wird der Eingabe-Kontext neu aufgebaut, daher erst abmelden.
function AOKassenbuchDialog.registriereTaste()
    if g_dedicatedServerInfo ~= nil then
        return
    end
    if g_inputBinding == nil or InputAction == nil or InputAction.AO_BUCH == nil then
        return
    end

    if AOKassenbuchDialog.tasteId ~= nil and g_inputBinding.removeActionEvent ~= nil then
        g_inputBinding:removeActionEvent(AOKassenbuchDialog.tasteId)
        AOKassenbuchDialog.tasteId = nil
    end

    if g_inputBinding.registerActionEvent == nil then
        return
    end
    local ok, id = g_inputBinding:registerActionEvent(InputAction.AO_BUCH, AOKassenbuchDialog,
        AOKassenbuchDialog.umschalten, false, true, false, true)
    if ok then
        AOKassenbuchDialog.tasteId = id
    end
end
