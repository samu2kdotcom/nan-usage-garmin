using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Math;

// =============================================================================
// PIEL DE MARCA "nan.builders" — mapeo hex de marca -> paleta segura del fr955.
//
// El fr955 es ARGB2222 de 8 bpp: solo hay 64 colores reales. setColor() acepta
// 0xRRGGBB, pero el hardware lo CUANTIZA al color más cercano de su paleta
// (el violeta #9B6BF0 solo daría gris). Por eso se usan SIEMPRE constantes
// COLOR_* exactas en el dispositivo:
//
//   hex de marca        uso                        constante aplicada
//   -----------------   ------------------------   ------------------------
//   #0B0B0C (fondo)     fondo de la vista          Graphics.COLOR_BLACK
//   #FFFFFF (texto)     héroe, % de filas          Graphics.COLOR_WHITE
//   #C9C9CC / #9A9A9E   cuerpo y metadatos         Graphics.COLOR_LT_GRAY
//                       (colapsan: jerarquía por
//                       TAMAÑO, no por tono)
//   #FFFFFF al 16%      hairline 1px (.sechead)    Graphics.COLOR_DK_GRAY
//   #7D39EB/#9B6BF0     violeta de marca           Graphics.COLOR_PURPLE
//                       (NO cuantizar el hex solo)
//   #95DD4F (lima)      verde del isotipo          Graphics.COLOR_GREEN
//                       (decisión semántica)
//   semáforo            arco por el % de CRÉDITOS  COLOR_GREEN/COLOR_YELLOW/
//                       de la cuenta (used/        COLOR_RED
//                       allowance del periodo)
//
// El #8B5CF6 usado antes NO es color de marca y se ha eliminado. El par
// verde/violeta ES la marca (es el degradado del isotipo oficial).
//
// Decisiones del lead sobre color:
//   - El ARCO y el héroe son used/allowance del bloque "credits" de
//     /v1/usage (la cuenta va por CRÉDITOS; el /api/usage/quota antiguo con
//     topes de tokens no representaba el consumo real).
//   - Las BARRAS de las filas son COLOR_PURPLE (marca) con la cifra SIEMPRE
//     en COLOR_WHITE (el número es la información; el color, el atajo). El
//     relleno de cada fila es el crédito del modelo sobre totals.credits
//     (ventana de 30 días), no sobre el allowance del periodo.
//   - La glance conserva el color de severidad en "QUEDAN".
// =============================================================================

//! Main widget screen: layout "Órbita" piel nan.builders (260x260, centro 130,130).
//!
//! Geometría conservada del diseño aprobado: arco de progreso 240° (r=112,
//! grosor 10, hueco de 120° abajo) con pista DK_GRAY y semáforo por el % de
//! créditos consumidos de la cuenta (used/allowance del bloque "credits").
//! La piel cambia: wordmark de marca + hairline, héroe Roboto-Black con "%" en
//! violeta, badge "btn-primary" relleno de violeta, filas con nombre en gris y
//! barra violeta, e isotipo mini en el hueco del arco.
//!
//! FUENTE DE DATOS (cambio): GET /v1/usage?limit=1 de api.nan.builders con la
//! MISMA key sk-. El héroe es used/allowance de la ventana de créditos del
//! periodo; el subtítulo muestra "3.9K de 7.0K créditos · hace 12s"; las
//! filas son el top 3 por créditos de la ventana de 30 días (totals.by_model,
//! cada fila muestra su crédito y la barra es su % sobre totals.credits, que
//! cubre la ventana y NO el periodo: no suman el héroe). El badge cuenta los
//! días hasta period_end (o avisa "CUENTA CONGELADA").
class NaNUsageView extends WatchUi.View {

    // --- geometría del arco (mockup SVG, sin cambios) ---
    private const ARC_R = 112;          // radio del anillo
    private const ARC_PEN = 10;         // grosor del anillo
    private const ARC_START = 210;      // extremo inferior-izquierdo (33,186)
    private const ARC_SWEEP = 240;      // barrido total; hueco de 120 abajo

    // --- geometría de la piel (mockup aprobado) ---
    private const WM_W = 96;            // ancho del wordmark (x 82..178)
    private const WM_Y = 40;            // top del wordmark (centrado en y~48)
    private const HAIR_Y = 60;          // hairline 1px bajo el wordmark
    private const HERO_BASE = 133;      // línea base del héroe (glifos hasta aquí)
    private const SUB_Y = 134;          // top del subtítulo
    // BUG 2: el ancho del badge ya NO es fijo (la constante 82 basada en el
    // mockup hacía que "RESET EN 20 D" en FONT_XTINY del fr955 desbordara la
    // caja por la derecha). Se mide el texto y ancho = texto + 2*BADGE_PAD,
    // centrado en cx; si ni abreviado cupiera en el área segura, se recorta.
    private const BADGE_PAD = 6;        // px de aire por lado, estilo btn-primary
    private const BADGE_H = 17;         // badge .btn-primary (89, y, w, 17)
    private const BADGE_MAX_W = 240;    // techo del área segura del círculo
                                        // 260x260 en la fila del badge: la caja
                                        // baja hasta y=badgeY+BADGE_H=174 (dy=44
                                        // desde el centro 130), donde la cuerda
                                        // mide 2*sqrt(130^2-44^2) ~= 244 px; con
                                        // 240 las esquinas quedan a r ~= 127.8
                                        // < 130, dentro del círculo
    // FIX solape (foto fr955 260x260): FONT_XTINY mide 21 px en el fr955
    // (height 21 / ascent 17, simulator.json), así que el subtítulo dibujado
    // en SUB_Y=134 ocupa hasta y=155 y un badge fijo en y=146 le pisaba la
    // mitad inferior. El badge ahora se ancla MEDIANTE getFontHeight() en
    // drawBadge(): badgeY = SUB_Y + hXTINY + 2 -> 157..174 (margen real de
    // 2 px bajo el subtítulo). Las filas y el isotipo se re-flujan abajo.
    private const ROW_BASE = 192;       // top del texto fila 1: 192 - 16 = 176,
                                        // 2 px bajo el badge (fin 174). Antes 174.
    private const ROW_PITCH = 17;       // 192 / 209 / 226
    private const ROW_HALF = 66;        // filas de x=cx-66 a x=cx+66 (64..196)
    private const BAR_H = 3;            // barra de consumo (alto 3)
    private const ISO_SIZE = 16;        // isotipo mini 16x16
    private const ISO_Y = 236;          // 2 px bajo la barra de la fila 3
                                        // (231..234); antes 224. Esquina inferior
                                        // (138,252): r=122.3 < 129 del centro.
    private const MAX_ROWS = 3;

    // Política de refresco (batería primero): CERO red en background (sin
    // Timer ni Temporal Events). El fetch ocurre SOLO al abrir la vista o con
    // SELECT; REFRESH_MS desaparece porque ya no hay refresco por tiempo.
    private const ANTI_BOUNCE_MS = 30000;   // no re-fetch automático antes de 30 s
    private const SYNC_TIMEOUT_MS = 20000;  // suelo mínimo entre intentos (en vuelo)

    //! Sentido de dibujo del anillo. Si el firmware interpretara las etiquetas
    //! al revés, basta con cambiar esta constante: arcEnd() y las dos llamadas
    //! a drawArc se adaptan solas.
    private const ARC_DIRECTION = Graphics.ARC_CLOCKWISE;

    private var mState;        //!< CreditState (instantánea de créditos) or null
    private var mError;        //!< String or null
    private var mSyncing;      //!< true while a request is in flight
    private var mSyncStartMs;  //!< System.getTimer() when the last sync started
    private var mHeroFont;     //!< font for the hero number (VectorFont or resource)
    private var mPctFont;      //!< font for the "%" after the hero number
    private var mWmFontA;      //!< fallback vectorial del wordmark: "naN"
    private var mWmFontB;      //!< fallback vectorial del wordmark: ".builders"
    private var mWordmark;     //!< BitmapResource del wordmark oficial, o null
    private var mIsoMini;      //!< BitmapResource del isotipo mini, o null

    function initialize() {
        View.initialize();
        mState = QuotaStore.getCachedState();
        // B3: el resultado del último intento PERSISTE en Storage; restaurarlo
        // mantiene el subtítulo ámbar ("sin conexion · hace X") al reabrir.
        mError = QuotaStore.getLastErr();
        mSyncing = false;
        mSyncStartMs = 0;
        mHeroFont = null;
        mPctFont = null;
        mWmFontA = null;
        mWmFontB = null;
        // Assets de marca declarados en resources/drawables/drawables.xml.
        try {
            mWordmark = WatchUi.loadResource(Rez.Drawables.Wordmark);
        } catch (e) {
            mWordmark = null;
        }
        try {
            mIsoMini = WatchUi.loadResource(Rez.Drawables.IsotipoMini);
        } catch (e) {
            mIsoMini = null;
        }
    }

    function onShow() {
        // Política de refresco (batería primero): fetch SIEMPRE al abrir,
        // salvo anti-rebote de ANTI_BOUNCE_MS desde el último INTENTO (éxito o
        // fallo -> backoff de 30 s tras un fallo). SYNC_TIMEOUT_MS se conserva
        // como suelo mínimo entre intentos mientras una petición sigue en
        // vuelo (guard anti-doble-disparo de sync()). B1: edades en epoch de
        // PARED; diff < 0 significa que el reloj cambió -> edad desconocida ->
        // refrescar. Cero red en background: esto sólo corre al abrir la
        // vista; SELECT fuerza el refresco bypassando el anti-rebote.
        var now = QuotaStore.nowEpoch();
        var lastFetch = QuotaStore.getLastFetchEpoch();
        var lastAttempt = QuotaStore.getLastAttemptEpoch();
        var diff = now - lastFetch;
        if (mState == null || lastFetch == 0 || diff < 0 || now - lastAttempt > ANTI_BOUNCE_MS) {
            sync();
        }
    }

    //! Kicks off a network refresh; results come back into onSyncDone().
    //! onShow() llega aquí tras el anti-rebote; SELECT llega vía forceSync()
    //! (bypass del anti-rebote) y sólo respeta el guard de SYNC_TIMEOUT_MS.
    function sync() {
        var now = System.getTimer();
        if (mSyncing) {
            // Una petición vieja (callback perdido) no debe bloquear el widget.
            if (now - mSyncStartMs < SYNC_TIMEOUT_MS) {
                return;
            }
        }
        mSyncing = true;
        mSyncStartMs = now;
        mError = null;
        WatchUi.requestUpdate();
        QuotaStore.refresh(method(:onSyncDone));
    }

    //! Refresco MANUAL (SELECT): fuerza el fetch bypassando el anti-rebote de
    //! onShow() (política punto 4). Sólo respeta el suelo mínimo de
    //! SYNC_TIMEOUT_MS mientras una petición sigue en vuelo.
    function forceSync() {
        sync();
    }

    function onSyncDone(state as CreditState or Null, err as Lang.String or Null) as Void {
        mSyncing = false;
        mSyncStartMs = 0;
        if (err != null) {
            // La caché anterior se conserva: el aviso se pinta en el subtítulo.
            mError = err;
        } else {
            mState = state;
            mError = null;
        }
        WatchUi.requestUpdate();
    }

    function onLayout(dc as Graphics.Dc) {
        View.onLayout(dc);
    }

    // -------------------------------------------------------------------------
    // Pintado
    // -------------------------------------------------------------------------
    function onUpdate(dc as Graphics.Dc) {
        View.onUpdate(dc);

        // Anti-aliasing defensivo (fr955 lo soporta, @since 3.2.0).
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        // B5: fijar color ANTES de clear para garantizar el fondo negro.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        // Sin caché: estado vacío / error / sincronizando, centrado de verdad.
        if (mState == null) {
            drawEmptyState(dc, cx, cy);
            return;
        }

        // Héroe, arco y semáforo: créditos usados / allowance del periodo.
        var frac = mState.usedFraction();

        drawRing(dc, cx, cy, frac);
        drawHeader(dc, cx);
        drawHero(dc, cx, frac);
        drawSubtitle(dc, cx);
        drawBadge(dc, cx,
            QuotaStore.daysUntilReset(mState.periodDay()),
            mState.frozen() == true);
        drawRows(dc, cx);
        drawIsoMini(dc, cx);
    }

    //! Semáforo por severidad: verde < 50 %, ámbar 50-80 %, rojo > 80 %.
    //! Solo para el ARCO (función). Las filas van en violeta de marca.
    private function severityColor(frac as Lang.Float) as Graphics.ColorType {
        if (frac > 0.8) {
            return Graphics.COLOR_RED;
        }
        if (frac >= 0.5) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_GREEN;
    }

    // -------------------------------------------------------------------------
    // Anillo (geometría y semáforo sin cambios; es función, no piel)
    // -------------------------------------------------------------------------

    //! Pista + progreso del % de créditos consumido de la cuenta
    //! (used/allowance; geometría intacta).
    //!
    //! Convención de Graphics.Dc.drawArc(x, y, r, dir, degreeStart, degreeEnd):
    //!   0° = 3 en punto, 90° = 12, 180° = 9, 270° = 6.
    //!   Los grados CRECEN en sentido antihorario en pantalla, por lo que
    //!   ARC_CLOCKWISE recorre los grados DECRECIENDO desde degreeStart hasta
    //!   degreeEnd.
    //! Comprobación con el mockup: 210° -> (130 + 112*cos210, 130 - 112*sin210)
    //! = (33, 186) y 330° -> (227, 186). El arco de 240° que pasa por arriba va
    //! de 210° a 330° en sentido horario.
    //! Progreso: degreeEnd = ARC_START - ARC_SWEEP * used/allowance de la
    //! cuenta, normalizado
    //! a [0,360). Con 45 % -> 210 - 108 = 102°, el extremo (106.7, 20.5) del
    //! mockup. Si el barrido es casi nulo se omite: drawArc con
    //! degreeStart == degreeEnd dibuja un círculo completo.
    private function drawRing(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number, frac as Lang.Float) as Void {
        dc.setPenWidth(ARC_PEN);

        // Pista (240 grados, hueco inferior de 120).
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, ARC_R, ARC_DIRECTION, ARC_START, arcEnd(ARC_SWEEP));

        // Progreso: el % de créditos consumido de la cuenta (used/allowance),
        // y el semáforo juzga ESE porcentaje.
        var sweep = ARC_SWEEP * frac;
        if (sweep >= 0.5) {
            dc.setColor(severityColor(frac), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, ARC_R, ARC_DIRECTION, ARC_START, arcEnd(sweep));
        }

        // Tres marcas radiales del mockup (30°, 90° y 150°) que cortan el anillo:
        // de r=104 a r=120, en negro, como separadores de los tres tramos.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        var tickAngles = [30, 90, 150];
        for (var i = 0; i < tickAngles.size(); i++) {
            var rad = Math.toRadians(tickAngles[i]);
            var co = Math.cos(rad);
            var si = Math.sin(rad);
            dc.drawLine(
                cx + (104 * co).toNumber(), cy - (104 * si).toNumber(),
                cx + (120 * co).toNumber(), cy - (120 * si).toNumber());
        }

        dc.setPenWidth(1);
    }

    //! Ángulo final para un barrido de `sweep` grados desde ARC_START en el
    //! sentido ARC_DIRECTION. Con ARC_CLOCKWISE los grados decrecen, así que
    //! degreeEnd = ARC_START - sweep (normalizado a [0,360)); es la fórmula que
    //! hace que, con 45 % (108°), el extremo caiga en 102° = (106.7, 20.5).
    //! El módulo de Monkey C solo admite enteros, de ahí el truncado previo.
    private function arcEnd(sweep as Lang.Numeric) as Lang.Number {
        var deg = (sweep * 1.0).toNumber();
        if (deg < 1) {
            deg = 1;      // evita degreeStart == degreeEnd (dibujaría un círculo)
        }
        if (deg > 359) {
            deg = 359;
        }
        var e;
        if (ARC_DIRECTION == Graphics.ARC_CLOCKWISE) {
            e = ARC_START - deg;
        } else {
            e = ARC_START + deg;
        }
        e = e % 360;
        if (e < 0) {
            e += 360;
        }
        return e;
    }

    // -------------------------------------------------------------------------
    // Cabecera de marca: wordmark + hairline (patrón .sechead de la web)
    // -------------------------------------------------------------------------
    private function drawHeader(dc as Graphics.Dc, cx as Lang.Number) as Void {
        if (mWordmark != null) {
            // Wordmark oficial rasterizado (96x15, blanco sobre negro).
            dc.drawBitmap(cx - WM_W / 2, WM_Y, mWordmark);
        } else {
            // Fallback vectorial: "naN" en Roboto-Black + ".builders" en
            // RobotoCondensed-RegularItalic (caras verificadas en el fr955).
            var fa = wmFontA();
            var fb = wmFontB();
            var wa = dc.getTextWidthInPixels("naN", fa);
            var wb = dc.getTextWidthInPixels(".builders", fb);
            var x = cx - (wa + wb) / 2;
            var ty = WM_Y - 1;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, ty, fa, "naN", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(x + wa, ty, fb, ".builders", Graphics.TEXT_JUSTIFY_LEFT);
        }
        // Hairline de 1px en DK_GRAY: una sola línea por vista (regla de marca).
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 74, HAIR_Y, cx + 74, HAIR_Y);
    }

    //! Héroe: "45" en Roboto-Black 62 blanco + "%" en un SEGUNDO drawText de
    //! 26 px en COLOR_PURPLE (nunca dos colores en una misma llamada).
    //! La base de los glifos queda en HERO_BASE (133), justo sobre el subtítulo.
    private function drawHero(dc as Graphics.Dc, cx as Lang.Number, frac as Lang.Float) as Void {
        var pct = (frac * 100.0).toNumber();
        var num = pct.toString();

        var hf = heroFont();
        var pf = pctFont();
        var hh = dc.getFontHeight(hf);
        var ph = dc.getFontHeight(pf);
        var numW = dc.getTextWidthInPixels(num, hf);
        var pctW = dc.getTextWidthInPixels("%", pf);

        var gap = 2;
        var totalW = numW + gap + pctW;
        var x = cx - totalW / 2;

        // Sin acceso a la ascendente real de una fuente vectorial, la top se
        // deriva de la línea base con la misma proporción que el resto del
        // código (ascendente ~= 0.78 * altura de la fuente).
        var numTop = HERO_BASE - (0.78 * hh).toNumber();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, numTop, hf, num, Graphics.TEXT_JUSTIFY_LEFT);

        // "%" alineado por la línea de base con el número grande.
        dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + numW + gap, HERO_BASE - (0.78 * ph).toNumber(), pf, "%",
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! "3.9K de 7.0K créditos · hace 12s" en LT_GRAY (top y=134): créditos
    //! usados y totales del PERIODO de facturación (bloque "credits" de
    //! /v1/usage), con el helper compacto creditLabel(). Aquí vive también el
    //! aviso de error/caché vieja ("sin conexion · hace 2 h", ámbar).
    //! Degradación con presupuesto de 250 px (medido en FONT_XTINY): se quita
    //! primero la palabra "créditos" y AL FINAL la edad; las cifras de
    //! créditos NUNCA se quitan.
    private function drawSubtitle(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var uTxt = QuotaStore.creditLabel(mState.used());
        var aTxt = QuotaStore.creditLabel(mState.allowance());
        var txt;
        var color = Graphics.COLOR_LT_GRAY;
        // B3: el aviso ámbar se decide por el último intento PERSISTIDO
        // (QuotaStore.getLastErr()), no sólo por el error en memoria de esta
        // sesión, para que sobreviva a cerrar y reabrir el widget.
        if (QuotaStore.getLastErr() != null) {
            txt = "sin conexion · " + relativeAge();
            color = Graphics.COLOR_YELLOW;
        } else {
            txt = uTxt + " de " + aTxt + " créditos · " + relativeAge();
            if (dc.getTextWidthInPixels(txt, Graphics.FONT_XTINY) > 250) {
                txt = uTxt + " de " + aTxt + " · " + relativeAge();
                if (dc.getTextWidthInPixels(txt, Graphics.FONT_XTINY) > 250) {
                    txt = uTxt + " de " + aTxt;   // al final: se quita la edad
                }
            }
        }

        // El indicador de red es un sufijo sutil en el propio subtítulo,
        // nunca una pantalla de espera. Si con el sufijo no cabe, se recorta
        // al dato esencial; las cifras de créditos se conservan.
        if (mSyncing) {
            var withSync = txt + " · actualizando...";
            if (dc.getTextWidthInPixels(withSync, Graphics.FONT_XTINY) <= 250) {
                txt = withSync;
            } else {
                txt = uTxt + " · " + relativeAge() + " · actualizando...";
            }
        } else {
            var extra = mState.models().size() - MAX_ROWS;
            if (extra > 0) {
                var candidate = txt + " · +" + extra;
                if (dc.getTextWidthInPixels(candidate, Graphics.FONT_XTINY) <= 168) {
                    txt = candidate;
                }
            }
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, SUB_Y, Graphics.FONT_XTINY, txt, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Badge tipo .btn-primary: rectángulo RELLENO de violeta, esquinas rectas
    //! (la marca tiene radio 0; prohibido fillRoundedRectangle), texto blanco
    //! en MAYÚSCULAS. Cuenta los días hasta period_end del bloque "credits"
    //! (p.ej. "RESET EN 21 D"); negativo se clampea a 0; null = SIN PERIODO.
    //! Si la cuenta viene congelada (frozen: true) el badge se sustituye por
    //! un aviso DISCRETO de texto ámbar sin caja: "CUENTA CONGELADA"
    //! (abreviado a "CONGELADA" si no cupiera en el área segura).
    //!
    //! BUG 2: la caja se dimensiona por MEDICIÓN con getTextWidthInPixels()
    //! (ancho = texto + 2*BADGE_PAD, centrada en cx); antes era una constante
    //! fija de 82 px y "RESET EN 20 D" la desbordaba. Si el texto no cupiera
    //! en el área segura del círculo se ABREVA en dos pasos ("RESET · 20 D"
    //! -> "20 D") en lugar de desbordar; la Y anclada a la fuente no cambia.
    private function drawBadge(dc as Graphics.Dc, cx as Lang.Number, days, frozen as Lang.Boolean) as Void {
        // Anclaje vertical común (FIX solape): margen real bajo el subtítulo,
        // midiendo la fuente en lugar de una Y fija (FONT_XTINY = 21 px en
        // fr955 -> subtítulo 134..155, badge en 157..174).
        var y = SUB_Y + dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        var ty = y + (BADGE_H - dc.getFontHeight(Graphics.FONT_XTINY)) / 2;

        if (frozen) {
            var frozenLabel = "CUENTA CONGELADA";
            if (dc.getTextWidthInPixels(frozenLabel, Graphics.FONT_XTINY) > BADGE_MAX_W) {
                frozenLabel = "CONGELADA";
            }
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, ty, Graphics.FONT_XTINY, frozenLabel,
                Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var label;
        if (days == null) {
            label = "SIN PERIODO";
        } else {
            if (days < 0) {
                days = 0;   // fecha pasada -> se muestra 0, nunca "-3 D"
            }
            label = "RESET EN " + days + " D";
        }

        // BUG 2: ancho medido, no constante. El texto manda sobre la caja;
        // el techo BADGE_MAX_W es el del círculo 260x260 (cuerda ~244 px en la
        // y más baja del badge, ver la constante) y si lo excede se abrevia.
        var wBox = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY) + 2 * BADGE_PAD;
        if (wBox > BADGE_MAX_W && days != null) {
            label = "RESET · " + days + " D";           // 1er acorte
            wBox = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY) + 2 * BADGE_PAD;
            if (wBox > BADGE_MAX_W) {
                label = "" + days + " D";                // 2º acorte: lo esencial
                wBox = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY) + 2 * BADGE_PAD;
            }
        }
        if (wBox > BADGE_MAX_W) {
            wBox = BADGE_MAX_W;     // defensa final; con 4-11 glifos no ocurre
        }

        var x = cx - wBox / 2;

        dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, wBox, BADGE_H);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ty, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------------------
    // Filas secundarias: top 3 modelos por CRÉDITOS de la ventana de 30 días
    // (totals.by_model, ya ordenado desc por QuotaStore). Cada fila muestra el
    // crédito consumido (WHITE, formato compacto) y la BARRA es su cuota
    // sobre totals.credits — sobre la ventana, no sobre el allowance del
    // periodo: no debe parecer que las filas suman el héroe.
    // Piel de marca: nombre en LT_GRAY MAYÚSCULAS, cifra en blanco y barra
    // en COLOR_PURPLE (nada de semáforo ni arcoíris en las filas).
    // -------------------------------------------------------------------------
    private function drawRows(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var models = mState.models();
        var ascent = (0.78 * dc.getFontHeight(Graphics.FONT_XTINY)).toNumber();
        var left = cx - ROW_HALF;
        var right = cx + ROW_HALF;

        for (var i = 0; i < MAX_ROWS && i < models.size(); i++) {
            var m = models[i] as ModelCredit;
            if (m == null) {
                continue;
            }
            var f = m.windowFraction(mState.windowTotal());
            var creditTxt = QuotaStore.creditLabel(m.credits());

            var baseY = ROW_BASE + i * ROW_PITCH;   // 192 / 209 / 226
            var topY = baseY - ascent;
            var barY = baseY + 5;                   // 197 / 214 / 231

            var creditW = dc.getTextWidthInPixels(creditTxt, Graphics.FONT_XTINY);
            var name = fitName(dc, upperAscii(m.shortName()),
                right - creditW - 6 - left);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, topY, Graphics.FONT_XTINY, name, Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(right, topY, Graphics.FONT_XTINY, creditTxt, Graphics.TEXT_JUSTIFY_RIGHT);

            // Barra: pista DK_GRAY + relleno violeta con la cuota del modelo
            // sobre totals.credits (misma fracción que codifica la barra).
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left, barY, 2 * ROW_HALF, BAR_H);
            var fillW = (2 * ROW_HALF * f).toNumber();
            if (fillW < 1 && f > 0.0) {
                fillW = 1;
            }
            if (fillW > 0) {
                dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(left, barY, fillW, BAR_H);
            }
        }
    }

    //! Isotipo mini (16x16) centrado en el hueco del arco, bajo la última fila:
    //! x = cx-8..cx+8 (122..138), y = 236..252 (FIX solape: re-flujo de las
    //! filas). El footer se eliminó (su aviso vive ahora en el subtítulo), así
    //! que no hay solape y todo queda dentro del círculo: la esquina
    //! (138,252) está a r=122.3 < 129 del centro.
    private function drawIsoMini(dc as Graphics.Dc, cx as Lang.Number) as Void {
        if (mIsoMini != null) {
            dc.drawBitmap(cx - ISO_SIZE / 2, ISO_Y, mIsoMini);
            return;
        }
        // Fallback con primitivas: hexágono pointy-top bicolor + infinito blanco.
        var top = ISO_Y;
        var midY = top + ISO_SIZE / 2;
        var bot = top + ISO_SIZE - 1;
        var q = (ISO_SIZE / 2 - 1);   // semiancho de los lados verticales
        var x1 = cx - q;
        var x2 = cx + q;
        var edges = [
            [cx, top, x2, top + q],        // superior-derecha
            [x2, top + q, x2, bot - q],    // derecha
            [x2, bot - q, cx, bot],        // inferior-derecha
            [cx, bot, x1, bot - q],        // inferior-izquierda
            [x1, bot - q, x1, top + q],    // izquierda
            [x1, top + q, cx, top]         // superior-izquierda
        ];
        for (var i = 0; i < edges.size(); i++) {
            var e = edges[i];
            // 3 aristas verdes (0,2,4) + 3 violetas (1,3,5), como el isotipo.
            dc.setColor((i % 2 == 0) ? Graphics.COLOR_PURPLE : Graphics.COLOR_GREEN,
                Graphics.COLOR_TRANSPARENT);
            dc.drawLine(e[0], e[1], e[2], e[3]);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx - 3, midY, 2);
        dc.drawCircle(cx + 3, midY, 2);
    }

    //! Mayúsculas ASCII: Lang.String no tiene toUpperCase() en el SDK 9.3.0.
    //! Los nombres de modelo son ASCII, así que basta una tabla con find().
    private function upperAscii(s as Lang.String) as Lang.String {
        if (s == null) {
            return s;
        }
        var lower = "abcdefghijklmnopqrstuvwxyz";
        var upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        var out = "";
        for (var i = 0; i < s.length(); i++) {
            var ch = s.substring(i, i + 1);
            if (ch == null) {
                break;
            }
            var idx = lower.find(ch);
            out += (idx == null || idx < 0) ? ch : upper.substring(idx, idx + 1);
        }
        return out;
    }

    //! Recorta el nombre con ".." si no cabe en maxW píxeles.
    private function fitName(dc as Graphics.Dc, name as Lang.String, maxW as Lang.Number) as Lang.String {
        if (maxW <= 0 || dc.getTextWidthInPixels(name, Graphics.FONT_XTINY) <= maxW) {
            return name;
        }
        var cut = name;
        while (cut.length() > 1
            && dc.getTextWidthInPixels(cut + "..", Graphics.FONT_XTINY) > maxW) {
            var shorter = cut.substring(0, cut.length() - 1);
            if (shorter == null) {
                break;
            }
            cut = shorter;
        }
        return cut + "..";
    }

    // -------------------------------------------------------------------------
    // Estado vacío / error / aviso de conexión (con cabecera de marca)
    // -------------------------------------------------------------------------
    private function drawEmptyState(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number) as Void {
        drawHeader(dc, cx);

        var msg;
        var color = Graphics.COLOR_LT_GRAY;
        if (mError != null) {
            msg = mError;
            color = Graphics.COLOR_YELLOW;
        } else {
            msg = mSyncing ? "Sincronizando..." : "Sin datos";
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_SMALL, msg,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var hint = mSyncing ? "esperando al movil" : "pulsa SELECT para reintentar";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 36, Graphics.FONT_XTINY, hint,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! "hace 45s" / "hace 3 min" / "hace 2 h" / "hace 5 d" a partir del epoch
    //! de PARED del último fetch (B1: Time.now().value(), sobrevive a reboots;
    //! antes System.getTimer() colapsaba todo < 60 s en "hace un momento").
    function relativeAge() as Lang.String {
        var last = QuotaStore.getLastFetchEpoch();
        if (last == null || last == 0) {
            return "sin datos";
        }
        var diff = QuotaStore.nowEpoch() - last;
        if (diff < 0) {
            return "hace ?";   // reloj cambiado/reboot: edad desconocida (B1)
        }
        if (diff < 60) {
            return "hace " + diff + "s";
        }
        var mins = diff / 60;
        if (mins < 60) {
            return "hace " + mins + " min";
        }
        var hours = mins / 60;
        if (hours < 24) {
            return "hace " + hours + " h";
        }
        return "hace " + (hours / 24) + " d";
    }

    // -------------------------------------------------------------------------
    // Fuentes
    // -------------------------------------------------------------------------

    //! Fuente vectorial con fallback a la fuente de sistema indicada.
    //! Caras verificadas en el Device Reference del fr955: "Roboto-Black" y
    //! "RobotoCondensed-RegularItalic" (NUNCA ":Roboto_Black" con guion bajo).
    private function loadFont(face as Lang.String, size as Lang.Number, fallback as Graphics.FontType) as Graphics.FontType {
        try {
            var f = Graphics.getVectorFont({ :face => face, :size => size });
            if (f != null) {
                return f;
            }
        } catch (e) {
            // Sin memoria gráfica para la fuente: usamos la del sistema.
        }
        return fallback;
    }

    private function heroFont() as Graphics.FontType {
        if (mHeroFont == null) {
            mHeroFont = loadFont("Roboto-Black", 62, Graphics.FONT_NUMBER_MEDIUM);
        }
        return mHeroFont;
    }

    private function pctFont() as Graphics.FontType {
        if (mPctFont == null) {
            mPctFont = loadFont("Roboto-Black", 26, Graphics.FONT_MEDIUM);
        }
        return mPctFont;
    }

    private function wmFontA() as Graphics.FontType {
        if (mWmFontA == null) {
            mWmFontA = loadFont("Roboto-Black", 16, Graphics.FONT_XTINY);
        }
        return mWmFontA;
    }

    private function wmFontB() as Graphics.FontType {
        if (mWmFontB == null) {
            mWmFontB = loadFont("RobotoCondensed-RegularItalic", 16, Graphics.FONT_XTINY);
        }
        return mWmFontB;
    }
}

//! Input: select = manual refresh, back = exit.
class NaNUsageDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        // CRASH B (fix): WatchUi.getCurrentView() devuelve un array de DOS
        // elementos [View, InputDelegate] (doc API 9.3.0), NO la vista. El
        // cast "as NaNUsageView" sobre un objeto no se comprueba en runtime
        // en Monkey C, así que appView seguía siendo el Array y
        // appView.forceSync() moría con "Symbol Not Found: forceSync" en cada
        // pulsación de START. La vista correcta es el elemento [0].
        var views = WatchUi.getCurrentView();
        if (views != null && views.size() > 0) {
            var appView = views[0] as NaNUsageView;
            if (appView != null) {
                // Política punto 4: SELECT fuerza el refresco SIEMPRE,
                // bypassando el anti-rebote de onShow() (que sólo mira
                // lastAttempt/lastFetch); sync() sólo retiene la llamada
                // mientras la petición anterior siga EN VUELO (< 20 s), de
                // modo que no puede haber dos peticiones simultáneas.
                appView.forceSync();
            }
        }
        return true;
    }
}
