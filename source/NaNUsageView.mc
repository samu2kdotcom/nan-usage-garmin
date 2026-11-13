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
//!
//! NAVEGACIÓN (3 pantallas): SELECT refresca (manual), BACK sale y DOWN abre
//! la pantalla de desglose por modelos (NaNUsageBreakdownView, pushed con su
//! delegate); el ciclo completo es Principal -> Desglose -> Proyección ->
//! Principal (UP retrocede; detalles en el delegate del desglose). Esta
//! pantalla es la "1/3" del indicador discreto bajo el arco.
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
    // BUG subtítulo (fr955 real, foto): la degradación usaba un techo FIJO de
    // 250 px sin relación con la geometría y con margen 3 el texto tocaba el
    // cristal. Ahora el presupuesto es la CUERDA ÚTIL real (subAvailWidth()):
    // el subtítulo vive DENTRO del hueco del anillo, cuyos lados (r=112,
    // plumín 10 -> borde interior 107) cruzan la franja del texto, así que el
    // radio seguro es el del borde INTERIOR del arco menos un aire de 3 px:
    // rSafe = 112 - 5 - 3 = 104 (>= 10 px al cristal de sobra: 120 - 104 = 16).
    // Cuerda a la altura del renglón: 2*sqrt(104^2 - 25^2) ~= 201 px.
    private const SUB_MARGIN = 10;      // px de margen mínimo al borde del círculo
    private const ARC_CLEAR = 3;        // px de aire entre el texto y el arco
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
    private var mS = 1.0;      //!< factor de escala = min(w, h) / 260.0

    //! Recalcula el factor de escala desde el Dc (base de diseño 260x260).
    //! Si cambia, descarta las fuentes vectoriales cacheadas.
    private function updateScale(dc as Graphics.Dc) as Void {
        var m = dc.getWidth();
        if (dc.getHeight() < m) {
            m = dc.getHeight();
        }
        var s = m / 260.0;
        if (s != mS) {
            mS = s;
            mHeroFont = null;
            mPctFont = null;
            mWmFontA = null;
            mWmFontB = null;
        }
    }

    //! Escala un valor de diseño (px a 260x260) y redondea. Con s=1.0 es la
    //! identidad exacta.
    private function sc(v as Lang.Numeric) as Lang.Number {
        return (v * mS + 0.5).toNumber();
    }

    //! Escala con suelo mínimo de 1 px (grosores).
    private function sc1(v as Lang.Numeric) as Lang.Number {
        var r = sc(v);
        return (r < 1) ? 1 : r;
    }

    //! Dibuja un bitmap de diseño wxh escalado (drawBitmap nativo si s=1).
    private function drawBmp(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
            bw as Lang.Number, bh as Lang.Number, bmp) as Void {
        if (mS != 1.0 && (dc has :drawScaledBitmap)) {
            dc.drawScaledBitmap(x, y, sc(bw), sc(bh), bmp);
        } else {
            dc.drawBitmap(x, y, bmp);
        }
    }

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
        updateScale(dc);
    }

    // -------------------------------------------------------------------------
    // Pintado
    // -------------------------------------------------------------------------
    function onUpdate(dc as Graphics.Dc) {
        View.onUpdate(dc);
        updateScale(dc);

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
        drawScreenIndicator(dc, cx);
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
        var arcR = sc(ARC_R);
        dc.setPenWidth(sc1(ARC_PEN));

        // Pista (240 grados, hueco inferior de 120).
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, arcR, ARC_DIRECTION, ARC_START, arcEnd(ARC_SWEEP));

        // Progreso: el % de créditos consumido de la cuenta (used/allowance),
        // y el semáforo juzga ESE porcentaje.
        var sweep = ARC_SWEEP * frac;
        if (sweep >= 0.5) {
            dc.setColor(severityColor(frac), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, arcR, ARC_DIRECTION, ARC_START, arcEnd(sweep));
        }

        // Tres marcas radiales del mockup (30°, 90° y 150°) que cortan el anillo:
        // de r=104 a r=120, en negro, como separadores de los tres tramos.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(sc1(3));
        var tickIn = sc(104);
        var tickOut = sc(120);
        var tickAngles = [30, 90, 150];
        for (var i = 0; i < tickAngles.size(); i++) {
            var rad = Math.toRadians(tickAngles[i]);
            var co = Math.cos(rad);
            var si = Math.sin(rad);
            dc.drawLine(
                cx + (tickIn * co).toNumber(), cy - (tickIn * si).toNumber(),
                cx + (tickOut * co).toNumber(), cy - (tickOut * si).toNumber());
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
            drawBmp(dc, cx - sc(WM_W) / 2, sc(WM_Y), WM_W, 15, mWordmark);
        } else {
            // Fallback vectorial: "naN" en Roboto-Black + ".builders" en
            // RobotoCondensed-RegularItalic (caras verificadas en el fr955).
            var fa = wmFontA();
            var fb = wmFontB();
            var wa = dc.getTextWidthInPixels("naN", fa);
            var wb = dc.getTextWidthInPixels(".builders", fb);
            var x = cx - (wa + wb) / 2;
            var ty = sc(WM_Y) - 1;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, ty, fa, "naN", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(x + wa, ty, fb, ".builders", Graphics.TEXT_JUSTIFY_LEFT);
        }
        // Hairline de 1px en DK_GRAY: una sola línea por vista (regla de marca).
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - sc(74), sc(HAIR_Y), cx + sc(74), sc(HAIR_Y));
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

        var gap = sc(2);
        var totalW = numW + gap + pctW;
        var x = cx - totalW / 2;
        var heroBase = sc(HERO_BASE);

        // Sin acceso a la ascendente real de una fuente vectorial, la top se
        // deriva de la línea base con la misma proporción que el resto del
        // código (ascendente ~= 0.78 * altura de la fuente).
        var numTop = heroBase - (0.78 * hh).toNumber();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, numTop, hf, num, Graphics.TEXT_JUSTIFY_LEFT);

        // "%" alineado por la línea de base con el número grande.
        dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + numW + gap, heroBase - (0.78 * ph).toNumber(), pf, "%",
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! "4.0K de 7.0K créditos · hace 12s" en LT_GRAY (top y=134): créditos
    //! usados y totales del PERIODO de facturación (bloque "credits" de
    //! /v1/usage), con el helper compacto creditLabel(). Aquí vive también el
    //! aviso de error/caché vieja ("sin conexion · hace 2 h", ámbar).
    //!
    //! BUG subtítulo (fr955 real, foto): el sufijo "· +N" (modelos fuera del
    //! top 3) y "· actualizando..." se CONCATENABAN después de elegir el
    //! formato, así que la cadena final pintada no era ninguna de las medidas
    //! y el "+9" se salía del círculo. Ahora el SUFIJO se hornea en cada
    //! candidato y se mide SIEMPRE la cadena final completa antes de pintar.
    //! Presupuesto: cuerda real subAvailWidth() (radio seguro 120, margen 10).
    //! Cadena de degradación (medir cada candidato; primero FONT_XTINY y sólo
    //! se baja de fuente si FONT_TINY midiera menos, que en fr955 no ocurre):
    //!   1. "4.0K de 7.0K créditos · hace 45 min · +9"   (completo)
    //!   2. "4.0K de 7.0K · hace 45 min · +9"            (sin "créditos")
    //!   3. "4.0K/7.0K · 45 min · +9"                    (edad compacta)
    //!   4. "4.0K/7.0K · 45 min"                         (sacrifica el sufijo)
    //!   5. "4.0K/7.0K"                                  (sacrifica la edad)
    //! ORDEN DE SACRIFICIO: primero el sufijo (+N / actualizando...), luego
    //! la edad; las CIFRAS nunca se sacrifican. Si ni el 5.º cupiera (con la
    //! cuerda del fr955 es inalcanzable: "4.0K/7.0K" mide ~80 px < 235), se
    //! baja de fuente ANTES de recortar cifras y como defensa final se
    //! recorta con ".." para que JAMÁS desborde el círculo.
    private function drawSubtitle(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var uTxt = QuotaStore.creditLabel(mState.used());
        var aTxt = QuotaStore.creditLabel(mState.allowance());
        var erring = QuotaStore.getLastErr() != null;
        // B3: el aviso ámbar se decide por el último intento PERSISTIDO
        // (QuotaStore.getLastErr()), no sólo por el error en memoria de esta
        // sesión, para que sobreviva a cerrar y reabrir el widget.
        var color = erring ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY;

        // Sufijo del subtítulo (indicador de red / contador de modelos fuera
        // del top 3). Va DENTRO de cada candidato: lo que se pinta es lo que
        // se midió.
        var suffix = "";
        if (mSyncing) {
            suffix = " · actualizando...";
        } else {
            var extra = mState.models().size() - MAX_ROWS;
            if (extra > 0) {
                suffix = " · +" + extra;
            }
        }

        // Edad en sus DOS vestidos: completo (1-2) y compacto (3).
        var ageL = relativeAge();
        var ageS = ageShort();
        var f0 = uTxt + " de " + aTxt + " créditos · " + ageL + suffix;
        var f1 = uTxt + " de " + aTxt + " · " + ageL + suffix;
        var f2 = uTxt + "/" + aTxt + " · " + ageS + suffix;
        var f2s = uTxt + "/" + aTxt + " · " + ageS;      // sin sufijo
        var f3 = uTxt + "/" + aTxt;                      // sin edad
        var e0 = "sin conexion · " + ageL + suffix;
        var e0s = "sin conexion · " + ageL;              // sin sufijo
        var e1 = "sin conexion" + suffix;

        // Tramo 2 de la cadena ("reduce el tamaño de fuente antes de recortar
        // cifras" con las dos fuentes proyectadas por el lead): FONT_XTINY es
        // la más pequeña del fr955 (21 px; FONT_TINY mide 29), así que aquí
        // el array sólo tiene XTINY y el tramo es no-op; se decide MIDIENDO
        // la altura, por si el código se porta a otro dispositivo donde
        // FONT_TINY sea la menor.
        var fonts = [Graphics.FONT_XTINY];
        if (dc.getFontHeight(Graphics.FONT_TINY)
                < dc.getFontHeight(Graphics.FONT_XTINY)) {
            fonts.add(Graphics.FONT_TINY);
        }

        // El PRIMERO que quepa en la cuerda REAL, midiendo cada candidato
        // completo (por cada fuente, la cadena de degradación; el sufijo ya
        // va horneado, así que lo elegido es exactamente lo que se pinta).
        var opts = erring ? [e0, e0s, e1, "sin conexion"] : [f0, f1, f2, f2s, f3];
        var txt = null;
        var font = fonts[0];
        for (var fi = 0; fi < fonts.size() && txt == null; fi++) {
            var availF = subAvailWidth(dc, fonts[fi]);
            for (var oi = 0; oi < opts.size(); oi++) {
                if (dc.getTextWidthInPixels(opts[oi], fonts[fi]) <= availF) {
                    txt = opts[oi];
                    font = fonts[fi];
                    break;
                }
            }
        }
        if (txt == null) {
            // Defensa final (inalcanzable con la cuerda del fr955, ~235 px):
            // recorte literal con ".." — nunca desbordar, pase lo que pase.
            // Con presupuesto <= 0 (geometría degenerada) se dibuja vacío.
            font = fonts[0];
            var lastW = subAvailWidth(dc, font);
            txt = (lastW > 0)
                ? fitToWidth(dc, erring ? "sin conexion" : f3, font, lastW)
                : "";
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, sc(SUB_Y), font, txt, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Cuerda ÚTIL del círculo para el renglón del subtítulo (fr955 redondo
    //! 260x260, centro (w/2, h/2), franja [SUB_Y, SUB_Y + altura de fuente]).
    //! Dos restrictores:
    //!   1. EL CRISTAL: rSafe_cristal = w/2 - SUB_MARGIN (= 120, margen >= 10)
    //!   2. EL ARCO DE MARCA: sus lados (r = ARC_R = 112, plumín 10 -> borde
    //!      interior 107) cruzan la franja del subtítulo; el texto debe caber
    //!      ENTRE ellos: rSafe_arco = ARC_R - ARC_PEN/2 - ARC_CLEAR = 104.
    //!   rSafe = min(120, 104) = 104; dy = max(|SUB_Y-cy|, |SUB_Y+fontH-cy|)
    //!   avail = 2 * sqrt(rSafe^2 - dy^2)  = 2*sqrt(104^2 - 25^2) = 201 px
    //!
    //! Verificación aritmética con las medidas REALES del simulador fr955
    //! (getTextWidthInPixels, RobotoCondensed-Bold 21 px): "4.0K de 7.0K
    //! créditos · hace 45 min · +9" = 241 px ✗; "4.0K de 7.0K · hace 45 min
    //! · +9" = 222 px — cabría en la cuerda del CRISTAL (235) pero sus
    //! esquinas (r = sqrt(111^2 + 25^2) = 113.6) chocan con el arco (borde
    //! interior 107..117 en esa franja: solape verificado en captura). Con
    //! rSafe = 104 cae al formato corto "4.0K/7.0K · 45 min · +9" = 163 px ✓
    //! (esquinas a r=86, holgado). Nunca se sacrifican las cifras.
    private function subAvailWidth(dc as Graphics.Dc, font as Graphics.FontType) as Lang.Number {
        var cy = dc.getHeight() / 2;
        var rGlass = dc.getWidth() / 2 - sc(SUB_MARGIN);
        var rArc = sc(ARC_R) - sc1(ARC_PEN) / 2 - sc(ARC_CLEAR);
        var rSafe = (rGlass < rArc) ? rGlass : rArc;
        var dyT = sc(SUB_Y) - cy;
        if (dyT < 0) {
            dyT = -dyT;
        }
        var dyB = sc(SUB_Y) + dc.getFontHeight(font) - cy;
        if (dyB < 0) {
            dyB = -dyB;
        }
        var dy = (dyB > dyT) ? dyB : dyT;
        if (dy >= rSafe) {
            return 0;               // franja fuera del radio seguro
        }
        var w = (2.0 * Math.sqrt((rSafe * rSafe - dy * dy) * 1.0)).toNumber();
        return (w > 0) ? w : 0;
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
        var badgeH = sc(BADGE_H);
        var badgePad = sc(BADGE_PAD);
        var badgeMaxW = sc(BADGE_MAX_W);
        var y = sc(SUB_Y) + dc.getFontHeight(Graphics.FONT_XTINY) + sc(2);
        var ty = y + (badgeH - dc.getFontHeight(Graphics.FONT_XTINY)) / 2;

        if (frozen) {
            var frozenLabel = "CUENTA CONGELADA";
            if (dc.getTextWidthInPixels(frozenLabel, Graphics.FONT_XTINY) > badgeMaxW) {
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
        var wBox = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY) + 2 * badgePad;
        if (wBox > badgeMaxW && days != null) {
            label = "RESET · " + days + " D";           // 1er acorte
            wBox = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY) + 2 * badgePad;
            if (wBox > badgeMaxW) {
                label = "" + days + " D";                // 2º acorte: lo esencial
                wBox = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY) + 2 * badgePad;
            }
        }
        if (wBox > badgeMaxW) {
            wBox = badgeMaxW;     // defensa final; con 4-11 glifos no ocurre
        }

        var x = cx - wBox / 2;

        dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, wBox, badgeH);

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
        var rowHalf = sc(ROW_HALF);
        var left = cx - rowHalf;
        var right = cx + rowHalf;

        for (var i = 0; i < MAX_ROWS && i < models.size(); i++) {
            var m = models[i] as ModelCredit;
            // Modelo sin créditos o gratuito (credits <= 0): sin cifra no hay
            // fila en la vista principal (QuotaStore ya los filtra; guard
            // defensivo por si una lista llegara sin pasar por el filtro).
            if (m == null || m.credits() == null || m.credits() <= 0.0) {
                continue;
            }
            var f = m.windowFraction(mState.windowTotal());
            var creditTxt = QuotaStore.creditLabel(m.credits());

            var baseY = sc(ROW_BASE) + i * sc(ROW_PITCH);   // 192 / 209 / 226
            var topY = baseY - ascent;
            var barY = baseY + sc(5);                       // 197 / 214 / 231

            var creditW = dc.getTextWidthInPixels(creditTxt, Graphics.FONT_XTINY);
            // Etiqueta corta ÚNICA ya en MAYÚSCULAS (QuotaStore.assignLabels:
            // "glm5.3" y "glm5.3-flash" -> "GLM5.3" y "GLM5.3-F").
            var name = fitName(dc, m.label(),
                right - creditW - sc(6) - left);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, topY, Graphics.FONT_XTINY, name, Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(right, topY, Graphics.FONT_XTINY, creditTxt, Graphics.TEXT_JUSTIFY_RIGHT);

            // Barra: pista DK_GRAY + relleno violeta con la cuota del modelo
            // sobre totals.credits (misma fracción que codifica la barra).
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left, barY, 2 * rowHalf, sc1(BAR_H));
            var fillW = (2 * rowHalf * f).toNumber();
            if (fillW < 1 && f > 0.0) {
                fillW = 1;
            }
            if (fillW > 0) {
                dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(left, barY, fillW, sc1(BAR_H));
            }
        }
    }

    //! Indicador DISCRETO de pantalla "1/3" (navegación de 3 pantallas):
    //! a la derecha del isotipo mini (que ocupa cx±8), en la banda del hueco
    //! del arco. Con "1/3" de ~26 px: ink 140..166 x 238..251 -> esquina
    //! (166, 251): dx=36, dy=121 -> r=127.7 < 130 (2 px al cristal) y sin
    //! tocar la barra de la fila 3 (231..233) ni el isotipo (borde cx+8).
    private function drawScreenIndicator(dc as Graphics.Dc, cx as Lang.Number) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + sc(ISO_SIZE) / 2 + sc(2), sc(ISO_Y) - sc(2), Graphics.FONT_XTINY,
            "1/3", Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Isotipo mini (16x16) centrado en el hueco del arco, bajo la última fila:
    //! x = cx-8..cx+8 (122..138), y = 236..252 (FIX solape: re-flujo de las
    //! filas). El footer se eliminó (su aviso vive ahora en el subtítulo), así
    //! que no hay solape y todo queda dentro del círculo: la esquina
    //! (138,252) está a r=122.3 < 129 del centro.
    private function drawIsoMini(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var isoSz = sc(ISO_SIZE);
        var isoY = sc(ISO_Y);
        if (mIsoMini != null) {
            drawBmp(dc, cx - isoSz / 2, isoY, ISO_SIZE, ISO_SIZE, mIsoMini);
            return;
        }
        // Fallback con primitivas: hexágono pointy-top bicolor + infinito blanco.
        var top = isoY;
        var midY = top + isoSz / 2;
        var bot = top + isoSz - 1;
        var q = (isoSz / 2 - 1);   // semiancho de los lados verticales
        var off = sc(3);
        var cr = sc1(2);
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
        dc.drawCircle(cx - off, midY, cr);
        dc.drawCircle(cx + off, midY, cr);
    }

    //! Mayúsculas ASCII: Lang.String no tiene toUpperCase() en el SDK 9.3.0.
    //! Los nombres de modelo son ASCII, así que basta una tabla con find().
    //! (Movida a QuotaStore.upperAscii: es la ÚNICA copia y la usan las
    //! etiquetas de assignLabels.)

    //! Recorta el nombre con ".." si no cabe en maxW píxeles (FONT_XTINY).
    private function fitName(dc as Graphics.Dc, name as Lang.String, maxW as Lang.Number) as Lang.String {
        return fitToWidth(dc, name, Graphics.FONT_XTINY, maxW);
    }

    //! Recorta `txt` con ".." si no cabe en maxW píxeles con la fuente dada.
    //! Gemela de fitName pero paramétrica: la usa el recorte de DEFENSA FINAL
    //! del subtítulo (defensa para que el círculo jamás se desborde).
    private function fitToWidth(dc as Graphics.Dc, txt as Lang.String, font as Graphics.FontType, maxW as Lang.Number) as Lang.String {
        if (maxW <= 0 || dc.getTextWidthInPixels(txt, font) <= maxW) {
            return txt;
        }
        var cut = txt;
        while (cut.length() > 1
            && dc.getTextWidthInPixels(cut + "..", font) > maxW) {
            var shorter = cut.substring(0, cut.length() - 1);
            if (shorter == null) {
                break;
            }
            cut = shorter;
        }
        return cut + "..";
    }

    //! Estado vacío / error / aviso de conexión (con cabecera de marca)
    // -------------------------------------------------------------------------
    //! Cuerda ÚTIL del cristal para una franja de texto [yTop, yTop+bandH],
    //! gemela de subAvailWidth() pero SIN el restrictor del arco (el estado
    //! vacío no dibuja anillo): rSafe = w/2 - SUB_MARGIN.
    //! FIX desborde (verificación con métricas reales del fr955): mError es
    //! una cadena libre y "Respuesta inesperada" mide 237 px en FONT_SMALL ->
    //! esquinas a r=123.3, fuera del margen de diseño (120). El msg y el hint
    //! se MIDEN ahora contra la cuerda y degradan antes de dibujarse.
    private function chordAvail(dc as Graphics.Dc, yTop as Lang.Number, bandH as Lang.Number) as Lang.Number {
        var cy = dc.getHeight() / 2;
        var rSafe = dc.getWidth() / 2 - sc(SUB_MARGIN);
        var dyT = yTop - cy;
        if (dyT < 0) {
            dyT = -dyT;
        }
        var dyB = yTop + bandH - cy;
        if (dyB < 0) {
            dyB = -dyB;
        }
        var dy = (dyB > dyT) ? dyB : dyT;
        if (dy >= rSafe) {
            return 0;               // franja fuera del radio seguro
        }
        var w = (2.0 * Math.sqrt((rSafe * rSafe - dy * dy) * 1.0)).toNumber();
        return (w > 0) ? w : 0;
    }

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

        // Msg medido contra la cuerda real: primero FONT_SMALL; si no cabe,
        // FONT_XTINY; defensa final, recorte con ".." (nunca fuera del
        // círculo; "Respuesta inesperada" cae a XTINY: 156 px < 229).
        var fMsg = Graphics.FONT_SMALL;
        var hMsg = dc.getFontHeight(fMsg);
        var yMsg = cy - hMsg / 2;
        var avail = chordAvail(dc, yMsg, hMsg);
        if (dc.getTextWidthInPixels(msg, fMsg) > avail) {
            fMsg = Graphics.FONT_XTINY;
            hMsg = dc.getFontHeight(fMsg);
            yMsg = cy - hMsg / 2;
            avail = chordAvail(dc, yMsg, hMsg);
        }
        if (dc.getTextWidthInPixels(msg, fMsg) > avail) {
            msg = fitToWidth(dc, msg, fMsg, avail);
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yMsg, fMsg, msg,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Hint medido también (212 px se salaban del margen de diseño):
        // escalera "pulsa SELECT para reintentar" -> "SELECT para reintentar"
        // -> recorte con ".."; "esperando al movil" (137) siempre cabe.
        var hint = mSyncing ? "esperando al movil" : "pulsa SELECT para reintentar";
        var fHint = Graphics.FONT_XTINY;
        var yHint = cy + sc(36);
        var availH = chordAvail(dc, yHint, dc.getFontHeight(fHint));
        if (dc.getTextWidthInPixels(hint, fHint) > availH) {
            hint = "SELECT para reintentar";
        }
        if (dc.getTextWidthInPixels(hint, fHint) > availH) {
            hint = fitToWidth(dc, hint, fHint, availH);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yHint, fHint, hint,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Segundos desde el último fetch CON ÉXITO. Devuelve:
    //!   null -> nunca se ha traído nada (sin datos)
    //!   -1   -> diff < 0: el reloj cambió/reboot y la edad es desconocida (B1)
    private function ageSeconds() as Lang.Number or Null {
        var last = QuotaStore.getLastFetchEpoch();
        if (last == null || last == 0) {
            return null;
        }
        var diff = QuotaStore.nowEpoch() - last;
        if (diff < 0) {
            return -1;
        }
        return diff;
    }

    //! Edad COMPACTA para los formatos estrechos del subtítulo: "ahora"
    //! (< 5 s, en vez del "hace 0s" del bug), "12s", "3 min", "2 h", "5 d";
    //! "sin datos" y "?" para los casos B0/B1. La pareja ageShort()/la forma
    //! con "hace " de relativeAge() comparte el cálculo de ageSeconds().
    private function ageShort() as Lang.String {
        var s = ageSeconds();
        if (s == null) {
            return "sin datos";
        }
        if (s < 0) {
            return "?";
        }
        if (s < 5) {
            return "ahora";
        }
        if (s < 60) {
            return s + "s";
        }
        var mins = s / 60;
        if (mins < 60) {
            return mins + " min";
        }
        var hours = mins / 60;
        if (hours < 24) {
            return hours + " h";
        }
        return (hours / 24) + " d";
    }

    //! "ahora" / "hace 45s" / "hace 3 min" / "hace 2 h" / "hace 5 d" a partir
    //! del epoch de PARED del último fetch (B1: Time.now().value(), sobrevive
    //! a reboots; antes System.getTimer() colapsaba todo < 60 s en "hace un
    //! momento"). BUG edad "hace 0s": menos de 5 s muestra "ahora".
    function relativeAge() as Lang.String {
        var s = ageSeconds();
        if (s == null) {
            return "sin datos";
        }
        if (s < 0) {
            return "hace ?";
        }
        if (s < 5) {
            return "ahora";
        }
        if (s < 60) {
            return "hace " + s + "s";
        }
        var mins = s / 60;
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

    //! Tamaño de fuente vectorial escalado, con suelo de 10.
    private function fs(v as Lang.Number) as Lang.Number {
        var r = sc(v);
        return (r < 10) ? 10 : r;
    }

    private function heroFont() as Graphics.FontType {
        if (mHeroFont == null) {
            mHeroFont = loadFont("Roboto-Black", fs(62), Graphics.FONT_NUMBER_MEDIUM);
        }
        return mHeroFont;
    }

    private function pctFont() as Graphics.FontType {
        if (mPctFont == null) {
            mPctFont = loadFont("Roboto-Black", fs(26), Graphics.FONT_MEDIUM);
        }
        return mPctFont;
    }

    private function wmFontA() as Graphics.FontType {
        if (mWmFontA == null) {
            mWmFontA = loadFont("Roboto-Black", fs(16), Graphics.FONT_XTINY);
        }
        return mWmFontA;
    }

    private function wmFontB() as Graphics.FontType {
        if (mWmFontB == null) {
            mWmFontB = loadFont("RobotoCondensed-RegularItalic", fs(16), Graphics.FONT_XTINY);
        }
        return mWmFontB;
    }
}

//! Input: select = manual refresh, back = exit, DOWN = pantalla de desglose.
class NaNUsageDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! DOWN abre la PANTALLA 2/3 (desglose por modelos) como vista PUSHED con
    //! su PROPIO delegate (NaNUsageBreakdownDelegate): mientras el desglose
    //! está encima, recibe él la entrada (DOWN/UP pagan y pasan a la pantalla
    //! 3/3, Proyección; BACK vuelve aquí); al hacer BACK el control vuelve a
    //! esta vista sin tocar el manejo de SELECT/BACK de la principal.
    //! Mapeo de teclas del fr955 (simulator.json): down -> nextPage. UP en la
    //! principal no tiene pantalla anterior: no se overridea (no-op).
    function onNextPage() as Lang.Boolean {
        // Guard anti doble-push (pulsaciones rápidas de DOWN apilarían dos
        // desgloses): si la vista de arriba ya es el desglose, no se apila.
        var views = WatchUi.getCurrentView();
        if (views != null && views.size() > 0
                && (views[0] instanceof NaNUsageBreakdownView)) {
            return true;
        }
        WatchUi.pushView(new NaNUsageBreakdownView(), new NaNUsageBreakdownDelegate(),
            WatchUi.SLIDE_IMMEDIATE);
        return true;
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
