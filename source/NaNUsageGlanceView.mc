using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application.Storage;
using Toybox.System;
using Toybox.Time;

//! Glance "nan.builders", coherente con la vista principal.
//!
//! El Dc de una GlanceView en el fr955 está recortado al contentArea
//! 176x93 (medido en el simulador: dc.getWidth()/getHeight() devuelven
//! eso, no 260): todo se dibuja con coordenadas RELATIVAS a w/h, padding
//! de 7 px y nada a sangre. Sin red, sin BLE y sin WatchUi.Layer: solo
//! Application.Storage + dibujo, para respetar los 64 KB del proceso glance.
//!
//! Layout (2 líneas, todo MEDIDO con getTextWidthInPixels contra w; cero
//! recortes verificado en captura del simulador fr955):
//!   Línea 1: "57%" grande (héroe: número blanco FONT_GLANCE_NUMBER + "%"
//!            en COLOR_PURPLE) a la izquierda y, a la derecha y en línea
//!            de base con el héroe, el bloque "QUEDAN 3.0K": etiqueta
//!            corta "QUEDAN" (FONT_XTINY, LT_GRAY) + créditos restantes
//!            en color de severidad (FONT_GLANCE, la señal crítica se
//!            conserva). Si héroe + etiqueta + valor no caben en una
//!            línea (p. ej. "100%" o "10.0K"), el bloque derecho pasa a
//!            APILADO (etiqueta sobre valor); nunca se recorta texto.
//!   Línea 2: edad del último fetch ("HACE 12S" / "HACE 51 MIN", leída
//!            de Storage, sin red) en LT_GRAY, anclada a la derecha.
//!
//! Cabecera de marca, en este orden: isotipo mini + wordmark
//! "naN.builders", hairline DK_GRAY de 1 px. Guard de altura (orden de
//! sacrificio): marca completa -> hairline -> oculta -> etiqueta "QUEDAN"
//! -> edad -> tamaño del héroe (se baja a FONT_GLANCE, más pequeño pero
//! JAMÁS oculto). El % y los créditos restantes NUNCA se ocultan.
//! Solo fuentes de sistema (FONT_GLANCE* / FONT_XTINY): nada de vector
//! fonts en el proceso de glance.
(:glance)
class NaNUsageGlanceView extends WatchUi.GlanceView {

    private var mWordmark;   //!< BitmapResource del wordmark, o null
    private var mIsoMini;    //!< BitmapResource del isotipo mini, o null
    private var mS = 1.0;    //!< escala = min(w/176, h/93) (caja de glance fr955)

    //! Recalcula la escala desde la caja real de la glance (base 176x93).
    private function updateScale(dc as Graphics.Dc) as Void {
        var sx = dc.getWidth() / 176.0;
        var sy = dc.getHeight() / 93.0;
        mS = (sx < sy) ? sx : sy;
    }

    //! Escala un valor de diseño (px a 176x93); identidad exacta con s=1.0.
    private function sc(v as Lang.Numeric) as Lang.Number {
        return (v * mS + 0.5).toNumber();
    }

    // --- espaciados del layout (px, relativos al contentArea) ---
    private const PAD = 7;        // padding lateral dentro del contentArea
    private const GAP_HERO = 1;   // héroe <-> "%" (misma pareja que la principal)
    private const GAP_MIN = 3;    // aire mínimo héroe <-> bloque derecho
    private const GAP_LBL = 2;    // "QUEDAN" <-> valor (modo en línea)
    private const GAP_STACK = 2;  // etiqueta sobre valor (modo apilado)
    private const GAP_ROW = 2;    // línea 1 <-> línea 2 (edad)

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
        var fitted = Graphics.fitTextToArea(text, Graphics.FONT_XTINY, w - sc(16), h - sc(8), true);
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
        updateScale(dc);
    }

    //! Cabecera de marca con niveles de compresión (guard de altura B4: la
    //! marca es lo PRIMERO que se sacrifica, el % y "QUEDAN" NUNCA):
    //!   0 = completa: isotipo + wordmark + hairline
    //!   1 = comprimida: sólo la hairline de 1 px
    //!   2 = oculta
    //! Devuelve la y donde cuelga el contenido (26 / 6 / 5).
    private function drawBrandHeader(dc as Graphics.Dc, w as Lang.Number, level as Lang.Number) as Lang.Number {
        if (level == 2) {
            return sc(5);
        }
        if (level == 1) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(sc(7), sc(3), w - sc(7), sc(3));
            return sc(3) + sc(3);
        }

        var pad = sc(PAD);
        var isoH = sc(16);
        var wmH = sc(15);
        var y0 = sc(3);

        // Isotipo mini (bitmap oficial cuantizado, fallback con primitivas).
        if (mIsoMini != null) {
            dc.drawBitmap(pad, y0, mIsoMini);
        } else {
            var cxI = pad + isoH / 2;
            var cyI = y0 + isoH / 2;
            var q = isoH / 2 - 1;
            var top = y0;
            var bot = y0 + isoH - 1;
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
            var cr = sc(2);
            if (cr < 1) {
                cr = 1;
            }
            dc.drawCircle(cxI - sc(3), cyI, cr);
            dc.drawCircle(cxI + sc(3), cyI, cr);
        }

        // Wordmark: bitmap blanco 96x15, o texto de sistema como fallback.
        var wx = pad + isoH + sc(4);
        if (mWordmark != null) {
            dc.drawBitmap(wx, y0 + (isoH - wmH) / 2, mWordmark);
        } else {
            var f = Graphics.FONT_GLANCE;
            if (dc.getTextWidthInPixels("naN.builders", f) > w - pad - wx) {
                f = Graphics.FONT_XTINY;
            }
            // ty >= 1: el ink del texto nunca arranca a menos de 4 px del
            // borde superior del contentArea (con FONT_GLANCE, 24 px, el
            // centrado puro daría ty = -1 y el ink tocaría y=2).
            var ty = y0 + (isoH - dc.getFontHeight(f)) / 2;
            if (ty < 1) {
                ty = 1;
            }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(wx, ty, f, "naN.builders", Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Hairline de 1 px en DK_GRAY (una sola línea por vista).
        var hairY = y0 + isoH + sc(4);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(pad, hairY, w - pad, hairY);
        return hairY + sc(3);
    }

    //! Espejo de drawBrandHeader() para el guard de altura: la y que devolverá
    //! la cabecera por nivel, SIN pintarla (0 -> hairline (3+16+4) + 3 = 26;
    //! 1 -> 3 + 3 = 6; 2 -> 5).
    private function brandTopY(level as Lang.Number) as Lang.Number {
        return (level == 2) ? sc(5)
            : ((level == 1) ? (sc(3) + sc(3)) : (sc(3) + sc(16) + sc(4) + sc(3)));
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
    //! en fr955, 63 px en otras familias). Necesita: línea 1 (héroe + bloque
    //! derecho, alto line1H) + [gap + fila de edad] + margen inferior de 2 px.
    //! El % y los créditos restantes son innegociables; la marca, la etiqueta
    //! y la edad son lo comprimible, en ese orden.
    private function glanceFits(h as Lang.Number, topY as Lang.Number, line1H as Lang.Number,
            hTxt as Lang.Number, showAge as Lang.Boolean) as Lang.Boolean {
        var need = topY + line1H;
        if (showAge) {
            need += sc(GAP_ROW) + hTxt;
        }
        return need + sc(2) <= h;
    }

    function onUpdate(dc as Graphics.Dc) {
        GlanceView.onUpdate(dc);
        updateScale(dc);

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        // La edad del último fetch (B4) se lee aquí arriba, de Storage y sin
        // red; hTxt es la altura de FONT_XTINY (21 px en fr955).
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
            dc.drawText(w / 2, (topY0 + h - sc(4)) / 2, Graphics.FONT_XTINY,
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
            dc.drawText(w / 2, (topY1 + h - sc(4)) / 2, Graphics.FONT_XTINY,
                fitMsg(dc, w, h - topY1, "sin datos de créditos"),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var frac = used * 1.0 / allowance;
        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var pct = (frac * 100.0).toNumber();

        // --- MEDIDAS (nada se pinta sin medir): fuentes y alturas reales del
        // fr955: FONT_GLANCE_NUMBER 32, FONT_GLANCE 24, FONT_XTINY 21. ---
        var fHero = Graphics.FONT_GLANCE_NUMBER;
        var hHero = dc.getFontHeight(fHero);
        var fPct = Graphics.FONT_GLANCE;        // el "%" de marca, más pequeño
        var hPct = dc.getFontHeight(fPct);
        var num = pct.toString();
        var numW = dc.getTextWidthInPixels(num, fHero);
        var pctW = dc.getTextWidthInPixels("%", fPct);
        var gapHero = sc(GAP_HERO);
        var gapMin = sc(GAP_MIN);
        var gapLbl = sc(GAP_LBL);
        var gapStack = sc(GAP_STACK);
        var gapRow = sc(GAP_ROW);
        var pad = sc(PAD);
        var heroW = numW + gapHero + pctW;

        // Bloque derecho: valor "3.0K" en color de severidad (FONT_GLANCE) +
        // etiqueta corta "QUEDAN" (FONT_XTINY). Ambos MEDIDOS; si el valor no
        // viniera, "?" en LT_GRAY (también medido).
        var valTxt = "?";
        var valColor = Graphics.COLOR_LT_GRAY;
        if (remaining != null) {
            valTxt = creditLabel(remaining);
            valColor = severityColor(frac);
        }
        var fVal = Graphics.FONT_GLANCE;
        var hVal = dc.getFontHeight(fVal);
        var valW = dc.getTextWidthInPixels(valTxt, fVal);
        var lblW = dc.getTextWidthInPixels("QUEDAN", Graphics.FONT_XTINY);

        // Modo del bloque derecho, decidido por ANCHO (no por altura): en
        // línea si héroe + etiqueta + valor caben entre los pads con el aire
        // mínimo; si no, apilado (etiqueta sobre valor). En 176 px con "57%"
        // (42) + "QUEDAN" (62) + "3.0K" (38) caben en línea (7+42+3+62+2+38+7
        // = 161 <= 176); con "100%" o valores anchos pasa a apilado.
        var inline = (pad + heroW + gapMin + lblW + gapLbl + valW + pad <= w);

        // Alto de la línea 1 según el modo.
        var line1H = inline ? ((hHero > hVal) ? hHero : hVal)
            : (hTxt + gapStack + hVal);

        // --- guard de altura (contentArea 93 px fr955, 63 px en familias
        // menores): orden de sacrificio marca completa -> hairline -> oculta
        // -> etiqueta QUEDAN (sin ella el valor se alinea con el héroe) ->
        // edad -> tamaño del héroe (se baja a FONT_GLANCE, más pequeño pero
        // JAMÁS oculto; el valor nunca se oculta). ---
        var showAge = (ageTxt != null);
        var showLbl = true;
        var brand = 0;
        var topY = brandTopY(0);
        if (!glanceFits(h, topY, line1H, hTxt, showAge)) {
            brand = 1;                      // comprime la marca: sólo hairline
            topY = brandTopY(1);
        }
        if (!glanceFits(h, topY, line1H, hTxt, showAge)) {
            brand = 2;                      // oculta la marca
            topY = brandTopY(2);
        }
        if (!glanceFits(h, topY, line1H, hTxt, showAge)) {
            showLbl = false;                // quita la etiqueta QUEDAN
            line1H = (hHero > hVal) ? hHero : hVal;
        }
        if (!glanceFits(h, topY, line1H, hTxt, showAge) && showAge) {
            showAge = false;                // luego la edad
        }
        if (!glanceFits(h, topY, line1H, hTxt, showAge)) {
            fHero = Graphics.FONT_GLANCE;   // héroe más pequeño, nunca oculto
            hHero = dc.getFontHeight(fHero);
            fPct = fHero;
            hPct = hHero;
            numW = dc.getTextWidthInPixels(num, fHero);
            pctW = dc.getTextWidthInPixels("%", fPct);
            heroW = numW + gapHero + pctW;
            line1H = (hHero > hVal) ? hHero : hVal;
        }

        // La cabecera se pinta UNA vez, con el nivel ya decidido.
        topY = drawBrandHeader(dc, w, brand);

        // --- línea 1, héroe: número blanco + "%" en violeta de marca. Dos
        // drawText: nunca dos colores en una misma llamada. ---
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, topY, fHero, num, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad + numW + gapHero, topY + ((hHero - hPct) * 0.78).toNumber(),
            fPct, "%", Graphics.TEXT_JUSTIFY_LEFT);

        // --- línea 1, bloque derecho: "QUEDAN 3.0K" (etiqueta LT_GRAY +
        // valor en color de severidad). En línea: valor en línea de base con
        // el héroe y etiqueta a su izquierda, alineada por abajo; apilado:
        // etiqueta encima y valor debajo, ambos anclados a la derecha. ---
        var xR = w - pad;
        if (showLbl) {
            if (inline) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(xR - valW - gapLbl, topY + line1H - hTxt,
                    Graphics.FONT_XTINY, "QUEDAN", Graphics.TEXT_JUSTIFY_RIGHT);
                dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(xR, topY + line1H - hVal, fVal, valTxt,
                    Graphics.TEXT_JUSTIFY_RIGHT);
            } else {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(xR, topY, Graphics.FONT_XTINY, "QUEDAN",
                    Graphics.TEXT_JUSTIFY_RIGHT);
                dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(xR, topY + hTxt + gapStack, fVal, valTxt,
                    Graphics.TEXT_JUSTIFY_RIGHT);
            }
        } else {
            dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xR, topY + line1H - hVal, fVal, valTxt,
                Graphics.TEXT_JUSTIFY_RIGHT);
        }

        // --- línea 2: edad del último dato (B4), discreta, LT_GRAY y
        // anclada a la derecha, con GAP_ROW bajo la línea 1. ---
        if (showAge && ageTxt != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xR, topY + line1H + gapRow, Graphics.FONT_XTINY,
                ageTxt, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }
}
