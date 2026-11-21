-- AOHofPCFuhrpark.lua
-- Seite Fuhrpark im Hof-PC: alle Fahrzeuge und Geraete des Hofs mit Stunden,
-- Kosten als gestapeltem Balken, Euro je Stunde und Zustand. Ein Klick auf
-- eine Zeile zeigt rechts die Einzelheiten. Die Zahlen kommen aus
-- AOMaschinenMain.erstellePaket, im Mehrspieler per AOMaschinenEvent.
-- OGW

AOHofPC.FP_ZEILEN = 10
AOHofPC.FP_WAHL   = { "jahr", "vorjahr", "gesamt" }

local t = AOHofPC.t
local F = AOHofPC.FARBE

local WAHL_TEXT   = { "ao_mk_jahr", "ao_mk_vorjahr", "ao_mk_gesamt" }
local SORT_TEXT   = { "ao_mk_sortEh", "ao_mk_sortSumme", "ao_mk_sortStd", "ao_mk_sortAusl", "ao_mk_sortName" }
local ZEIGEN_TEXT = { "ao_mk_zeigAlle", "ao_mk_zeigMotor", "ao_mk_zeigGeraete", "ao_mk_zeigLeasing", "ao_mk_zeigKaum" }

local SEGMENTE = {
    { text = "ao_mk_lWert",      farbe = { 0.545, 0.361, 0.839, 1 }, wert = function(r) return r.wertverlust end },
    { text = "ao_mk_lRep",       farbe = { 0.922, 0.533, 0.204, 1 }, wert = function(r) return r.reparatur end },
    { text = "ao_mk_lSprit",     farbe = { 0.165, 0.471, 0.839, 1 }, wert = function(r) return r.sprit end },
    { text = "ao_mk_lUnterhalt", farbe = { 0.141, 0.651, 0.620, 1 }, wert = function(r) return r.unterhalt + r.leasing end },
    { text = "ao_mk_lFuhrpark",  farbe = { 0.851, 0.678, 0.161, 1 }, wert = function(r) return r.fuhrpark end },
}

local function texte(schluessel)
    local liste = {}
    for i, k in ipairs(schluessel) do
        liste[i] = t(k)
    end
    return liste
end

local function tageJeMonat()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and type(env.daysPerPeriod) == "number" and env.daysPerPeriod > 0 then
        return env.daysPerPeriod
    end
    return 1
end

local FILTER = {
    function() return true end,
    function(r) return r.motor end,
    function(r) return not r.motor end,
    function(r) return r.geleast end,
    function(r)
        if r.auslastung ~= nil then
            return r.auslastung < 2
        end
        return r.tage >= tageJeMonat() and r.stunden < 0.5
    end,
}

local function absteigend(a, b, feld)
    local x, y = a[feld], b[feld]
    if x == nil and y == nil then
        return a.summe > b.summe
    end
    if x == nil then
        return false
    end
    if y == nil then
        return true
    end
    if x == y then
        return a.summe > b.summe
    end
    return x > y
end

local SORTIERUNG = {
    function(a, b) return absteigend(a, b, "proStunde") end,
    function(a, b) return a.summe > b.summe end,
    function(a, b) return absteigend(a, b, "stunden") end,
    function(a, b)
        if a.auslastung == nil or b.auslastung == nil then
            return a.auslastung ~= nil
        end
        return a.auslastung < b.auslastung
    end,
    function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end,
}

local function kraftstoffText(r)
    local teile = {}
    for _, k in ipairs(r.kraftstoff or {}) do
        local name = k.typ
        if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeByName ~= nil then
            local ft = g_fillTypeManager:getFillTypeByName(k.typ)
            if ft ~= nil and type(ft.title) == "string" then
                name = ft.title
            end
        end
        table.insert(teile, AOHofPC.zahl(k.liter) .. " l " .. name)
    end
    if #teile == 0 then
        return "-"
    end
    return table.concat(teile, ", ")
end

local function bildSetzen(element, r)
    if element == nil then
        return
    end
    local datei = nil
    if r ~= nil and r.vehicle ~= nil and r.vehicle.getImageFilename ~= nil then
        datei = r.vehicle:getImageFilename()
    end
    if type(datei) ~= "string" or datei == "" then
        AOHofPC.zeigen(element, false)
        return
    end
    if element.aoDatei ~= datei and element.setImageFilename ~= nil then
        element:setImageFilename(datei)
        element.aoDatei = datei
    end
    AOHofPC.zeigen(element, true)
end

local function zustandFarbe(zustand)
    if zustand >= 0.7 then
        return F.gut
    elseif zustand >= 0.4 then
        return F.mittel
    end
    return F.neg
end

function AOHofPC:fpVorbereiten()
    AOHofPC.optionen(self.fpOptZeitraum, texte(WAHL_TEXT), self.fp.wahl)
    AOHofPC.optionen(self.fpOptSort, texte(SORT_TEXT), self.fp.sort)
    AOHofPC.optionen(self.fpOptZeigen, texte(ZEIGEN_TEXT), self.fp.zeigen)
    for k, s in ipairs(SEGMENTE) do
        AOHofPC.farbe(self["fpLegF" .. k], s.farbe)
        AOHofPC.text(self["fpLegT" .. k], t(s.text), F.grau)
    end
end

function AOHofPC:fpAnfordern()
    if AOMaschinenMain ~= nil and AOMaschinenMain.anfordern ~= nil then
        AOMaschinenMain.anfordern(AOHofPC.FP_WAHL[self.fp.wahl])
    end
end

function AOHofPC:onClickFpZeitraum(state)
    self.fp.wahl = state
    self.fp.start = 0
    self:fpAnfordern()
    self:fuelleFuhrpark()
end

function AOHofPC:onClickFpSort(state)
    self.fp.sort = state
    self.fp.start = 0
    self:fuelleFuhrpark()
end

function AOHofPC:onClickFpZeigen(state)
    self.fp.zeigen = state
    self.fp.start = 0
    self:fuelleFuhrpark()
end

function AOHofPC:onClickFpSeite(state)
    self.fp.start = (state - 1) * AOHofPC.FP_ZEILEN
    self:fuelleFuhrpark()
end

function AOHofPC:onClickFpZeile(element)
    for i = 1, AOHofPC.FP_ZEILEN do
        if self["fpZeile" .. i] == element then
            local r = self.fp.sichtbar ~= nil and self.fp.sichtbar[i] or nil
            if r ~= nil then
                self.fp.auswahl = r.vehicle or r.name
                self:fuelleFuhrpark()
            end
            return
        end
    end
end

function AOHofPC:fpZeileLeeren(i)
    AOHofPC.zeigen(self["fpMarke" .. i], false)
    AOHofPC.zeigen(self["fpBild" .. i], false)
    AOHofPC.text(self["fpName" .. i], "")
    AOHofPC.text(self["fpStd" .. i], "")
    AOHofPC.text(self["fpSumme" .. i], "")
    AOHofPC.text(self["fpEh" .. i], "")
    for s = 1, #SEGMENTE do
        AOHofPC.zeigen(self["fpSeg" .. i .. "_" .. s], false)
    end
    AOHofPC.zeigen(self["fpZustGrund" .. i], false)
    AOHofPC.zeigen(self["fpZust" .. i], false)
    AOHofPC.zeigen(self["fpZeile" .. i], false)
end

function AOHofPC:fpKacheln(liste)
    local summe, stunden, kostenMotor, liter, sprit, flaeche = 0, 0, 0, 0, 0, 0
    for _, r in ipairs(liste) do
        summe = summe + r.summe
        liter = liter + r.liter
        sprit = sprit + r.sprit
        flaeche = flaeche + r.ha
        if r.motor then
            stunden = stunden + r.stunden
            kostenMotor = kostenMotor + r.summe
        end
    end
    local kacheln = {
        { "ao_mk_kKosten", AOHofPC.geld(summe), AOHofPC.vorlage("ao_mk_kKostenSub", #liste) },
        { "ao_mk_kStunden", AOHofPC.zahl(stunden, 1) .. " h", t("ao_mk_kStundenSub") },
        { "ao_mk_kEh", stunden > 0.05 and AOHofPC.geld(kostenMotor / stunden) or "-", t("ao_mk_kEhSub") },
        { "ao_mk_kSprit", AOHofPC.zahl(liter) .. " l", AOHofPC.vorlage("ao_mk_kSpritSub", AOHofPC.geld(sprit)) },
        { "ao_mk_kFlaeche", AOHofPC.zahl(flaeche, 1) .. " ha",
          flaeche > 0.01 and AOHofPC.vorlage("ao_mk_kFlaecheSub", AOHofPC.geld(summe / flaeche)) or "" },
    }
    for i, k in ipairs(kacheln) do
        AOHofPC.text(self["fpKLab" .. i], t(k[1]), F.grau)
        AOHofPC.text(self["fpKWert" .. i], k[2], F.weiss)
        AOHofPC.text(self["fpKSub" .. i], k[3], F.grau)
    end
end

function AOHofPC:fpDetail(r)
    local zeilen = {}
    if r ~= nil then
        bildSetzen(self.fpDBild, r)
        AOHofPC.text(self.fpDName, r.name, F.weiss)
        AOHofPC.text(self.fpDStatus, AOHofPC.vorlage("ao_mk_dStatus",
            t(r.geleast and "ao_mk_geleast" or "ao_mk_eigentum"), AOHofPC.geld(r.zeitwert)), F.grau)

        local sub = ""
        if r.leasingBesser and r.leasingGleich ~= nil then
            sub = AOHofPC.vorlage("ao_mk_dLeasingBesser", AOHofPC.geld(r.leasingGleich), AOHofPC.geld(r.besitz))
        elseif r.leasingGleich ~= nil and r.stunden >= 1 then
            sub = AOHofPC.vorlage("ao_mk_dLeasingVgl", AOHofPC.geld(r.leasingGleich), AOHofPC.geld(r.besitz))
        elseif r.altbestand and AOHofPC.FP_WAHL[self.fp.wahl] == "gesamt" then
            sub = t("ao_mk_dAltbestand")
        end
        AOHofPC.text(self.fpDSub, sub, r.leasingBesser and F.mittel or F.grau)

        local literTeil = kraftstoffText(r)
        if r.literProStunde ~= nil then
            literTeil = literTeil .. ", " .. AOHofPC.zahl(r.literProStunde, 1) .. " l/h"
        end
        local flaecheTeil = AOHofPC.zahl(r.flaeche, 2) .. " ha"
        if r.literProHa ~= nil then
            flaecheTeil = flaecheTeil .. ", " .. AOHofPC.zahl(r.literProHa, 1) .. " l/ha"
        end
        zeilen = {
            { "ao_mk_dStunden", AOHofPC.vorlage("ao_mk_dStundenWert", AOHofPC.zahl(r.stunden, 1), AOHofPC.zahl(r.tage)) },
            { "ao_mk_dAuslastung", r.auslastung ~= nil
                and AOHofPC.vorlage("ao_mk_dAuslastungWert", AOHofPC.zahl(r.auslastung, 1)) or "-" },
            { "ao_mk_dZustand", AOHofPC.zahl(r.zustand * 100) .. " %", zustandFarbe(r.zustand) },
            { "ao_mk_dKraftstoff", literTeil },
            { "ao_mk_dFlaeche", flaecheTeil },
            { "ao_mk_lWert", AOHofPC.geld(r.wertverlust) },
            { "ao_mk_lRep", AOHofPC.geld(r.reparatur) },
            { "ao_mk_lSprit", AOHofPC.geld(r.sprit) },
            { "ao_mk_dUnterhalt", AOHofPC.geld(r.unterhalt) },
            { "ao_mk_dLeasing", AOHofPC.geld(r.leasing) },
            { "ao_mk_lFuhrpark", AOHofPC.geld(r.fuhrpark) },
            { "ao_mk_dSumme", AOHofPC.geld(r.summe), F.weiss },
            { "ao_mk_dJe", (r.proStunde ~= nil or r.proHa ~= nil) and AOHofPC.vorlage("ao_mk_dJeWert",
                r.proStunde ~= nil and AOHofPC.geld(r.proStunde) or "-",
                r.proHa ~= nil and AOHofPC.geld(r.proHa) or "-") or "-" },
        }
    else
        AOHofPC.zeigen(self.fpDBild, false)
        AOHofPC.text(self.fpDName, "")
        AOHofPC.text(self.fpDStatus, "")
        AOHofPC.text(self.fpDSub, "")
    end
    for k = 1, 13 do
        local z = zeilen[k]
        AOHofPC.text(self["fpDLab" .. k], z ~= nil and t(z[1]) or "", F.grau)
        AOHofPC.text(self["fpDWert" .. k], z ~= nil and z[2] or "", z ~= nil and z[3] or F.weiss)
    end
end

function AOHofPC:fuelleFuhrpark()
    local paket = AOMaschinenMain ~= nil and AOMaschinenMain.paket or nil
    local wahl = AOHofPC.FP_WAHL[self.fp.wahl]
    if paket ~= nil and paket.wahl ~= wahl then
        paket = nil
    end

    local liste = {}
    if paket ~= nil and paket.aktiv then
        local filter = FILTER[self.fp.zeigen] or FILTER[1]
        for _, r in ipairs(paket.eintraege) do
            AOMaschinen.ableiten(r)
            if filter(r) then
                table.insert(liste, r)
            end
        end
        table.sort(liste, SORTIERUNG[self.fp.sort] or SORTIERUNG[1])
    end
    self:fpKacheln(liste)

    local erstes, seite, seiten = AOHofPC.fenster(self.fp, #liste, AOHofPC.FP_ZEILEN)
    local seitenTexte = {}
    for s = 1, seiten do
        seitenTexte[s] = AOHofPC.vorlage("ao_mk_seiteVon", s, seiten)
    end
    AOHofPC.optionen(self.fpOptSeite, seitenTexte, seite)
    self:rollleiste("fpRoll", erstes, #liste, AOHofPC.FP_ZEILEN)

    local gewaehlt = nil
    for _, r in ipairs(liste) do
        if self.fp.auswahl ~= nil and (r.vehicle == self.fp.auswahl or r.name == self.fp.auswahl) then
            gewaehlt = r
        end
    end
    if gewaehlt == nil then
        gewaehlt = liste[erstes + 1]
        self.fp.auswahl = gewaehlt ~= nil and (gewaehlt.vehicle or gewaehlt.name) or nil
    end

    local hoechste = 0
    for _, r in ipairs(liste) do
        hoechste = math.max(hoechste, r.summe)
    end

    self.fp.sichtbar = {}
    for i = 1, AOHofPC.FP_ZEILEN do
        local r = liste[erstes + i]
        self.fp.sichtbar[i] = r
        if r == nil then
            self:fpZeileLeeren(i)
        else
            AOHofPC.zeigen(self["fpZeile" .. i], true)
            AOHofPC.zeigen(self["fpMarke" .. i], r == gewaehlt)
            bildSetzen(self["fpBild" .. i], r)
            local name = r.name or "?"
            if r.geleast then
                name = AOHofPC.vorlage("ao_mk_nameGeleast", name)
            end
            AOHofPC.text(self["fpName" .. i], name, r == gewaehlt and F.akzent or F.weiss)
            AOHofPC.text(self["fpStd" .. i], AOHofPC.zahl(r.stunden, 1), F.weiss)
            AOHofPC.text(self["fpSumme" .. i], AOHofPC.geld(r.summe), F.weiss)
            AOHofPC.text(self["fpEh" .. i], r.proStunde ~= nil and AOHofPC.geld(r.proStunde) or "-", F.weiss)

            local versatz = 0
            for s, seg in ipairs(SEGMENTE) do
                local element = self["fpSeg" .. i .. "_" .. s]
                local wert = math.max(0, seg.wert(r) or 0)
                AOHofPC.farbe(element, seg.farbe)
                AOHofPC.verschiebe(element, versatz)
                versatz = versatz + AOHofPC.breite(element, hoechste > 0 and wert / hoechste or 0)
            end

            AOHofPC.zeigen(self["fpZustGrund" .. i], true)
            AOHofPC.farbe(self["fpZust" .. i], zustandFarbe(r.zustand))
            AOHofPC.breite(self["fpZust" .. i], math.max(0.02, r.zustand))
        end
    end
    self:fpDetail(gewaehlt)

    local fuss = t("ao_mk_hinweis")
    if paket == nil then
        fuss = t("ao_pc_laedt")
    elseif not paket.aktiv then
        fuss = t("ao_mk_aus")
    elseif #liste == 0 then
        fuss = t("ao_mk_keineDaten")
    end
    AOHofPC.text(self.fpFuss, fuss, F.grau)
end
