-- AOHofPCKasse.lua
-- Seite Kassenbuch im Hof-PC: Rangliste der Gruppen mit Balken und die
-- letzten Buchungen, je Monat oder Jahr zum Durchblaettern. Die Zahlen kommen
-- aus AOKassenbuch, im Mehrspieler per AOKassenbuchEvent.
-- OGW

AOHofPC.KB_RANG  = 8
AOHofPC.KB_BUCH  = 12
AOHofPC.KB_MAX   = 120

local t = AOHofPC.t
local F = AOHofPC.FARBE

function AOHofPC.gruppeArt(id)
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

function AOHofPC.gruppeLabel(id)
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

local function jahrText(jahr)
    return AOHofPC.vorlage("ao_buch_jahr", jahr)
end

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
        local art = AOHofPC.gruppeArt(id)
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

function AOHofPC:kbVorbereiten()
    AOHofPC.optionen(self.kbOptAnsicht, { t("ao_buch_ansMonat"), t("ao_buch_ansJahr") }, self.kb.ansicht)
    self.kb.gewaehlt = nil
end

function AOHofPC:onClickKbAnsicht(state)
    self.kb.ansicht  = state
    self.kb.gewaehlt = nil
    self.kb.start    = 0
    self:fuelleKasse()
end

function AOHofPC:onClickKbZeitraum(state)
    local z = self.kb.zeitraeume[state]
    if z ~= nil then
        self.kb.gewaehlt = z.schluessel
    end
    self.kb.start = 0
    self:fuelleKasse()
end

function AOHofPC:kbZeitraeumeBauen(paket)
    local liste, gesehen = {}, {}
    for _, m in ipairs(paket.monate or {}) do
        if self.kb.ansicht == 2 then
            if not gesehen[m.jahr] then
                gesehen[m.jahr] = true
                table.insert(liste, { schluessel = m.jahr, jahr = m.jahr, text = jahrText(m.jahr) })
            end
        else
            table.insert(liste, {
                schluessel = m.jahr * 100 + m.monat, jahr = m.jahr, monat = m.monat,
                text = AOHofPC.monatName(m.monat) .. ", " .. jahrText(m.jahr),
            })
        end
    end
    return liste
end

function AOHofPC:kbVergleich(paket, ids, z, werte)
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
        bezug = AOHofPC.monatName(vm)
    elseif z.jahr == paket.jahr then
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
        table.insert(teile, AOHofPC.vorlage("ao_buch_vglEin", p))
    end
    p = prozent(ausNeu, ausAlt)
    if p ~= nil then
        table.insert(teile, AOHofPC.vorlage("ao_buch_vglAus", p))
    end
    if #teile == 0 then
        return t("ao_buch_fussDatei")
    end
    return AOHofPC.vorlage(schluessel, bezug, table.concat(teile, ", "))
end

function AOHofPC:fuelleKasse()
    local paket = AOKassenbuch ~= nil and AOKassenbuch.paket or nil
    if paket == nil then
        paket = { monate = {} }
    end
    local ids = AOKassenbuch.gruppenIds()

    self.kb.zeitraeume = self:kbZeitraeumeBauen(paket)
    local index = 1
    for i, z in ipairs(self.kb.zeitraeume) do
        if z.schluessel == self.kb.gewaehlt then
            index = i
        end
    end
    local gewaehlt = self.kb.zeitraeume[index]
    local texte = {}
    for i, z in ipairs(self.kb.zeitraeume) do
        texte[i] = z.text
    end
    AOHofPC.optionen(self.kbOptZeitraum, texte, index)

    local werte, letzte = {}, {}
    if gewaehlt ~= nil then
        werte = summieren(paket, #ids, function(m)
            if gewaehlt.monat ~= nil then
                return m.jahr == gewaehlt.jahr and m.monat == gewaehlt.monat
            end
            return m.jahr == gewaehlt.jahr
        end)
        for _, m in ipairs(paket.monate) do
            if m.jahr == gewaehlt.jahr and (gewaehlt.monat == nil or m.monat == gewaehlt.monat) then
                for _, e in ipairs(m.letzte or {}) do
                    if #letzte < AOHofPC.KB_MAX then
                        e.monat = m.monat
                        table.insert(letzte, e)
                    end
                end
            end
        end
    end

    local summen = { ein = 0, aus = 0, inv = 0, kredit = 0 }
    for i, id in ipairs(ids) do
        local betrag = werte[i] or 0
        local art    = AOHofPC.gruppeArt(id)
        if art == "ein" or art == "kredit" then
            summen[art] = summen[art] + betrag
        else
            summen[art] = summen[art] + math.abs(betrag)
        end
    end
    local saldo = summen.ein - summen.aus - summen.inv + summen.kredit

    local kopf = {
        { "ao_buch_ein", summen.ein, F.ein },
        { "ao_buch_aus", summen.aus, F.aus },
        { "ao_buch_inv", summen.inv, F.inv },
        { "ao_buch_saldo", saldo, saldo >= 0 and F.ein or F.neg },
    }
    for i, k in ipairs(kopf) do
        AOHofPC.text(self["kbLab" .. i], t(k[1]), F.grau)
        AOHofPC.text(self["kbWert" .. i], AOHofPC.geld(k[2]), k[3])
    end

    local posten = {}
    for i, id in ipairs(ids) do
        local betrag = werte[i] or 0
        local art    = AOHofPC.gruppeArt(id)
        if (art == "aus" or art == "inv") and math.abs(betrag) >= 0.5 then
            table.insert(posten, { name = AOHofPC.gruppeLabel(id), betrag = math.abs(betrag), art = art })
        end
    end
    table.sort(posten, function(a, b) return a.betrag > b.betrag end)
    local groesster = posten[1] ~= nil and posten[1].betrag or 0

    for i = 1, AOHofPC.KB_RANG do
        local p = posten[i]
        local balken = self["kbRangBalken" .. i]
        if p == nil then
            AOHofPC.text(self["kbRangLab" .. i], "")
            AOHofPC.text(self["kbRangWert" .. i], "")
            AOHofPC.zeigen(balken, false)
        else
            AOHofPC.text(self["kbRangLab" .. i], p.name, F.weiss)
            AOHofPC.text(self["kbRangWert" .. i], AOHofPC.geld(p.betrag), F.weiss)
            AOHofPC.farbe(balken, F[p.art] or F.aus)
            AOHofPC.breite(balken, groesster > 0 and math.max(0.01, p.betrag / groesster) or 0)
        end
    end

    local erstes = AOHofPC.fenster(self.kb, #letzte, AOHofPC.KB_BUCH)
    self:rollleiste("kbRoll", erstes, #letzte, AOHofPC.KB_BUCH)
    for i = 1, AOHofPC.KB_BUCH do
        local e = letzte[erstes + i]
        if e == nil then
            AOHofPC.text(self["kbZeit" .. i], "")
            AOHofPC.text(self["kbText" .. i], "")
            AOHofPC.text(self["kbBetrag" .. i], "")
        else
            local name = t("ao_buch_unbekannt")
            if AOKassenbuch.KATEGORIE_TEXT[e.kategorie or ""] ~= nil then
                name = t(AOKassenbuch.KATEGORIE_TEXT[e.kategorie])
            elseif e.gruppe >= 1 and ids[e.gruppe] ~= nil then
                name = AOHofPC.gruppeLabel(ids[e.gruppe])
            end
            local wann = e.zeit or ""
            if e.summe then
                wann = t("ao_buch_tagessumme")
            end
            AOHofPC.text(self["kbZeit" .. i], AOHofPC.monatName(e.monat) .. " " .. wann, F.grau)
            AOHofPC.text(self["kbText" .. i], name, F.weiss)
            AOHofPC.text(self["kbBetrag" .. i], AOHofPC.geld(e.betrag), e.betrag >= 0 and F.ein or F.neg)
        end
    end

    local fuss = t("ao_buch_leer")
    if gewaehlt ~= nil and (#posten > 0 or #letzte > 0 or summen.ein ~= 0) then
        fuss = self:kbVergleich(paket, ids, gewaehlt, werte)
    end
    AOHofPC.text(self.kbFuss, fuss, F.grau)
end
