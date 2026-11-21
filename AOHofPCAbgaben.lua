-- AOHofPCAbgaben.lua
-- Zwei Seiten des Hof-PCs: "Abgaben und Helfer" mit Steuern, Zinsen, Loehnen
-- und dem Stand der Bremse, dazu Farm Overview, das die Tabellen jener Mod
-- (Felder, Aufgaben, Lager, Tiere, Produktion) direkt hier anzeigt.
-- OGW

AOHofPC.FO_ZEILEN = 16

local t = AOHofPC.t
local F = AOHofPC.FARBE

local STUFEN = { [0] = "hl_stufeAzubi", [1] = "hl_stufeQuer", [2] = "hl_stufeAusgelernt", [3] = "hl_stufeEigen" }

local FO_BEREICHE = {
    { tab = 1, text = "ao_pc_foFelder" },
    { tab = 5, text = "ao_pc_foAufgaben" },
    { tab = 2, text = "ao_pc_foLager" },
    { tab = 3, text = "ao_pc_foTiere" },
    { tab = 4, text = "ao_pc_foProduktion" },
}

local function anAus(wert)
    return t(wert == 1 and "ao_pc_an" or "ao_pc_aus")
end

local function prozentText(anteil)
    return AOHofPC.zahl((anteil or 0) * 100, 1) .. " %"
end

local function wechselText()
    return AOHofPC.wechselText(AOHofPC.tageBisMonatswechsel())
end

function AOHofPC:fuelleAbgaben()
    local p = AOAbgaben ~= nil and AOAbgaben.paket or nil
    if p == nil then
        for r = 1, 7 do
            AOHofPC.text(self["abP" .. r], r == 1 and t("ao_pc_laedt") or "", F.grau)
            AOHofPC.text(self["abN" .. r], "")
            AOHofPC.text(self["abJ" .. r], "")
            AOHofPC.text(self["abV" .. r], "")
        end
        for k = 1, 8 do
            AOHofPC.text(self["abIL" .. k], "")
            AOHofPC.text(self["abIW" .. k], "")
        end
        for k = 1, 15 do
            AOHofPC.text(self["abHL" .. k], "")
            AOHofPC.text(self["abHW" .. k], "")
        end
        AOHofPC.zeigen(self.abBremse, false)
        AOHofPC.zeigen(self.abBremseGrund, false)
        AOHofPC.text(self.abBremseText, "")
        AOHofPC.text(self.abFuss, "")
        return
    end

    local fsFaellig = p.fsMonateBis <= 1 and p.fsNaechste or 0
    local naechste = {
        p.fsAktiv == 1 and AOHofPC.geld(p.fsNaechste) or t("ao_pc_aus"),
        p.gsAktiv == 1 and AOHofPC.geld(p.gsNaechste) or t("ao_pc_aus"),
        "-",
        "-",
        p.ziAktiv == 1 and AOHofPC.geld(p.ziNaechste) or t("ao_pc_aus"),
    }
    local kostenN = fsFaellig + p.gsNaechste
    local kostenJ = p.fsJahr + p.gsJahr + p.krJahr + p.hlJahr
    local kostenV = p.fsVorjahr + p.gsVorjahr + p.krVorjahr + p.hlVorjahr
    local zeilen = {
        { "ao_pc_abFs", naechste[1], p.fsJahr, p.fsVorjahr, F.aus },
        { "ao_pc_abGs", naechste[2], p.gsJahr, p.gsVorjahr, F.aus },
        { "ao_pc_abKredit", naechste[3], p.krJahr, p.krVorjahr, F.aus },
        { "ao_pc_abLohn", naechste[4], p.hlJahr, p.hlVorjahr, F.aus },
        { "ao_pc_abZins", naechste[5], p.ziJahr, p.ziVorjahr, F.gut },
        { "ao_pc_abSumme", AOHofPC.geld(kostenN), kostenJ, kostenV, F.aus },
        { "ao_pc_abStrich", AOHofPC.geld(kostenN - p.ziNaechste), kostenJ - p.ziJahr, kostenV - p.ziVorjahr, F.weiss },
    }
    for r, z in ipairs(zeilen) do
        AOHofPC.text(self["abP" .. r], t(z[1]), r >= 6 and F.akzent or F.weiss)
        AOHofPC.text(self["abN" .. r], z[2], F.grau)
        AOHofPC.text(self["abJ" .. r], AOHofPC.geld(z[3]), math.abs(z[3]) >= 0.5 and z[5] or F.grau)
        AOHofPC.text(self["abV" .. r], AOHofPC.geld(z[4]), F.grau)
    end

    local fsAbrechnung = t("ao_pc_monatlich")
    if p.fsJaehrlich == 1 then
        fsAbrechnung = AOHofPC.vorlage("ao_pc_jaehrlichIn", AOHofPC.zahl(p.fsMonateBis))
    end
    local info = {
        { "ao_pc_abFsInfo", AOHofPC.vorlage("ao_pc_abFsInfoWert",
            AOHofPC.zahl(p.fsAnzahl), AOHofPC.zahl(p.fsRuhend), AOHofPC.zahl(p.fsDach)) },
        { "ao_pc_abFsAbrechnung", fsAbrechnung },
        { "ao_pc_abKarenz", AOHofPC.vorlage("ao_pc_monate", AOHofPC.zahl(p.karenz)) },
        { "ao_pc_abGsInfo", AOHofPC.vorlage("ao_pc_abGsInfoWert",
            AOHofPC.geld(p.gsWert), AOHofPC.zahl(p.gsHa, 1), prozentText(p.gsSatz)) },
        { "ao_pc_abZiInfo", AOHofPC.vorlage("ao_pc_abZiInfoWert", AOHofPC.geld(p.ziBasis), prozentText(p.ziSatz)) },
        { "ao_pc_abZiLetzte", AOHofPC.geld(p.ziLetzte) },
        { "ao_pc_abKreditStand", AOHofPC.geld(p.krKredit) },
        { "ao_pc_stWechsel", wechselText() },
    }
    for k = 1, 8 do
        local z = info[k]
        AOHofPC.text(self["abIL" .. k], z ~= nil and t(z[1]) or "", F.grau)
        AOHofPC.text(self["abIW" .. k], z ~= nil and z[2] or "", F.weiss)
    end
    AOHofPC.text(self.abFuss, t("ao_pc_abFuss"), F.grau)

    local stufe = t(STUFEN[math.floor(p.hlStufe)] or "hl_stufeQuer")
    local lohnArt = AOHofPC.vorlage("ao_pc_hlStufeWert", stufe, AOHofPC.zahl(p.hlFaktor, 2))
    if p.hlModus == 1 then
        lohnArt = t("ao_pc_hlFestWert")
    end
    local budget = p.brSchnitt * p.brAnteil
    local kappung = t("ao_pc_brKeine")
    if p.kpTag > 0 then
        kappung = AOHofPC.vorlage("ao_pc_brKappungWert", AOHofPC.zahl(math.max(0, p.tag - p.kpTag)),
            AOHofPC.geld(p.kpEcht), AOHofPC.geld(p.kpGewollt),
            t(p.kpGrund == 2 and "ao_pc_brGrundKonto" or "ao_pc_brGrundDeckel"))
    end
    local helfer = {
        { "ao_pc_hlModul", anAus(p.hlAktiv) },
        { "ao_pc_hlModus", t(p.hlModus == 1 and "ao_pc_hlFest" or "ao_pc_hlStunde") },
        { "ao_pc_hlStufe", lohnArt },
        { "ao_pc_hlZufall", t(p.hlZufall == 1 and "ao_pc_hlZufallAn" or "ao_pc_hlZufallAus") },
        { "ao_pc_hlGratis", t(p.hlGratis == 1 and "ao_pc_hlGratisAn" or "ao_pc_hlGratisAus") },
        { "ao_pc_hlEinsatz", AOHofPC.zahl(p.hlEinsatz) },
        { "ao_pc_hlMonat", AOHofPC.geld(p.hlMonat) },
        { "ao_pc_brModul", anAus(p.brAktiv) },
        { "ao_pc_brDeckel", AOHofPC.vorlage("ao_pc_brDeckelWert", prozentText(p.brAnteil)) },
        { "ao_pc_brSchnitt", AOHofPC.geld(p.brSchnitt) },
        { "ao_pc_brBudget", budget > 0 and AOHofPC.geld(budget) or t("ao_pc_brKeinBudget") },
        { "ao_pc_brHeute", AOHofPC.geld(p.brHeute) },
        { "ao_pc_brMindest", AOHofPC.geld(p.brNotKonto) },
        { "ao_pc_brSpielraum", AOHofPC.geld(math.max(0, p.brGeld - p.brNotKonto)) },
        { "ao_pc_brKappung", kappung },
    }
    for k = 1, 15 do
        local z = helfer[k]
        AOHofPC.text(self["abHL" .. k], z ~= nil and t(z[1]) or "", F.grau)
        AOHofPC.text(self["abHW" .. k], z ~= nil and z[2] or "", F.weiss)
    end

    if p.brAktiv == 1 and budget > 0 then
        local anteil = p.brHeute / budget
        local farbe = F.ein
        if anteil >= 1 then
            farbe = F.neg
        elseif anteil >= 0.7 then
            farbe = F.mittel
        end
        AOHofPC.zeigen(self.abBremseGrund, true)
        AOHofPC.farbe(self.abBremse, farbe)
        AOHofPC.breite(self.abBremse, anteil)
        AOHofPC.text(self.abBremseText, AOHofPC.vorlage("ao_pc_brBalken",
            AOHofPC.geld(p.brHeute), AOHofPC.geld(budget)), F.grau)
    else
        AOHofPC.zeigen(self.abBremseGrund, false)
        AOHofPC.zeigen(self.abBremse, false)
        AOHofPC.text(self.abBremseText, "", F.grau)
    end
end

function AOHofPC:foVorbereiten()
    local namen = {}
    for i, b in ipairs(FO_BEREICHE) do
        namen[i] = t(b.text)
    end
    AOHofPC.optionen(self.foOptBereich, namen, self.fo.bereich)
end

function AOHofPC:foAnfordern(mitAbgleich)
    local env = AOHofPC.foUmgebung()
    self.fo.zeilen = {}
    self.fo.fuss = nil
    if env == nil then
        return
    end
    local fa = env.FruchtfolgeAdvisor
    if mitAbgleich then
        if env.Bodengesundheit ~= nil and env.Bodengesundheit.requestSync ~= nil then
            env.Bodengesundheit.requestSync()
        end
        if env.FruitMemoryEvent ~= nil and env.FruitMemoryEvent.request ~= nil then
            env.FruitMemoryEvent.request()
        end
        if env.CropSelectionEvent ~= nil and env.CropSelectionEvent.request ~= nil then
            env.CropSelectionEvent.request()
        end
        if env.TaskStateEvent ~= nil and env.TaskStateEvent.request ~= nil then
            env.TaskStateEvent.request()
        end
    end
    if fa.buildCache ~= nil then
        fa.buildCache()
    end
    local bereich = FO_BEREICHE[self.fo.bereich] or FO_BEREICHE[1]
    if bereich.tab == 5 and env.TaskAnalyzer ~= nil and env.TaskAnalyzer.getRows ~= nil then
        if env.TaskAnalyzer.build ~= nil then
            env.TaskAnalyzer.build()
        end
        self.fo.zeilen = env.TaskAnalyzer.getRows(self.fo.aufgeklappt) or {}
    elseif bereich.tab == 1 and fa.getFieldRows ~= nil then
        self.fo.zeilen = fa.getFieldRows(self.fo.feldOffen) or {}
    else
        self.fo.zeilen = fa.getSectionRows(bereich.tab) or {}
    end
    if fa.getShortageLine ~= nil then
        local text, farbe = fa.getShortageLine()
        self.fo.fuss = { text = text, farbe = farbe }
    end
end

function AOHofPC:onClickFoBereich(state)
    self.fo.bereich = state
    self.fo.start = 0
    self.fo.feldOffen = nil
    self.foTakt = 0
    self:foAnfordern(false)
    self:fuelleOverview()
end

function AOHofPC:onClickFoSeite(state)
    self.fo.start = (state - 1) * AOHofPC.FO_ZEILEN
    self:fuelleOverview()
end

local function farbeVon(col)
    if type(col) ~= "table" then
        return F.weiss
    end
    return { col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1 }
end

local function foZeileVon(self, prefix, element)
    for j = 1, AOHofPC.FO_ZEILEN do
        if self[prefix .. j] == element then
            return self.fo.sichtbar ~= nil and self.fo.sichtbar[j] or nil
        end
    end
    return nil
end

function AOHofPC:onClickFoZeile(element)
    local r = foZeileVon(self, "foZeile", element)
    local env = AOHofPC.foUmgebung()
    if r == nil or env == nil then
        return
    end
    if r.fieldIndex ~= nil then
        if self.fo.feldOffen == r.fieldIndex then
            self.fo.feldOffen = nil
        else
            self.fo.feldOffen = r.fieldIndex
        end
    elseif r.collapse ~= nil then
        self.fo.feldOffen = nil
    elseif r.feldBlock ~= nil then
        self.fo.aufgeklappt[r.feldBlock] = not self.fo.aufgeklappt[r.feldBlock] or nil
    elseif r.taskKey ~= nil and env.TaskState ~= nil and env.TaskState.cycle ~= nil then
        env.TaskState.cycle(r.taskKey)
    else
        return
    end
    self:foAnfordern(false)
    self:fuelleOverview()
end

function AOHofPC:onClickFoOeffnen(element)
    local r = foZeileVon(self, "foOeffnen", element)
    local env = AOHofPC.foUmgebung()
    if r ~= nil and r.stall ~= nil and env ~= nil and env.FruchtfolgeAdvisor ~= nil
            and env.FruchtfolgeAdvisor.stallOeffnen ~= nil then
        self:close()
        if env.FruchtfolgeAdvisor.stallOeffnen(r.stall) then
            AOHofPC.stallWache = { zeit = 0, offen = false }
        end
    end
end

function AOHofPC:fuelleOverview()
    local kopf = nil
    local zeilen = {}
    for _, r in ipairs(self.fo.zeilen or {}) do
        if r.head ~= nil then
            if kopf == nil then
                kopf = r.head
            end
        elseif r.section ~= nil or r.cells ~= nil then
            table.insert(zeilen, r)
        end
    end

    for n = 1, 6 do
        AOHofPC.text(self["foH" .. n], kopf ~= nil and tostring(kopf[n] or "") or "", F.grau)
    end

    local erstes, seite, seiten = AOHofPC.fenster(self.fo, #zeilen, AOHofPC.FO_ZEILEN)
    local seitenTexte = {}
    for s = 1, seiten do
        seitenTexte[s] = AOHofPC.vorlage("ao_mk_seiteVon", s, seiten)
    end
    AOHofPC.optionen(self.foOptSeite, seitenTexte, seite)

    self:rollleiste("foRoll", erstes, #zeilen, AOHofPC.FO_ZEILEN)
    local spalten = { "A", "B", "C", "D", "E", "F" }
    self.fo.sichtbar = {}
    for j = 1, AOHofPC.FO_ZEILEN do
        local r = zeilen[erstes + j]
        self.fo.sichtbar[j] = r
        AOHofPC.zeigen(self["foZeile" .. j], r ~= nil and (r.feldBlock ~= nil or r.taskKey ~= nil
            or r.fieldIndex ~= nil or r.collapse ~= nil))
        AOHofPC.zeigen(self["foOeffnen" .. j], r ~= nil and r.stall ~= nil)
        if r ~= nil and r.section ~= nil then
            AOHofPC.text(self["foS" .. j], tostring(r.section), farbeVon(r.col or { 0.60, 0.95, 0.35 }))
            for _, s in ipairs(spalten) do
                AOHofPC.text(self["fo" .. s .. j], "")
            end
        else
            AOHofPC.text(self["foS" .. j], "")
            local zellen = r ~= nil and r.cells or {}
            for n, s in ipairs(spalten) do
                local z = zellen[n]
                AOHofPC.text(self["fo" .. s .. j], z ~= nil and tostring(z.t or "") or "", farbeVon(z ~= nil and z.col or nil))
            end
        end
    end

    local leer = ""
    if AOHofPC.foUmgebung() == nil then
        leer = t("ao_pc_foFehlt")
    elseif #zeilen == 0 then
        leer = t("ao_pc_foLeer")
    end
    AOHofPC.text(self.foLeer, leer, F.grau)

    local fuss = t("ao_pc_foHinweis")
    local farbe = F.grau
    if self.fo.fuss ~= nil and type(self.fo.fuss.text) == "string" and self.fo.fuss.text ~= "" then
        fuss = self.fo.fuss.text .. "\n" .. fuss
        farbe = farbeVon(self.fo.fuss.farbe)
    end
    AOHofPC.text(self.foFuss, fuss, farbe)
end
