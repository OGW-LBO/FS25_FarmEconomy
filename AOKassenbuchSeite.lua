-- AOKassenbuchSeite.lua
-- Macht aus den Buchungen des Kassenbuchs eine fertige HTML-Seite mit
-- Diagrammen, die im Spielstand-Ordner liegt und sich im Browser oeffnen
-- laesst. Alles steckt in der einen Datei, es wird nichts nachgeladen.
-- OGW

AOKassenbuchSeite = {}

-- Reihenfolge und Farben der drei Reihen; neg ist nur das Vorzeichen beim Saldo
AOKassenbuchSeite.REIHEN = {
    { id = "ein", label = "ao_buch_ein" },
    { id = "aus", label = "ao_buch_aus" },
    { id = "inv", label = "ao_buch_inv" },
}

AOKassenbuchSeite.ART = {
    ernte = "ein", produkte = "ein", tiere = "ein", ballenHolz = "ein",
    energie = "ein", auftraege = "ein", sonstEin = "ein",
    betriebsmittel = "aus", fahrzeugKosten = "aus", gebaeudeKosten = "aus",
    loehne = "aus", zinsen = "aus", sonstAus = "aus",
    investFahrzeuge = "inv", investBau = "inv", investLand = "inv",
    investTiere = "inv",
}

local BREITE = 980

-- %d verlangt in neueren Lua-Fassungen eine echte Ganzzahl
local function ganz(wert)
    return math.floor(wert + 0.5)
end

local function t(schluessel)
    if AOSettingsPage ~= nil and AOSettingsPage.getText ~= nil then
        return AOSettingsPage.getText(schluessel)
    end
    return schluessel
end

local function esc(text)
    local s = tostring(text or "")
    s = string.gsub(s, "&", "&amp;")
    s = string.gsub(s, "<", "&lt;")
    s = string.gsub(s, ">", "&gt;")
    s = string.gsub(s, '"', "&quot;")
    return s
end

local function geld(wert, mitPlus)
    if wert == nil then
        return "-"
    end
    local txt = AgrarOekonomie.formatGeld(wert)
    if mitPlus and wert > 0 then
        return "+" .. txt
    end
    return txt
end

-- Kurzform fuer Achsen: 120000 -> 120K, 2400000 -> 2,4M
local function kurz(wert)
    local betrag = math.abs(wert)
    if betrag >= 1000000 then
        local v = wert / 1000000
        if g_i18n ~= nil and g_i18n.formatNumber ~= nil then
            return g_i18n:formatNumber(v, 1) .. "M"
        end
        return string.format("%.1fM", v)
    end
    if betrag >= 1000 then
        return string.format("%dK", ganz(wert / 1000))
    end
    return string.format("%d", ganz(wert))
end

local function monatsName(nr)
    if AOBericht ~= nil and AOBericht.monatsName ~= nil then
        return AOBericht.monatsName(nr)
    end
    return tostring(nr)
end

local function jahrText(jahr)
    local vorlage = t("ao_buch_jahr")
    if string.find(vorlage, "%%s") ~= nil then
        return string.format(vorlage, tostring(jahr))
    end
    return vorlage .. " " .. tostring(jahr)
end

-- Achsen ---------------------------------------------------------------------

local function achsenSchritt(maxwert, ziel)
    if maxwert <= 0 then
        return 1
    end
    local roh   = maxwert / ziel
    local stellen = 0
    local rest = math.floor(roh)
    while rest >= 10 do
        rest = math.floor(rest / 10)
        stellen = stellen + 1
    end
    local stufe = 10 ^ stellen
    for _, f in ipairs({ 1, 2, 2.5, 5, 10 }) do
        if stufe * f >= roh then
            return stufe * f
        end
    end
    return stufe * 10
end

-- Die Obergrenze liegt immer ueber dem groessten Wert, sonst ragen die
-- Saeulen aus dem Diagramm heraus.
local function achseSchritte(maxwert, ziel)
    if maxwert <= 0 then
        return { 0 }, 1
    end
    local schritt = achsenSchritt(maxwert, ziel)
    local werte   = { 0 }
    local v       = 0
    while v < maxwert - schritt * 0.000001 do
        v = v + schritt
        table.insert(werte, v)
    end
    return werte, werte[#werte]
end

-- Formen ---------------------------------------------------------------------

local function titelTag(titel)
    if titel == nil or titel == "" then
        return ""
    end
    return "<title>" .. esc(titel) .. "</title>"
end

-- Saeule mit abgerundetem Datenende, am Nullpunkt eckig
local function saeule(x, y, breite, hoehe, farbe, titel)
    if hoehe <= 0.5 then
        hoehe = 0.5
    end
    local r = math.min(4, breite / 2, hoehe)
    local d = string.format(
        "M%.2f %.2f V%.2f a%.2f %.2f 0 0 1 %.2f -%.2f H%.2f a%.2f %.2f 0 0 1 %.2f %.2f V%.2f Z",
        x, y + hoehe, y + r, r, r, r, r, x + breite - r, r, r, r, r, y + hoehe)
    return string.format('<path d="%s" fill="%s">%s</path>', d, farbe, titelTag(titel))
end

local function saeuleAbwaerts(x, y, breite, hoehe, farbe, titel)
    if hoehe <= 0.5 then
        hoehe = 0.5
    end
    local r = math.min(4, breite / 2, hoehe)
    local d = string.format(
        "M%.2f %.2f H%.2f V%.2f a%.2f %.2f 0 0 1 -%.2f %.2f H%.2f a%.2f %.2f 0 0 1 -%.2f -%.2f Z",
        x, y, x + breite, y + hoehe - r, r, r, r, r, x + r, r, r, r, r)
    return string.format('<path d="%s" fill="%s">%s</path>', d, farbe, titelTag(titel))
end

local function balken(x, y, breite, hoehe, farbe, titel)
    if breite <= 0.5 then
        breite = 0.5
    end
    local r = math.min(4, hoehe / 2, breite)
    local d = string.format(
        "M%.2f %.2f H%.2f a%.2f %.2f 0 0 1 %.2f %.2f V%.2f a%.2f %.2f 0 0 1 -%.2f %.2f H%.2f Z",
        x, y, x + breite - r, r, r, r, r, y + hoehe - r, r, r, r, r, x)
    return string.format('<path d="%s" fill="%s">%s</path>', d, farbe, titelTag(titel))
end

-- Diagramme ------------------------------------------------------------------

function AOKassenbuchSeite.monatsDiagramm(monate)
    local H = 300
    local links, rechts, oben, unten = 76, 16, 16, 46
    local pw, ph = BREITE - links - rechts, H - oben - unten

    local maxwert = 0
    for _, m in ipairs(monate) do
        maxwert = math.max(maxwert, m.ein, m.aus, m.inv)
    end
    local ticks, obergrenze = achseSchritte(maxwert, 4)

    local n     = math.max(1, #monate)
    local band  = pw / n
    local dicke = math.min(24, (band - 10) / 3 - 2)
    local breit = dicke * 3 + 4

    local teile = {}
    for _, tick in ipairs(ticks) do
        local y = oben + ph - (tick / obergrenze) * ph
        table.insert(teile, string.format(
            '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="grid"/>', links, y, BREITE - rechts, y))
        table.insert(teile, string.format(
            '<text x="%.1f" y="%.1f" class="tick ta-end">%s</text>', links - 10, y + 4, esc(kurz(tick))))
    end

    -- beschriftet wird nur der hoechste Balken ueberhaupt
    local hoch, hochReihe = 1, 1
    for i, m in ipairs(monate) do
        for r, reihe in ipairs(AOKassenbuchSeite.REIHEN) do
            if m[reihe.id] > monate[hoch][AOKassenbuchSeite.REIHEN[hochReihe].id] then
                hoch, hochReihe = i, r
            end
        end
    end

    local wechsel = {}
    for i, m in ipairs(monate) do
        local x0 = links + (i - 1) * band + (band - breit) / 2
        for r, reihe in ipairs(AOKassenbuchSeite.REIHEN) do
            local wert = m[reihe.id]
            local h    = (wert / obergrenze) * ph
            table.insert(teile, saeule(x0 + (r - 1) * (dicke + 2), oben + ph - h, dicke, h,
                "var(--c-" .. reihe.id .. ")",
                monatsName(m.monat) .. " " .. jahrText(m.jahr) .. ", " .. t(reihe.label) .. ": " .. geld(wert)))
        end
        table.insert(teile, string.format(
            '<text x="%.1f" y="%.1f" class="tick ta-mid">%s</text>',
            links + (i - 1) * band + band / 2, oben + ph + 18, esc(monatsName(m.monat))))
        if i == 1 or m.jahr ~= monate[i - 1].jahr then
            table.insert(wechsel, { i, m.jahr })
        end
        if i == hoch then
            local spitze = m[AOKassenbuchSeite.REIHEN[hochReihe].id]
            if spitze > 0 then
                local h = (spitze / obergrenze) * ph
                table.insert(teile, string.format(
                    '<text x="%.1f" y="%.1f" class="wert ta-mid">%s</text>',
                    x0 + (hochReihe - 1) * (dicke + 2) + dicke / 2, oben + ph - h - 8, esc(kurz(spitze))))
            end
        end
    end

    for k, eintrag in ipairs(wechsel) do
        local bis = n + 1
        if wechsel[k + 1] ~= nil then
            bis = wechsel[k + 1][1]
        end
        local x1 = links + (eintrag[1] - 1) * band
        local x2 = links + (bis - 1) * band
        table.insert(teile, string.format(
            '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="grid"/>',
            x1 + 2, oben + ph + 30, x2 - 2, oben + ph + 30))
        table.insert(teile, string.format(
            '<text x="%.1f" y="%.1f" class="tick ta-mid">%s</text>',
            (x1 + x2) / 2, oben + ph + 42, esc(jahrText(eintrag[2]))))
    end

    table.insert(teile, string.format(
        '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="basis"/>',
        links, oben + ph, BREITE - rechts, oben + ph))

    return string.format('<svg viewBox="0 0 %d %d">%s</svg>', ganz(BREITE), ganz(H), table.concat(teile))
end

function AOKassenbuchSeite.saldoDiagramm(monate)
    local H = 210
    local links, rechts, oben, unten = 76, 16, 14, 40
    local pw, ph = BREITE - links - rechts, H - oben - unten

    local maxplus, maxminus = 0, 0
    for _, m in ipairs(monate) do
        maxplus  = math.max(maxplus, m.saldo)
        maxminus = math.max(maxminus, -m.saldo)
    end

    local schritt = achsenSchritt(math.max(maxplus, maxminus, 1), 2)
    local obenG   = math.ceil(maxplus / schritt) * schritt
    local untenG  = math.ceil(maxminus / schritt) * schritt
    local spanne  = obenG + untenG
    if spanne <= 0 then
        spanne = schritt
    end
    local skala = ph / spanne
    local null  = oben + obenG * skala

    local n     = math.max(1, #monate)
    local band  = pw / n
    local dicke = math.min(24, band - 8)

    local teile = {}
    local von   = -math.floor(untenG / schritt + 0.5)
    local bis   = math.floor(obenG / schritt + 0.5)
    for k = von, bis do
        local wert = k * schritt
        local y    = null - wert * skala
        local art  = "grid"
        if k == 0 then
            art = "basis"
        end
        table.insert(teile, string.format(
            '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="%s"/>', links, y, BREITE - rechts, y, art))
        table.insert(teile, string.format(
            '<text x="%.1f" y="%.1f" class="tick ta-end">%s</text>', links - 10, y + 4, esc(kurz(wert))))
    end

    for i, m in ipairs(monate) do
        local h     = math.abs(m.saldo) * skala
        local x     = links + (i - 1) * band + (band - dicke) / 2
        local titel = monatsName(m.monat) .. " " .. jahrText(m.jahr) .. ": " .. geld(m.saldo, true)
        if m.saldo >= 0 then
            table.insert(teile, saeule(x, null - h, dicke, h, "var(--c-ein)", titel))
        else
            table.insert(teile, saeuleAbwaerts(x, null, dicke, h, "var(--c-neg)", titel))
        end
        table.insert(teile, string.format(
            '<text x="%.1f" y="%.1f" class="tick ta-mid">%s</text>',
            links + (i - 1) * band + band / 2, oben + ph + 18, esc(monatsName(m.monat))))
    end

    return string.format('<svg viewBox="0 0 %d %d">%s</svg>', ganz(BREITE), ganz(H), table.concat(teile))
end

function AOKassenbuchSeite.rangliste(posten)
    if #posten == 0 then
        return ""
    end
    local zeilenhoehe, dicke = 30, 18
    local labelBreite, wertBreite = 190, 118
    local pw = BREITE - labelBreite - wertBreite
    local H  = zeilenhoehe * #posten + 8

    local maxwert = 0
    for _, p in ipairs(posten) do
        maxwert = math.max(maxwert, math.abs(p.betrag))
    end
    if maxwert <= 0 then
        maxwert = 1
    end

    local teile = {}
    for i, p in ipairs(posten) do
        local y = 4 + (i - 1) * zeilenhoehe
        local b = math.abs(p.betrag) / maxwert * pw
        table.insert(teile, string.format(
            '<text x="%d" y="%.1f" class="kat">%s</text>', ganz(labelBreite - 12), y + dicke / 2 + 4, esc(p.name)))
        table.insert(teile, balken(labelBreite, y + (zeilenhoehe - dicke) / 2 - 4, b, dicke,
            "var(--c-" .. p.art .. ")",
            p.name .. ": " .. geld(math.abs(p.betrag)) .. " (" .. string.format("%d", ganz(p.anteil * 100)) .. " %)"))
        table.insert(teile, string.format(
            '<text x="%.1f" y="%.1f" class="wert">%s<tspan class="anteil">  %d %%</tspan></text>',
            labelBreite + b + 10, y + dicke / 2 + 4, esc(geld(math.abs(p.betrag))),
            ganz(p.anteil * 100)))
    end

    return string.format('<svg viewBox="0 0 %d %d">%s</svg>', ganz(BREITE), ganz(H), table.concat(teile))
end

function AOKassenbuchSeite.kontoDiagramm(punkte)
    if #punkte < 2 then
        return ""
    end
    local H = 240
    local links, rechts, oben, unten = 76, 70, 16, 40
    local pw, ph = BREITE - links - rechts, H - oben - unten

    local hoch, tief = punkte[1].wert, punkte[1].wert
    for _, p in ipairs(punkte) do
        hoch = math.max(hoch, p.wert)
        tief = math.min(tief, p.wert)
    end
    tief = math.min(0, tief)
    if hoch <= tief then
        hoch = tief + 1
    end
    local ticks, obergrenze = achseSchritte(hoch, 4)

    local function ypos(wert)
        return oben + ph - ((wert - tief) / (obergrenze - tief)) * ph
    end
    local function xpos(i)
        return links + ((i - 1) / (#punkte - 1)) * pw
    end

    local teile = {}
    for _, tick in ipairs(ticks) do
        if tick >= tief then
            local y = ypos(tick)
            table.insert(teile, string.format(
                '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="grid"/>', links, y, BREITE - rechts, y))
            table.insert(teile, string.format(
                '<text x="%.1f" y="%.1f" class="tick ta-end">%s</text>', links - 10, y + 4, esc(kurz(tick))))
        end
    end

    local pfad = {}
    for i, p in ipairs(punkte) do
        local befehl = "L"
        if i == 1 then
            befehl = "M"
        end
        table.insert(pfad, string.format("%s%.2f %.2f", befehl, xpos(i), ypos(p.wert)))
    end
    table.insert(teile, string.format('<path d="%s" class="linie"/>', table.concat(pfad, " ")))

    -- groessere, unsichtbare Flaechen, damit der Zeiger etwas zu fassen hat
    local schritt = math.max(1, math.floor(#punkte / 60))
    local i = 1
    while i <= #punkte do
        table.insert(teile, string.format(
            '<circle cx="%.1f" cy="%.1f" r="9" fill="transparent">%s</circle>',
            xpos(i), ypos(punkte[i].wert), titelTag(punkte[i].label .. ": " .. geld(punkte[i].wert))))
        i = i + schritt
    end

    local letzter = punkte[#punkte]
    table.insert(teile, string.format('<circle cx="%.1f" cy="%.1f" r="5" class="punkt"/>',
        xpos(#punkte), ypos(letzter.wert)))
    table.insert(teile, string.format('<text x="%.1f" y="%.1f" class="wert">%s</text>',
        xpos(#punkte) + 10, ypos(letzter.wert) + 4, esc(kurz(letzter.wert))))
    table.insert(teile, string.format(
        '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="basis"/>',
        links, oben + ph, BREITE - rechts, oben + ph))
    table.insert(teile, string.format('<text x="%.1f" y="%.1f" class="tick">%s</text>',
        links, oben + ph + 20, esc(punkte[1].label)))
    table.insert(teile, string.format('<text x="%.1f" y="%.1f" class="tick ta-end">%s</text>',
        BREITE - rechts, oben + ph + 20, esc(letzter.label)))

    return string.format('<svg viewBox="0 0 %d %d">%s</svg>', ganz(BREITE), ganz(H), table.concat(teile))
end

-- Zahlen ---------------------------------------------------------------------

local function artVon(gruppe, betrag)
    local art = AOKassenbuchSeite.ART[gruppe]
    if art ~= nil then
        return art
    end
    if betrag >= 0 then
        return "ein"
    end
    return "aus"
end

function AOKassenbuchSeite.auswerten(zeilen)
    local monateMap, reihenfolge = {}, {}
    local gruppen, gruppenListe = {}, {}
    local punkte = {}
    local summen = { ein = 0, aus = 0, inv = 0, kredit = 0 }

    for _, z in ipairs(zeilen) do
        local art = artVon(z.gruppe, z.betrag)
        if z.gruppe == "kredit" then
            art = "kredit"
        end

        local schluessel = z.jahr * 100 + z.monat
        local m = monateMap[schluessel]
        if m == nil then
            m = { jahr = z.jahr, monat = z.monat, ein = 0, aus = 0, inv = 0, kredit = 0, gruppen = {} }
            monateMap[schluessel] = m
            table.insert(reihenfolge, schluessel)
        end
        if art == "ein" or art == "kredit" then
            m[art] = m[art] + z.betrag
            summen[art] = summen[art] + z.betrag
        else
            m[art] = m[art] + math.abs(z.betrag)
            summen[art] = summen[art] + math.abs(z.betrag)
        end
        m.gruppen[z.gruppe] = (m.gruppen[z.gruppe] or 0) + z.betrag

        local g = gruppen[z.gruppe]
        if g == nil then
            g = { id = z.gruppe, name = z.text, art = art, betrag = 0 }
            gruppen[z.gruppe] = g
            table.insert(gruppenListe, g)
        end
        g.betrag = g.betrag + z.betrag

        if z.konto ~= nil then
            table.insert(punkte, {
                label = monatsName(z.monat) .. " " .. jahrText(z.jahr),
                wert  = z.konto,
            })
        end
    end

    table.sort(reihenfolge)
    local monate = {}
    for _, schluessel in ipairs(reihenfolge) do
        local m = monateMap[schluessel]
        m.saldo = m.ein - m.aus - m.inv + m.kredit
        table.insert(monate, m)
    end

    return monate, gruppenListe, punkte, summen
end

local function rangposten(gruppen, arten)
    local posten, gesamt = {}, 0
    for _, g in ipairs(gruppen) do
        for _, art in ipairs(arten) do
            if g.art == art then
                table.insert(posten, g)
                gesamt = gesamt + math.abs(g.betrag)
                break
            end
        end
    end
    table.sort(posten, function(a, b) return math.abs(a.betrag) > math.abs(b.betrag) end)
    if gesamt <= 0 then
        gesamt = 1
    end
    local aus = {}
    for _, g in ipairs(posten) do
        table.insert(aus, { name = g.name, betrag = g.betrag, art = g.art,
                            anteil = math.abs(g.betrag) / gesamt })
    end
    return aus
end

-- Seite ----------------------------------------------------------------------

local CSS = [==[
:root{color-scheme:light;
 --plane:#f9f9f7;--surface:#fcfcfb;--ink:#0b0b0b;--ink2:#52514e;--muted:#898781;
 --grid:#e1e0d9;--basis:#c3c2b7;--rahmen:rgba(11,11,11,.10);
 --c-ein:#2a78d6;--c-aus:#eb6834;--c-inv:#1baf7a;--c-neg:#e34948;--c-kredit:#6250d6;}
@media (prefers-color-scheme:dark){:root:where(:not([data-theme="light"])){color-scheme:dark;
 --plane:#0d0d0d;--surface:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;--muted:#898781;
 --grid:#2c2c2a;--basis:#383835;--rahmen:rgba(255,255,255,.10);
 --c-ein:#3987e5;--c-aus:#d95926;--c-inv:#199e70;--c-neg:#e66767;--c-kredit:#9085e9;}}
*{box-sizing:border-box}
body{margin:0;padding:32px 16px 64px;background:var(--plane);color:var(--ink);
 font:15px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif;}
.huelle{max-width:1060px;margin:0 auto}
h1{font-size:24px;font-weight:600;margin:0 0 4px}
.unter{color:var(--ink2);margin:0 0 28px}
.karte{background:var(--surface);border:1px solid var(--rahmen);border-radius:12px;
 padding:20px 22px 22px;margin:0 0 20px}
.karte h2{font-size:15px;font-weight:600;margin:0 0 2px}
.karte p.hin{color:var(--ink2);margin:0 0 14px;font-size:13px}
.kacheln{display:grid;grid-template-columns:repeat(auto-fit,minmax(168px,1fr));gap:12px;margin:0 0 20px}
.kachel{background:var(--surface);border:1px solid var(--rahmen);border-radius:12px;padding:16px 18px}
.kachel .lab{color:var(--ink2);font-size:13px;display:flex;align-items:center;gap:7px}
.kachel .val{font-size:26px;font-weight:600;margin-top:6px}
.kachel.held{grid-column:span 2}
.kachel.held .val{font-size:clamp(30px,4.2vw,48px);line-height:1.1;white-space:nowrap}
.punktfarbe{width:9px;height:9px;border-radius:50%;display:inline-block;flex:none}
svg{display:block;width:100%;height:auto;overflow:visible}
.grid{stroke:var(--grid);stroke-width:1}
.basis{stroke:var(--basis);stroke-width:1}
.tick{fill:var(--muted);font-size:11.5px;font-variant-numeric:tabular-nums}
.kat{fill:var(--ink2);font-size:13px;text-anchor:end}
.wert{fill:var(--ink);font-size:12.5px;font-variant-numeric:tabular-nums}
.anteil{fill:var(--muted)}
.ta-end{text-anchor:end}.ta-mid{text-anchor:middle}
.linie{fill:none;stroke:var(--c-ein);stroke-width:2;stroke-linejoin:round;stroke-linecap:round}
.punkt{fill:var(--c-ein);stroke:var(--surface);stroke-width:2}
.legende{display:flex;flex-wrap:wrap;gap:16px;margin:12px 0 0;color:var(--ink2);font-size:13px}
.legende span{display:flex;align-items:center;gap:7px}
table{border-collapse:collapse;width:100%;font-size:13.5px}
th,td{text-align:right;padding:7px 10px;border-bottom:1px solid var(--grid);
 font-variant-numeric:tabular-nums;white-space:nowrap}
th:first-child,td:first-child{text-align:left;font-variant-numeric:normal}
th{color:var(--ink2);font-weight:600;font-size:12.5px}
tbody tr:last-child td{border-bottom:none}
tr.sum td{font-weight:600;border-top:1px solid var(--basis)}
.rollen{overflow-x:auto}
details{margin:0 0 20px}
summary{cursor:pointer;color:var(--ink2);font-size:14px;padding:6px 0}
.minus{color:var(--c-neg)}
footer{color:var(--muted);font-size:12.5px;margin-top:28px}
]==]

local function kachel(label, wert, farbe, held)
    local punkt = ""
    if farbe ~= nil then
        punkt = '<span class="punktfarbe" style="background:' .. farbe .. '"></span>'
    end
    local klasse = "kachel"
    if held then
        klasse = "kachel held"
    end
    return string.format('<div class="%s"><div class="lab">%s%s</div><div class="val">%s</div></div>',
        klasse, punkt, esc(label), esc(wert))
end

local function legende(eintraege)
    local teile = {}
    for _, e in ipairs(eintraege) do
        table.insert(teile, string.format(
            '<span><span class="punktfarbe" style="background:var(--c-%s)"></span>%s</span>', e[1], esc(e[2])))
    end
    return '<div class="legende">' .. table.concat(teile) .. "</div>"
end

local function karte(titel, hinweis, inhalt, anhang)
    if inhalt == "" then
        return ""
    end
    return string.format('<div class="karte"><h2>%s</h2><p class="hin">%s</p>%s%s</div>',
        esc(titel), esc(hinweis), inhalt, anhang or "")
end

-- Die zwoelf groessten Einzelbuchungen einer Richtung
local function tabellePosten(zeilen, grosseZuerst, titel)
    local posten = {}
    for _, z in ipairs(zeilen) do
        if not z.summe then
            table.insert(posten, z)
        end
    end
    if #posten == 0 then
        return ""
    end
    table.sort(posten, function(a, b)
        if grosseZuerst then
            return a.betrag > b.betrag
        end
        return a.betrag < b.betrag
    end)

    local reihen = {}
    for i = 1, math.min(12, #posten) do
        local z = posten[i]
        local klasse = ""
        if z.betrag < 0 then
            klasse = ' class="minus"'
        end
        table.insert(reihen, string.format(
            "<tr><td>%s</td><td>%s</td><td>%s</td><td%s>%s</td></tr>",
            esc(monatsName(z.monat) .. " " .. jahrText(z.jahr) .. ", " .. z.zeit),
            esc(z.text), esc(z.kategorie), klasse, esc(geld(z.betrag, true))))
    end

    return string.format(
        '<div class="karte"><h2>%s</h2><p class="hin">%s</p><div class="rollen"><table><thead><tr>'
        .. "<th>%s</th><th>%s</th><th>%s</th><th>%s</th></tr></thead><tbody>%s</tbody></table></div></div>",
        esc(titel), esc(t("ao_buch_topHin")), esc(t("ao_buch_spZeit")), esc(t("ao_buch_spGruppe")),
        esc(t("ao_buch_spKat")), esc(t("ao_buch_spBetrag")), table.concat(reihen))
end

local function tabelleMonate(monate, gruppen)
    local kopf = {}
    for _, m in ipairs(monate) do
        table.insert(kopf, string.format("<th>%s<br>%s</th>", esc(monatsName(m.monat)), esc(jahrText(m.jahr))))
    end

    local sortiert = {}
    for _, g in ipairs(gruppen) do
        table.insert(sortiert, g)
    end
    table.sort(sortiert, function(a, b)
        if a.art ~= b.art then
            return a.art < b.art
        end
        return math.abs(a.betrag) > math.abs(b.betrag)
    end)

    local reihen = {}
    for _, g in ipairs(sortiert) do
        local zellen = {}
        for _, m in ipairs(monate) do
            local v = m.gruppen[g.id]
            if v == nil or v == 0 then
                table.insert(zellen, "<td>-</td>")
            else
                table.insert(zellen, "<td>" .. esc(geld(v)) .. "</td>")
            end
        end
        table.insert(reihen, string.format("<tr><td>%s</td>%s<td>%s</td></tr>",
            esc(g.name), table.concat(zellen), esc(geld(g.betrag))))
    end

    local summe, gesamt = {}, 0
    for _, m in ipairs(monate) do
        table.insert(summe, "<td>" .. esc(geld(m.saldo, true)) .. "</td>")
        gesamt = gesamt + m.saldo
    end
    table.insert(reihen, string.format('<tr class="sum"><td>%s</td>%s<td>%s</td></tr>',
        esc(t("ao_buch_saldo")), table.concat(summe), esc(geld(gesamt, true))))

    return string.format(
        '<div class="rollen"><table><thead><tr><th>%s</th>%s<th>%s</th></tr></thead><tbody>%s</tbody></table></div>',
        esc(t("ao_buch_spGruppe")), table.concat(kopf), esc(t("ao_buch_spGesamt")), table.concat(reihen))
end

function AOKassenbuchSeite.bauen(zeilen, hofText)
    local monate, gruppen, punkte, summen = AOKassenbuchSeite.auswerten(zeilen)
    local saldo = summen.ein - summen.aus - summen.inv + summen.kredit

    local zeitraum = "-"
    if #monate > 0 then
        local von = monatsName(monate[1].monat) .. " " .. jahrText(monate[1].jahr)
        local bis = monatsName(monate[#monate].monat) .. " " .. jahrText(monate[#monate].jahr)
        local vorlage = t("ao_buch_vonBis")
        if von == bis then
            zeitraum = von
        elseif select(2, string.gsub(vorlage, "%%s", "")) == 2 then
            zeitraum = string.format(vorlage, von, bis)
        else
            zeitraum = von .. ", " .. bis
        end
    end

    local kacheln = {
        kachel(t("ao_buch_saldo"), geld(saldo, true), nil, true),
        kachel(t("ao_buch_ein"), geld(summen.ein), "var(--c-ein)"),
        kachel(t("ao_buch_aus"), geld(summen.aus), "var(--c-aus)"),
        kachel(t("ao_buch_inv"), geld(summen.inv), "var(--c-inv)"),
    }
    if math.abs(summen.kredit) > 0.5 then
        table.insert(kacheln, kachel(t("ao_buch_kredit"), geld(summen.kredit, true), "var(--c-kredit)"))
    end

    local teile = {
        "<!doctype html><html><head><meta charset=\"utf-8\">",
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        "<title>", esc(t("ao_buch_titel")), "</title><style>", CSS, "</style></head><body>",
        '<div class="huelle"><h1>', esc(t("ao_buch_titel")), "</h1>",
        '<p class="unter">', esc(hofText .. ", " .. zeitraum .. ", " .. #zeilen .. " "
            .. t("ao_buch_buchungen")), "</p>",
        '<div class="kacheln">', table.concat(kacheln), "</div>",
        karte(t("ao_buch_monate"), t("ao_buch_monateHin"), AOKassenbuchSeite.monatsDiagramm(monate),
            legende({ { "ein", t("ao_buch_ein") }, { "aus", t("ao_buch_aus") }, { "inv", t("ao_buch_inv") } })),
        karte(t("ao_buch_saldoMon"), t("ao_buch_saldoHin"), AOKassenbuchSeite.saldoDiagramm(monate),
            legende({ { "ein", t("ao_buch_plus") }, { "neg", t("ao_buch_minus") } })),
        karte(t("ao_buch_weg"), t("ao_buch_wegHin"),
            AOKassenbuchSeite.rangliste(rangposten(gruppen, { "aus", "inv" })),
            legende({ { "aus", t("ao_buch_laufend") }, { "inv", t("ao_buch_inv") } })),
        karte(t("ao_buch_her"), t("ao_buch_herHin"),
            AOKassenbuchSeite.rangliste(rangposten(gruppen, { "ein", "kredit" }))),
        karte(t("ao_buch_konto"), t("ao_buch_kontoHin"), AOKassenbuchSeite.kontoDiagramm(punkte)),
        tabellePosten(zeilen, false, t("ao_buch_topAus")),
        tabellePosten(zeilen, true, t("ao_buch_topEin")),
        "<details><summary>", esc(t("ao_buch_alle")), '</summary><div class="karte">',
        tabelleMonate(monate, gruppen), "</div></details>",
        "<footer>", esc(t("ao_buch_fuss")), "</footer></div></body></html>",
    }

    return table.concat(teile)
end

function AOKassenbuchSeite.schreiben(zeilen, pfad, hofText)
    if pfad == nil or #zeilen == 0 then
        return false
    end
    if type(io) ~= "table" or type(io.open) ~= "function" then
        return false
    end
    -- FS25 laesst nur den Modus "w" zu, die Seite wird also jedes Mal neu gebaut
    local datei = io.open(pfad, "w")
    if datei == nil then
        return false
    end
    datei:write(AOKassenbuchSeite.bauen(zeilen, hofText))
    datei:close()
    return true
end
