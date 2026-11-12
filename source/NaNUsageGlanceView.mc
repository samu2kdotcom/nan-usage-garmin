using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application.Storage;
using Toybox.System;
using Toybox.Time;

//! Glance "nan.builders", coherente con la vista principal.
//!
//! El Dc de una GlanceView en el fr955 está recortado al contentArea
//! 176x93 (dc.getWidth()/getHeight() devuelven eso, no 260): todo se dibuja
//! con coordenadas RELATIVAS a w/h, padding de 7 px y nada a sangre. Sin red,
//! sin BLE y sin WatchUi.Layer: solo Application.Storage + dibujo, para
//! respetar los 64 KB del proceso glance.
//!
//! Piel de marca, en este orden: isotipo mini + wordmark "naN.builders",
//! hairline DK_GRAY de 1 px, % de créditos consumidos grande (used/allowance
//! del bloque "credits" de /v1/usage) con el "%" en COLOR_PURPLE, etiqueta
//! "CONSUMIDO" en MAYÚSCULAS, la edad del último fetch ("HACE 12S" /
//! "HACE 3 MIN", leída de Storage, sin red) y la fila "QUEDAN" con los
//! créditos restantes en color de severidad (señal crítica que se conserva).
//! Si el presupuesto vertical no alcanza, la marca se comprime (hairline) u
//! oculta PRIMERO; el % y "QUEDAN" NUNCA se ocultan.
//! Solo fuentes de sistema (FONT_GLANCE* / FONT_XTINY): nada de vector fonts
//! en el proceso de glance.
(:glance)
class NaNUsageGlanceView extends WatchUi.GlanceView {

    private var mWordmark;   //!< BitmapResource del wordmark, o null
    private var mIsoMini;    //!< BitmapResource del isotipo mini, o null

    // Mismos umbrales que la vista principal (verde < 50 %, ámbar 50-80 %,
    // rojo > 80 %). Solo constantes COLOR_*: el fr955 cuantiza cualquier
    // 0xRRGGBB a su paleta de 64 colores.
    private function severityColor(frac as Lang.Float) as Graphics.ColorType {
        if (frac > 0.8) {
            return Graphics.COLOR_RED;
        }
        if (frac >= 0.5) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_GREEN;
    }

    //! Conversión JSON/Storage -> Float a prueba de tipos (gemela de
    //! QuotaStore.asFloat, que NO puede enlazarse aquí: el proceso de glance
    //! sólo enlaza código anotado (:glance) y QuotaStore no lo está). El
    //! parser de JSON/Storage puede entregar Number (int 32), Long (int 64),
    //! Float o Double según el origen del valor.
    private function toFloat(v) as Lang.Float or Null {
        if (v == null) {
            return null;
        }
        if (v instanceof Lang.Float || v instanceof Lang.Double
                || v instanceof Lang.Number || v instanceof Lang.Long) {
            return v * 1.0;
        }
        return null;
    }

    //! Formato compacto de créditos (gemelo de QuotaStore.creditLabel, por el
    //! mismo motivo de enlazado): < 1000 -> entero ("320"); >= 1000 -> una
    //! decimal y "K" ("3.9K", "7.0K").
    private function creditLabel(v as Lang.Float) as Lang.String {
        if (v == null) {
            return "?";
        }
        if (v < 0.0) {
            v = 0.0;
        }
        if (v < 1000.0) {
            return (v + 0.5).toNumber().toString();
        }
        var tenths = (v / 100.0 + 0.5).toNumber();
        return (tenths / 10) + "." + (tenths % 10) + "K";
    }

    //! Texto ajustado al contentArea (fitTextToArea recorta con elipsis).
    private function fitMsg(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number, text as Lang.String) as Lang.String {
        var fitted = Graphics.fitTextToArea(text, Graphics.FONT_XTINY, w - 16, h - 8, true);
        if (fitted == null) {
            return text;
        }
        return fitted;
    }

    function initialize() {
        GlanceView.initialize();
        // CRASH A (fix): el proceso de glance sólo enlaza el código anotado
        // (:glance). El módulo Rez generado (Rez.mcgen) NO está anotado, así
        // que en el reloj "Rez" no existe en este proceso y las dos llamadas
        // loadResource(Rez.Drawables...) abortaban el glance con
        // "Illegal Access: Could not access symbol 'Rez'" (fr955 fw 29.05,
        // NaNUsageGlanceView.mc:90) y dejaban la entrada de la lista de apps
        // sin título. El GlanceRez que genera el compilador para este
        // proyecto sólo contiene Styles (no hay layouts de glance), así que
        // no hay ResourceIds de marca disponibles aquí. Los bitmaps de marca
        // siguen en la vista principal (ahí Rez sí existe); en la glance se
        // usa el fallback con primitivas que ya implementaba
        // drawBrandHeader() (hexágono violeta/verde + "naN.builders").
        mWordmark = null;
        mIsoMini = null;
    }

    function onLayout(dc as Graphics.Dc) {
        GlanceView.onLayout(dc);
    }

    //! Cabecera de marca con niveles de compresión (guard de altura B4: la
    //! marca es lo PRIMERO que se sacrifica, el % y "QUEDAN" NUNCA):
    //!   0 = completa: isotipo + wordmark + hairline
    //!   1 = comprimida: sólo la hairline de 1 px
    //!   2 = oculta
    //! Devuelve la y donde cuelga el contenido (26 / 6 / 5).
    private function drawBrandHeader(dc as Graphics.Dc, w as Lang.Number, level as Lang.Number) as Lang.Number {
        if (level == 2) {
            return 5;
        }
        if (level == 1) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(7, 3, w - 7, 3);
            return 6;
        }

        var pad = 7;
        var isoH = 16;
        var wmH = 15;

        // Isotipo mini (bitmap oficial cuantizado, fallback con primitivas).
        if (mIsoMini != null) {
            dc.drawBitmap(pad, 3, mIsoMini);
        } else {
            var cxI = pad + isoH / 2;
            var cyI = 3 + isoH / 2;
            var q = isoH / 2 - 1;
            var top = 3;
            var bot = 3 + isoH - 1;
            var x1 = cxI - q;
            var x2 = cxI + q;
            var edges = [
                [cxI, top, x2, top + q],
                [x2, top + q, x2, bot - q],
                [x2, bot - q, cxI, bot],
                [cxI, bot, x1, bot - q],
                [x1, bot - q, x1, top + q],
                [x1, top + q, cxI, top]
            ];
            for (var i = 0; i < edges.size(); i++) {
                var e = edges[i];
                dc.setColor((i % 2 == 0) ? Graphics.COLOR_PURPLE : Graphics.COLOR_GREEN,
                    Graphics.COLOR_TRANSPARENT);
                dc.drawLine(e[0], e[1], e[2], e[3]);
            }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cxI - 3, cyI, 2);
            dc.drawCircle(cxI + 3, cyI, 2);
        }

        // Wordmark: bitmap blanco 96x15, o texto de sistema como fallback.
        var wx = pad + isoH + 4;
        if (mWordmark != null) {
            dc.drawBitmap(wx, 3 + (isoH - wmH) / 2, mWordmark);
        } else {
            var f = Graphics.FONT_GLANCE;
            if (dc.getTextWidthInPixels("naN.builders", f) > w - pad - wx) {
                f = Graphics.FONT_XTINY;
            }
            var ty = 3 + (isoH - dc.getFontHeight(f)) / 2;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(wx, ty, f, "naN.builders", Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Hairline de 1 px en DK_GRAY (una sola línea por vista).
        var hairY = 3 + isoH + 4;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(pad, hairY, w - pad, hairY);
        return hairY + 3;
    }

    //! Edad del último fetch, "HACE 45S" / "HACE 3 MIN" / "HACE 2 H" / "HACE
    //! 5 D" (B4), en MAYÚSCULAS como el resto de etiquetas de la glance. Se
    //! lee DIRECTAMENTE de Storage con el literal "nan_fetch_epoch" (es
    //! QuotaStore.FETCH_KEY, pero el proceso de glance no debe enlazar
    //! QuotaStore, que no está anotado (:glance)). La clave se CONSERVA tras
    //! el cambio de fuente de datos: la edad del último fetch sigue
    //! funcionando igual.
    //! Epoch de PARED en segundos UNIX (Time.now().value()): sobrevive a
    //! reboots, a diferencia de System.getTimer() (ms desde boot). SIN red en
    //! la glance: sólo Storage. Devuelve null (-> se omite la edad) si no hay
    //! dato o si diff < 0 (reloj cambiado: edad desconocida, B1).
    private function fetchAgeText() as Lang.String or Null {
        var epoch = Storage.getValue("nan_fetch_epoch") as Lang.Number;
        if (epoch == null || epoch <= 0) {
            return null;
        }
        var diff = Time.now().value() - epoch;
        if (diff < 0) {
            return null;
        }
        if (diff < 60) {
            return "HACE " + diff + "S";
        }
        var mins = diff / 60;
        if (mins < 60) {
            return "HACE " + mins + " MIN";
        }
        var hours = mins / 60;
        if (hours < 24) {
            return "HACE " + hours + " H";
        }
        return "HACE " + (hours / 24) + " D";
    }

    //! Presupuesto vertical de la glance (guard de altura: contentArea 93 px
    //! en fr955, 63 px en fenix7). Necesita: fila del % + gap + [fila de edad
    //! + gap] + fila QUEDAN + margen inferior de 2 px. El % y los créditos
    //! restantes son innegociables; la marca y la edad son lo comprimible.
    private function glanceFits(h as Lang.Number, topY as Lang.Number, hN as Lang.Number,
            hTxt as Lang.Number, showAge as Lang.Boolean) as Lang.Boolean {
        var need = topY + hN + 2 + hTxt + 2;
        if (showAge) {
            need += hTxt + 2;
        }
        return need <= h - 2;
    }

    function onUpdate(dc as Graphics.Dc) {
        GlanceView.onUpdate(dc);

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var pad = 7;

        // Cabecera de marca: se decide DESPUÉS (guard de altura) y se pinta UNA
        // vez; de momento sólo se mide. La edad del último fetch (B4) se lee
        // aquí arriba, también de Storage y sin red.
        var hTxt = dc.getFontHeight(Graphics.FONT_XTINY);
        var ageTxt = fetchAgeText();

        // Instantánea de créditos en literal: el proceso de glance no debe
        // enlazar QuotaStore (esa clase no está anotada (:glance)).
        // Es el MISMO literal que QuotaStore.CREDITS_KEY == "nan_credits"
        // (formato de serializeState(): "a"/"u"/"r" Float, "f" Boolean).
        var raw = Storage.getValue("nan_credits");
        if (!(raw instanceof Lang.Dictionary)) {
            var topY0 = drawBrandHeader(dc, w, 0);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, (topY0 + h - 4) / 2, Graphics.FONT_XTINY,
                fitMsg(dc, w, h - topY0, "abre para sincronizar"),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var snap = raw as Lang.Dictionary;

        // B4: null-safety total con instanceof (el cast "as" puede lanzar).
        // Héroe: used/allowance del PERIODO de facturación, el mismo dato que
        // el héroe de la vista principal.
        var allowance = toFloat(snap.get("a"));
        var used = toFloat(snap.get("u"));
        var remaining = toFloat(snap.get("r"));
        if (allowance == null || used == null || allowance <= 0.0) {
            var topY1 = drawBrandHeader(dc, w, 0);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, (topY1 + h - 4) / 2, Graphics.FONT_XTINY,
                fitMsg(dc, w, h - topY1, "sin datos de créditos"),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var frac = used * 1.0 / allowance;
        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var pct = (frac * 100.0).toNumber();

        // --- guard de altura (contentArea 93 px fr955, 63 px fenix7): si el
        // % + edad + QUEDAN no caben, el orden de sacrificio es: marca
        // completa -> hairline -> edad -> tamaño del % (se baja a FONT_GLANCE,
        // más pequeño pero JAMÁS oculto; "QUEDAN" tampoco se oculta nunca).
        // Los topY replican lo que devuelve drawBrandHeader por nivel. ---
        var showAge = (ageTxt != null);
        var brand = 0;
        var topY = 26;                      // nivel 0: hairline (3+16+4) + 3
        var fBig = Graphics.FONT_GLANCE_NUMBER;
        var hN = dc.getFontHeight(fBig);
        if (!glanceFits(h, topY, hN, hTxt, showAge)) {
            brand = 1;                      // comprime la marca: sólo hairline
            topY = 6;
        }
        if (!glanceFits(h, topY, hN, hTxt, showAge)) {
            brand = 2;                      // oculta la marca
            topY = 5;
        }
        if (!glanceFits(h, topY, hN, hTxt, showAge) && showAge) {
            showAge = false;                // al final se omite la edad
        }
        if (!glanceFits(h, topY, hN, hTxt, showAge)) {
            fBig = Graphics.FONT_GLANCE;    // % más pequeño, nunca oculto
            hN = dc.getFontHeight(fBig);
        }

        // La cabecera se pinta UNA vez, con el nivel ya decidido.
        topY = drawBrandHeader(dc, w, brand);

        // --- % de créditos consumido: número blanco + "%" en violeta de
        // marca. Dos drawText: nunca dos colores en una misma llamada. ---
        var fPct = (fBig == Graphics.FONT_GLANCE_NUMBER) ? Graphics.FONT_GLANCE : fBig;
        var hPct = dc.getFontHeight(fPct);

        var pctNum = pct.toString();
        var pctNumW = dc.getTextWidthInPixels(pctNum, fBig);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, topY, fBig, pctNum, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad + pctNumW + 1, topY + ((hN - hPct) * 0.78).toNumber(), fPct, "%",
            Graphics.TEXT_JUSTIFY_LEFT);

        // Etiqueta "CONSUMIDO" en MAYÚSCULAS, anclada a la derecha y centrada
        // verticalmente con el centro óptico del número (~0.42 * hN).
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - pad, topY + (0.42 * hN).toNumber(), Graphics.FONT_XTINY,
            "CONSUMIDO",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- edad del último dato (B4), discreta: anclada a la derecha,
        // directamente bajo "CONSUMIDO" en LT_GRAY, en su propia fila. ---
        var yR = topY + hN + 2;
        if (showAge && ageTxt != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - pad, yR, Graphics.FONT_XTINY, ageTxt,
                Graphics.TEXT_JUSTIFY_RIGHT);
            yR += hTxt + 2;
        }

        // --- fila QUEDAN: créditos restantes del periodo ("QUEDAN 3.1K"),
        // el valor en color de severidad (la señal crítica se conserva). Si
        // el dato no viniera, "?" en LT_GRAY. ---
        var lblW = dc.getTextWidthInPixels("QUEDAN", Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, yR, Graphics.FONT_XTINY, "QUEDAN", Graphics.TEXT_JUSTIFY_LEFT);

        var valTxt = "?";
        var valColor = Graphics.COLOR_LT_GRAY;
        if (remaining != null) {
            valTxt = creditLabel(remaining);
            valColor = severityColor(frac);
        }
        dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - pad, yR, Graphics.FONT_XTINY, valTxt,
            Graphics.TEXT_JUSTIFY_RIGHT);
    }
}
