using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;

// =============================================================================
// PANTALLAS SECUNDARIAS (2/5 .. 5/5) — nan.builders, fr955 260x260 redondo.
//
// Se PUSH desde la vista principal con DOWN (NaNUsageDelegate.onNextPage() ->
// pushView) y trae SU PROPIO delegate, de modo que la vista principal conserva
// intactos su SELECT (refresco) y su BACK (salir). Es UNA vista con CUATRO
// pantallas internas (mScreen): apilarlas como views separadas obligaría a
// varios popView para cerrar el ciclo, que WatchUi no garantiza atómico.
//
// NAVEGACIÓN (5 pantallas, ciclo):
//   Principal --DOWN--> Desglose (pagina) --> 24 H --> 7 D --> Actividad
//   Actividad --DOWN--> Principal (popView). UP recorre al revés; en la
//   página 1 del desglose UP vuelve a la principal. BACK siempre vuelve a
//   la principal.
//   START (SELECT) alterna la UNIDAD en desglose y proyecciones: créditos
//   (cifras blancas, "cr") <-> tokens (cifras azules, "tok"). Se recuerda
//   en Storage (QuotaStore.showTokens/toggleUnit).
//
// DESGLOSE (2/5): "DESGLOSE · 30 D" + total ("4.0K de 7.0K créditos" del
// PERIODO o "5.2B tokens" de la ventana) y la lista de modelos con consumo
// de totals.by_model (caché de QuotaStore; los gratuitos no se listan).
// Cada fila: etiqueta única compacta, cifra en la unidad activa y barra
// fina violeta con la cuota del modelo en la ventana (créditos o tokens).
//
// PROYECCIÓN 24 H (3/5) y 7 D (4/5): ritmo de la ventana MÓVIL estimada con
// la serie diaria (QuotaStore.getSeries: la API sólo agrega por día UTC;
// el día más antiguo se prorratea) extrapolado al fin del periodo:
// RITMO /d, PROYECCIÓN (usado + ritmo x días restantes), veredicto (TE
// PASARÁS rojo / JUSTO ámbar / VAS BIEN verde), QUEDAN días · saldo y SE
// AGOTA (cuándo, a este ritmo). En tokens: créditos x ratio tokens/crédito
// de la misma ventana.
//
// ACTIVIDAD · 7 D (5/5): barras de créditos por día (hoy en verde, inicial
// del día debajo) y PETICIONES, TOK/PET, CACHÉ (cached/prompt) de la semana
// más el HISTÓRICO de tokens (all_time).
//
// Geometría: márgenes escalados con sc() (base 260) y pasos verticales de
// las métricas REALES de FONT_XTINY. Estilo: fondo negro, UNA hairline
// DK_GRAY por vista, violeta COLOR_PURPLE exacto (paleta de 64 colores).
// Dato ausente -> "—"; sin serie diaria -> "Sin datos diarios".
// =============================================================================
class NaNUsageBreakdownView extends WatchUi.View {

    // --- geometría de DISEÑO (px a 260x260, fr955) ---
    // MULTI-DISPOSITIVO (foto fr970 454x454: filas y renglones encimados):
    // las Y ya NO son absolutas. Los márgenes se escalan con sc() (base
    // 260) y los PASOS verticales salen de las métricas REALES de
    // FONT_XTINY (altura, ascent y altura de mayúsculas), que no escalan en
    // proporción entre dispositivos (fr955 RobotoCondensed-Bold 21 px; AMOLED
    // Roboto-Regular, más alta en relación al panel). En el fr955 los
    // valores resultantes reproducen la maqueta original (título 46, total
    // 70, hairline 96, bases 116 + 18 k, pie 230; proyección 78/99/120/141 y
    // 168/188/208).
    private const TITLE_Y = 36;         // top de "DESGLOSE · 30 D" / "PROYECCIÓN"
    private const HEAD_GAP = 3;         // aire entre título y total
    private const HAIR_GAP = 5;         // aire entre la última línea y la hairline
    private const HAIR_HALF = 74;       // hairline de cx-74 a cx+74
    private const ROW_TOP_GAP = 7;      // aire hairline -> tinta de la fila 1
    private const ROW_HALF_MAX = 90;    // techo del semiancho de fila
    private const ROW_MARGIN = 9;       // margen de las filas al cristal
    private const BAR_H = 2;            // barra fina (la principal usa 3)
    private const PAGE_Y = 230;         // top del indicador de página/pantalla
    private const PAGE_BOTTOM = 8;      // margen bajo el indicador al cristal
    private const MAX_ROWS_PER_PAGE = 7;

    // --- PROYECCIÓN ---
    // UNA hairline por vista (regla de marca): la sección de conteos se
    // separa de la de periodo sólo con aire (SECTION_GAP).
    private const KV_TOP_GAP = 6;       // hairline -> RITMO
    private const KV_PITCH_1 = 21;      // RITMO/PROYECCIÓN/veredicto/QUEDAN
    private const KV_PITCH_2 = 20;      // renglones de ACTIVIDAD
    private const CHART_H = 26;         // alto de las barras de ACTIVIDAD
    private const CHART_SLOT = 17;      // ancho de cada día (barra + aire)
    private const LAST_SCREEN = 3;      // 0 desglose, 1 24 H, 2 7 D, 3 actividad
    private const TOK_COLOR = Graphics.COLOR_BLUE;  // cifras en tokens
    // Barras de ACTIVIDAD: lila claro tirando a rosa (0xFF55FF existe tal
    // cual en la paleta de 64 colores); el violeta de marca no contrasta
    // con el negro en la pantalla MIP del fr955.
    private const BAR_COLOR = 0xFF55FF;
    private const SERIES_TTL_S = 600;   // la serie diaria se repide si > 10 min
    private const KV_MARGIN = 10;       // margen al cristal de los renglones
    private const PAGE_PAD = 4;         // aire interior del half de cuerda
    private const KV_GUTTER = 5;        // medio eje central etiqueta | valor

    private var mState as CreditState or Null; //!< instantánea de la caché
    private var mPage as Lang.Number = 0;     //!< página del desglose, 0-based
    private var mScreen as Lang.Number = 0;   //!< 0 DESGLOSE (2/5), 1 24 H (3/5),
                                              //!< 2 7 D (4/5), 3 ACTIVIDAD (5/5)
    private var mTok as Lang.Boolean = false; //!< unidad: true = tokens (START alterna)
    private var mS as Lang.Float = 1.0; //!< factor de escala = min(w, h) / 260.0
    private var mFh as Lang.Number = 21; //!< altura de FONT_XTINY (px)
    private var mAsc as Lang.Number = 17; //!< ascent de FONT_XTINY (top de celda -> base)
    private var mCap as Lang.Number = 13; //!< altura de mayúsculas/dígitos de FONT_XTINY
    private var mRowsPerPage as Lang.Number = 7; //!< filas del desglose que caben (>= 1)

    function initialize() {
        View.initialize();
        mState = QuotaStore.getCachedState();
        mPage = 0;
        mScreen = 0;
        mS = 1.0;
        mFh = 21;
        mAsc = 17;
        mCap = 13;
        mRowsPerPage = MAX_ROWS_PER_PAGE;
    }

    //! Métricas del dispositivo: escala de diseño (base 260) y medidas reales
    //! de FONT_XTINY. La altura de mayúsculas no la da la API: en las Roboto
    //! de Garmin es ~0,62 de la altura de celda (fr955: digitHeight 13 / 21).
    private function updateMetrics(dc as Graphics.Dc) as Void {
        var m = dc.getWidth();
        if (dc.getHeight() < m) {
            m = dc.getHeight();
        }
        var s = m / 260.0;
        if (s != mS) {
            mS = s;
            }
        mFh = dc.getFontHeight(Graphics.FONT_XTINY);
        mAsc = Graphics.getFontAscent(Graphics.FONT_XTINY);
        if (mAsc <= 0 || mAsc > mFh) {
            mAsc = (0.8 * mFh).toNumber();
        }
        mCap = (0.62 * mFh + 0.5).toNumber();
    }

    //! Escala un valor de diseño (px a 260x260); identidad con s = 1.
    private function sc(v as Lang.Numeric) as Lang.Number {
        return (v * mS + 0.5).toNumber();
    }

    //! Escala con suelo de 1 px (grosores).
    private function sc1(v as Lang.Numeric) as Lang.Number {
        var r = sc(v);
        return (r < 1) ? 1 : r;
    }

    //! Top del indicador de pie: el de diseño, salvo que la fuente no quepa
    //! sobre el cristal (fuentes altas en relación al panel).
    private function pageY(dc as Graphics.Dc) as Lang.Number {
        var y = sc(PAGE_Y);
        var lim = dc.getHeight() - mFh - sc(PAGE_BOTTOM);
        return (y < lim) ? y : lim;
    }

    //! Y del total y de la hairline del desglose (dependen de la fuente).
    private function totalY() as Lang.Number {
        return sc(TITLE_Y) + mFh + sc(HEAD_GAP);
    }

    private function breakdownHairY() as Lang.Number {
        return totalY() + mFh + sc(HAIR_GAP);
    }

    //! Geometría de filas: base de la fila 1, paso, desfase base -> barra.
    //! Paso = mayúsculas + aire + barra + aire: la barra de una fila nunca
    //! toca la tinta de la siguiente (fr955: 13 + 2 + 2 + 1 = 18).
    private function rowBarOff() as Lang.Number {
        var v = mFh / 8;
        return (v < 2) ? 2 : v;
    }

    private function rowGapBelow() as Lang.Number {
        var v = mFh / 14;
        return (v < 1) ? 1 : v;
    }

    private function rowPitch() as Lang.Number {
        return mCap + rowBarOff() + sc1(BAR_H) + rowGapBelow();
    }

    private function rowFirstBase() as Lang.Number {
        return breakdownHairY() + sc(ROW_TOP_GAP) + mCap;
    }

    //! La caché se RELEE al mostrarse: si el usuario volvió de un SELECT en
    //! la principal (o la app re-sincronizó), la pantalla pinta lo último.
    function onShow() {
        mState = QuotaStore.getCachedState();
        clampPage();
    }

    function onLayout(dc as Graphics.Dc) {
        View.onLayout(dc);
    }

    function onUpdate(dc as Graphics.Dc) {
        View.onUpdate(dc);

        // Anti-aliasing defensivo, igual que la vista principal.
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        // B5: color ANTES de clear para garantizar el fondo negro.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        updateMetrics(dc);
        updateRowsPerPage(dc);

        // Sin caché: "Sin datos" y BACK para volver, en el patrón del estado
        // vacío de la vista principal. Con caché pero sin NINGÚN modelo con
        // consumo (todo gratuito): "Sin consumo".
        var st = mState;
        if (st == null) {
            drawNoData(dc, cx, h / 2, "Sin datos");
            return;
        }

        mTok = QuotaStore.showTokens();
        if (mScreen == 1) {
            drawProjection(dc, cx, 1);
        } else if (mScreen == 2) {
            drawProjection(dc, cx, 7);
        } else if (mScreen == 3) {
            drawActivity(dc, cx);
        } else {
            if (st.models().size() == 0) {
                drawNoData(dc, cx, h / 2, "Sin consumo");
                return;
            }
            drawHeader(dc, cx);
            drawRows(dc, cx);
            drawPageIndicator(dc, cx);
        }
    }

    // -------------------------------------------------------------------------
    // DESGLOSE (2/5)
    // -------------------------------------------------------------------------

    //! Cabecera: etiqueta de sección gris (patrón .sechead: MAYÚSCULAS,
    //! discreta) con el total del PERIODO en blanco y la hairline de marca.
    private function drawHeader(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var titleY = sc(TITLE_Y);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, titleY, Graphics.FONT_XTINY,
            fitFlatIfNeeded(dc, "DESGLOSE · 30 D", 2 * chordHalf(dc, titleY)),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Total: en créditos el del PERIODO ("4.0K de 7.0K créditos"); en
        // tokens el de la VENTANA ("5.2B tokens"), en azul. Si no cabe en la
        // cuerda, sin la palabra de la unidad.
        var st = mState;
        if (st == null) {
            return;                       // drawHeader sólo corre con caché
        }
        var tY = totalY();
        var maxW = 2 * chordHalf(dc, tY);
        var total;
        var short;
        if (mTok) {
            short = QuotaStore.tokenLabel(st.totTokens()) + " tok";
            total = QuotaStore.tokenLabel(st.totTokens()) + " tokens";
        } else {
            short = QuotaStore.creditLabel(st.used()) + " de "
                + QuotaStore.creditLabel(st.allowance());
            total = short + " créditos";
        }
        if (dc.getTextWidthInPixels(total, Graphics.FONT_XTINY) > maxW) {
            total = fitFlatIfNeeded(dc, short, maxW);
        }
        dc.setColor(unitColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, tY, Graphics.FONT_XTINY, total,
            Graphics.TEXT_JUSTIFY_CENTER);

        // Hairline de 1 px en DK_GRAY, mismo trazo (cx±74) que la principal.
        var hairY = breakdownHairY();
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - sc(HAIR_HALF), hairY, cx + sc(HAIR_HALF), hairY);
    }

    //! Página corriente de la lista: ETIQUETA única (LT_GRAY, MAYÚSCULAS,
    //! compacta, truncada sólo si aun así no cupiera) a la izquierda;
    //! a la derecha los créditos (WHITE); bajo el texto, barra fina de pista
    //! DK_GRAY con relleno COLOR_PURPLE proporcional a la cuota sobre
    //! totals.credits (ventana).
    private function drawRows(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var st = mState;
        if (st == null) {
            return;                       // drawRows sólo corre con caché
        }
        var models = st.models();
        var rowHalf = rowHalfWidth(dc);
        var left = cx - rowHalf;
        var right = cx + rowHalf;
        var span = 2 * rowHalf;
        var start = mPage * mRowsPerPage;
        var firstBase = rowFirstBase();
        var pitch = rowPitch();
        var barOff = rowBarOff();
        var barH = sc1(BAR_H);
        for (var i = 0; i < mRowsPerPage; i++) {
            var idx = start + i;
            if (idx >= models.size()) {
                break;
            }
            var mV = models[idx];
            if (!(mV instanceof ModelCredit)) {
                continue;
            }
            var m = mV as ModelCredit;
            var baseY = firstBase + i * pitch;
            var topY = baseY - mAsc;
            var barY = baseY + barOff;

            // Cifra en la unidad activa: "3.1K cr" (blanco) o "1.2B tok"
            // (azul). La unidad se omite en la fila si la etiqueta entera no
            // cupiera con ella (el nombre manda; la cabecera ya la dice).
            var credits = m.credits();
            var num = mTok
                ? QuotaStore.tokenLabel(m.tokens())
                : ((credits == null) ? "—" : QuotaStore.creditLabel(credits));
            var creditTxt = num + (mTok ? " tok" : " cr");
            var air0 = sc(6) + sc1(2);
            if (span - dc.getTextWidthInPixels(creditTxt, Graphics.FONT_XTINY) - air0
                    < dc.getTextWidthInPixels(m.label(), Graphics.FONT_XTINY)) {
                creditTxt = num;
            }
            var creditW = dc.getTextWidthInPixels(creditTxt,
                Graphics.FONT_XTINY);

            // Sólo créditos (los tokens se quitaron: confundían "454 · 3.6B").
            var air = sc(6) + sc1(2);
            var name = fitLabel(dc, m.label(), span - creditW - air);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, topY, Graphics.FONT_XTINY, name,
                Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(unitColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(right, topY, Graphics.FONT_XTINY, creditTxt,
                Graphics.TEXT_JUSTIFY_RIGHT);

            // Barra fina: cuota del modelo en la ventana, en la unidad activa
            // (créditos sobre totals.credits; tokens sobre total_tokens).
            var f = 0.0;
            if (mTok) {
                var mt = QuotaStore.asFloat(m.tokens());
                var ttf = QuotaStore.asFloat(st.totTokens());
                if (mt != null && ttf != null && ttf > 0.0) {
                    f = mt / ttf;
                    f = (f > 1.0) ? 1.0 : f;
                }
            } else if (credits != null) {
                f = m.windowFraction(st.windowTotal());
            }
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left, barY, span, barH);
            var fillW = (span * f).toNumber() as Lang.Number;
            if (fillW < 1 && f > 0.0) {
                fillW = 1;
            }
            if (fillW > 0) {
                dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(left, barY, fillW, barH);
            }
        }
    }

    //! Filas que caben entre la hairline y el pie (tope 7, mínimo 1): la
    //! barra de la última fila acaba antes del top del indicador.
    private function updateRowsPerPage(dc as Graphics.Dc) as Void {
        var lastBarBottom = pageY(dc) - sc1(1);
        var firstBarBottom = rowFirstBase() + rowBarOff() + sc1(BAR_H);
        var n = 1 + (lastBarBottom - firstBarBottom) / rowPitch();
        if (n > MAX_ROWS_PER_PAGE) {
            n = MAX_ROWS_PER_PAGE;
        }
        mRowsPerPage = (n < 1) ? 1 : n;
        clampPage();
    }

    //! Semiancho de las filas: la cuerda del círculo (margen ROW_MARGIN) en
    //! la Y más extrema de la página (barra de la última fila), con techo
    //! ROW_HALF_MAX para no estirar la lista en pantallas grandes. En fr955:
    //! barra más baja 228..229 -> cuerda ~70 px.
    private function rowHalfWidth(dc as Graphics.Dc) as Lang.Number {
        var cy = dc.getHeight() / 2;
        var rSafe = dc.getWidth() / 2 - sc(ROW_MARGIN);
        var yBot = rowFirstBase() + (mRowsPerPage - 1) * rowPitch()
            + rowBarOff() + sc1(BAR_H);
        var dy = yBot - cy;
        var dyTop = cy - (rowFirstBase() - mCap);
        if (dyTop > dy) {
            dy = dyTop;
        }
        var half = sc(ROW_HALF_MAX);
        if (dy > 0 && dy < rSafe) {
            var c = (Math.sqrt((rSafe * rSafe - dy * dy) * 1.0)).toNumber();
            if (c < half) {
                half = c;
            }
        }
        return half;
    }

    //! Indicador de pie: página del desglose + pantalla. Con más de una
    //! página "1/2 · 2/5"; si no, sólo la pantalla ("2/5").
    private function drawPageIndicator(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var pages = pageCount();
        var txt = ((pages > 1) ? ((mPage + 1) + "/" + pages + " · ") : "")
            + "2/5";
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, pageY(dc), Graphics.FONT_XTINY, txt,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Estado vacío (sin caché) o lista vacía tras filtrar los gratuitos
    //! ("Sin consumo"): mismo patrón que la principal. BACK siempre funciona
    //! (delegate).
    private function drawNoData(dc as Graphics.Dc, cx as Lang.Number,
            cy as Lang.Number, msg as Lang.String) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_MEDIUM, msg,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + dc.getFontHeight(Graphics.FONT_MEDIUM) / 2 + mFh,
            Graphics.FONT_XTINY, "pulsa BACK para volver",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Páginas del desglose (>= 1).
    private function pageCount() as Lang.Number {
        var st = mState;
        var n = (st == null) ? 0 : st.models().size();
        var pages = (n + mRowsPerPage - 1) / mRowsPerPage;
        return (pages < 1) ? 1 : pages;
    }

    // -------------------------------------------------------------------------
    // Helpers de tabla (proyecciones y actividad)
    // -------------------------------------------------------------------------

    //! Semáforo por severidad (gemela del de la vista principal): verde
    //! < 50 %, ámbar 50-80 %, rojo > 80 %. Sólo para "QUEDAN".
    private function severityColor(frac as Lang.Float) as Graphics.ColorType {
        if (frac > 0.8) {
            return Graphics.COLOR_RED;
        }
        if (frac >= 0.5) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_GREEN;
    }

    //! Semi-cuerda ÚTIL del círculo para un renglón cuyo top está en `topY`
    //! (altura de renglón = FONT_XTINY): radio seguro = w/2 - 10 (margen
    //! >= 10 px al borde, como subAvailWidth() en la principal) menos 4 px
    //! de aire interior. El ancho útil decrece hacia el borde: RITMO (y=78)
    //! puede medir 218 px, CACHÉ (y=208..229) sólo ~126 px.
    private function chordHalf(dc as Graphics.Dc, topY as Lang.Number) as Lang.Number {
        var cy = dc.getHeight() / 2;
        var rSafe = dc.getWidth() / 2 - sc(KV_MARGIN);
        var h = mFh;
        var dyT = topY - cy;
        if (dyT < 0) {
            dyT = -dyT;
        }
        var dyB = topY + h - cy;
        if (dyB < 0) {
            dyB = -dyB;
        }
        var dy = (dyB > dyT) ? dyB : dyT;
        if (dy >= rSafe) {
            return 0;
        }
        var half = (Math.sqrt((rSafe * rSafe - dy * dy) * 1.0)).toNumber()
            - sc(PAGE_PAD);
        return (half > 0) ? half : 0;
    }

    //! Eje de tabla: si a la altura de algún renglón (tops `ys`) su etiqueta
    //! no cabe entre el borde de la cuerda y el eje, el eje se desplaza a la
    //! derecha lo justo antes de recurrir al recorte con "..".
    private function clampAxis(dc as Graphics.Dc, cx as Lang.Number, gx as Lang.Number,
            labels as Lang.Array, ys as Lang.Array) as Lang.Number {
        var g = sc1(KV_GUTTER);
        for (var i = 0; i < labels.size(); i++) {
            var need = cx - chordHalf(dc, ys[i] as Lang.Number) + g
                + dc.getTextWidthInPixels(labels[i] as Lang.String, Graphics.FONT_XTINY);
            if (gx < need) {
                gx = need;
            }
        }
        return gx;
    }

    //! Renglón tipo tabla: etiqueta (LT_GRAY) alineada a la derecha contra
    //! gx - KV_GUTTER y valor (color dado) a la izquierda desde gx +
    //! KV_GUTTER. El eje gx lo fija drawProjection() para centrar la tabla:
    //! en pantalla redonda la tinta se concentra cerca del centro, donde la
    //! cuerda es más ancha, y las columnas quedan alineadas en todos los
    //! dispositivos. Si la etiqueta no cupiera hasta el borde de la cuerda,
    //! se recorta con "..".
    private function drawKV(dc as Graphics.Dc, topY as Lang.Number,
            gx as Lang.Number, label as Lang.String, value as Lang.String,
            valueColor as Graphics.ColorType) as Void {
        var cx = dc.getWidth() / 2;
        var g = sc1(KV_GUTTER);
        var room = gx - g - (cx - chordHalf(dc, topY));
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(gx - g, topY, Graphics.FONT_XTINY,
            fitFlatIfNeeded(dc, label, room), Graphics.TEXT_JUSTIFY_RIGHT);
        if (value.length() > 0) {
            dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(gx + g, topY, Graphics.FONT_XTINY, value,
                Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // -------------------------------------------------------------------------
    // Unidad (START alterna créditos <-> tokens en las pantallas 2-4)
    // -------------------------------------------------------------------------

    //! Color de las CIFRAS según la unidad: créditos en blanco, tokens en
    //! azul (COLOR_BLUE existe tal cual en la paleta de 64 colores).
    private function unitColor() as Graphics.ColorType {
        return mTok ? TOK_COLOR : Graphics.COLOR_WHITE;
    }

    //! Cantidad en la unidad activa a partir de CRÉDITOS: "3.1K cr" o, en
    //! tokens, "~1.2B tok": créditos x ratio tokens/crédito de la ventana.
    //! Es una EQUIVALENCIA con la mezcla de modelos de esa ventana (un
    //! crédito rinde más tokens en modelos baratos), de ahí la "~". Ratio
    //! desconocido -> "—".
    private function fmtAmount(credits as Lang.Float, ratio as Lang.Float or Null) as Lang.String {
        if (mTok) {
            if (ratio == null) {
                return "—";
            }
            return "~" + QuotaStore.tokenLabel(credits * ratio) + " tok";
        }
        return QuotaStore.creditLabel(credits) + " cr";
    }

    //! START: alterna la unidad (desglose y proyecciones). En ACTIVIDAD no
    //! aplica (sus cifras ya llevan su unidad).
    function onSelectPressed() as Void {
        if (mScreen <= 2) {
            QuotaStore.toggleUnit();
            WatchUi.requestUpdate();
        }
    }

    // -------------------------------------------------------------------------
    // Serie diaria (QuotaStore.getSeries): helpers
    // -------------------------------------------------------------------------

    //! Valor del día `back` (0 = hoy UTC, 1 = ayer...) de la serie `key`.
    //! La serie se pidió el día s["d"]; si es de un día anterior, los días
    //! posteriores no existen (0).
    private function dayVal(s as Lang.Dictionary<Lang.String, Lang.Object or Null>, key as Lang.String,
            back as Lang.Number) as Lang.Float {
        var arrV = s.get(key);
        if (!(arrV instanceof Lang.Array)) {
            return 0.0;
        }
        var arr = arrV as Lang.Array<Lang.Object>;
        var today = QuotaStore.nowEpoch() / 86400;
        var idx = 7 - back - (today - (s.get("d") as Lang.Number));
        if (idx < 0 || idx > 7 || idx >= arr.size()) {
            return 0.0;
        }
        var v = QuotaStore.asFloat(arr[idx]);
        return (v == null) ? 0.0 : v;
    }

    //! Suma ponderada de la ventana: `days` = 1 (24 h) o 7. Los `days` días
    //! más recientes (hoy incluido, parcial) completos + el día anterior
    //! prorrateado por lo que falta del día UTC de hoy: ventana MÓVIL de
    //! days x 24 h estimada con datos diarios (la API no da horas).
    private function windowSum(s as Lang.Dictionary<Lang.String, Lang.Object or Null>, key as Lang.String,
            days as Lang.Number) as Lang.Float {
        var f = (QuotaStore.nowEpoch() % 86400) / 86400.0;
        var sum = 0.0;
        for (var b = 0; b < days; b++) {
            sum += dayVal(s, key, b);
        }
        return sum + dayVal(s, key, days) * (1.0 - f);
    }

    //! Pantalla sin serie diaria (aún no llegó la 2ª petición): título,
    //! aviso y pie.
    private function drawNoSeries(dc as Graphics.Dc, cx as Lang.Number,
            title as Lang.String, footer as Lang.String) as Void {
        var titleY = sc(TITLE_Y);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, titleY, Graphics.FONT_XTINY, title,
            Graphics.TEXT_JUSTIFY_CENTER);
        var hairY = titleY + mFh + sc(HAIR_GAP);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - sc(HAIR_HALF), hairY, cx + sc(HAIR_HALF), hairY);
        var cy = dc.getHeight() / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - mFh, Graphics.FONT_XTINY, "Sin datos diarios",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + sc(2), Graphics.FONT_XTINY, "refresca en la 1/5",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, pageY(dc), Graphics.FONT_XTINY, footer,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------------------
    // PROYECCIÓN 24 H (3/5) y 7 D (4/5)
    // -------------------------------------------------------------------------

    //! Ritmo de la ventana móvil (24 h o 7 d) extrapolado al fin del periodo
    //! de facturación: RITMO /d, PROYECCIÓN (usado + ritmo x días que
    //! quedan), veredicto, QUEDAN (días · saldo) y SE AGOTA (cuándo, a este
    //! ritmo). Todo en la unidad activa; en tokens, créditos x ratio
    //! tokens/crédito de la propia ventana.
    private function drawProjection(dc as Graphics.Dc, cx as Lang.Number,
            days as Lang.Number) as Void {
        var st = mState;
        if (st == null) {
            return;                       // drawProjection sólo corre con caché
        }
        var title = (days == 1) ? "PROYECCIÓN · 24 H" : "PROYECCIÓN · 7 D";
        var footer = (days == 1) ? "3/5" : "4/5";
        var s = QuotaStore.getSeries();
        if (s == null) {
            drawNoSeries(dc, cx, title, footer);
            return;
        }

        // --- Geometría: 5 renglones bajo la hairline; si no cupieran sobre
        // el pie, se comprime el paso (nunca por debajo de mayúsculas + 4).
        var pY = pageY(dc);
        var titleY = sc(TITLE_Y);
        var p = sc(KV_PITCH_1);
        if (p < mFh) {
            p = mFh;
        }
        var head = mFh + sc(HAIR_GAP) + sc(KV_TOP_GAP);
        var avail = pY - sc1(1) - titleY - head - mFh;
        if (4 * p > avail) {
            p = avail / 4;
            if (p < mCap + 4) {
                p = mCap + 4;
            }
        }
        var hairY = titleY + mFh + sc(HAIR_GAP);
        var y0 = hairY + sc(KV_TOP_GAP);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, titleY, Graphics.FONT_XTINY, title,
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - sc(HAIR_HALF), hairY, cx + sc(HAIR_HALF), hairY);

        // --- Cálculo.
        var crW = windowSum(s, "cr", days);
        var tkW = windowSum(s, "tk", days);
        var rate = crW / days;                         // créditos / día
        var ratio = (crW > 0.0) ? tkW / crW : null;    // tokens / crédito

        var now = QuotaStore.nowEpoch();
        var endDay = st.periodDay();
        var daysLeft = 0.0;
        if (endDay != null) {
            daysLeft = (endDay * 86400 - now) / 86400.0;
            if (daysLeft < 0.0) {
                daysLeft = 0.0;
            }
        }
        var allowance = st.allowance();
        var used = st.used();
        var left = st.remaining();
        if (left == null) {
            left = allowance - used;
        }
        if (left < 0.0) {
            left = 0.0;
        }
        var projection = used + rate * daysLeft;

        var verdict = "—";                   // sin allowance no hay veredicto
        var vColor = Graphics.COLOR_LT_GRAY;
        if (allowance > 0.0 && projection > allowance) {
            verdict = "TE PASARÁS +" + fmtAmount(projection - allowance, ratio);
            vColor = Graphics.COLOR_RED;
        } else if (allowance > 0.0 && projection < allowance * 0.8) {
            verdict = "VAS BIEN";
            vColor = Graphics.COLOR_GREEN;
        } else if (allowance > 0.0) {
            verdict = "JUSTO";
            vColor = Graphics.COLOR_YELLOW;
        }

        // SE AGOTA: saldo / ritmo, si cae antes del reset.
        var agota = "NO";
        var aColor = Graphics.COLOR_GREEN;
        if (rate > 0.0 && left / rate < daysLeft) {
            var dEx = left / rate;
            agota = (dEx < 1.0)
                ? "EN " + (dEx * 24.0).toNumber() + " H"
                : "EN " + dEx.toNumber() + " D";
            aColor = Graphics.COLOR_RED;
        }

        var dReset = QuotaStore.daysUntilReset(endDay);
        if (dReset != null && dReset < 0) {
            dReset = 0;
        }
        var dTxt = (dReset == null) ? null : dReset + " D";

        // RITMO en tokens es EXACTO (tokens reales de la ventana / días);
        // el resto en tokens es equivalencia (~).
        var ritmoTxt = mTok
            ? QuotaStore.tokenLabel(tkW / days) + " tok/d"
            : QuotaStore.creditLabel(rate) + " cr/d";
        var proyTxt = fmtAmount(projection, ratio);
        var leftTxt = fmtAmount(left, ratio);

        // --- Eje de la tabla centrado (etiqueta más ancha + valor más ancho).
        var labels = ["RITMO", "PROYECCIÓN", "QUEDAN", "SE AGOTA"];
        var maxL = 0;
        for (var i = 0; i < labels.size(); i++) {
            var lw = dc.getTextWidthInPixels(labels[i] as Lang.String, Graphics.FONT_XTINY);
            if (lw > maxL) {
                maxL = lw;
            }
        }
        var quedanW = dc.getTextWidthInPixels(leftTxt, Graphics.FONT_XTINY);
        if (dTxt != null) {
            quedanW += dc.getTextWidthInPixels(dTxt + " · ", Graphics.FONT_XTINY);
        }
        var maxV = quedanW;
        var vals = [ritmoTxt, proyTxt, agota];
        for (var i = 0; i < vals.size(); i++) {
            var vw = dc.getTextWidthInPixels(vals[i] as Lang.String, Graphics.FONT_XTINY);
            if (vw > maxV) {
                maxV = vw;
            }
        }
        var gx = clampAxis(dc, cx, cx + (maxL - maxV) / 2, labels,
            [y0, y0 + p, y0 + 3 * p, y0 + 4 * p]);

        drawKV(dc, y0, gx, "RITMO", ritmoTxt, unitColor());
        drawKV(dc, y0 + p, gx, "PROYECCIÓN", proyTxt, unitColor());

        dc.setColor(vColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y0 + 2 * p, Graphics.FONT_XTINY,
            fitFlatIfNeeded(dc, verdict, 2 * chordHalf(dc, y0 + 2 * p)),
            Graphics.TEXT_JUSTIFY_CENTER);

        var qY = y0 + 3 * p;
        drawKV(dc, qY, gx, "QUEDAN", "", Graphics.COLOR_WHITE);
        var x = gx + sc1(KV_GUTTER);
        if (dTxt != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, qY, Graphics.FONT_XTINY, dTxt, Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(dTxt, Graphics.FONT_XTINY);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, qY, Graphics.FONT_XTINY, " · ", Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(" · ", Graphics.FONT_XTINY);
        }
        dc.setColor(unitColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, qY, Graphics.FONT_XTINY, leftTxt, Graphics.TEXT_JUSTIFY_LEFT);

        drawKV(dc, y0 + 4 * p, gx, "SE AGOTA", agota, aColor);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, pY, Graphics.FONT_XTINY, footer, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------------------
    // ACTIVIDAD · 7 D (5/5)
    // -------------------------------------------------------------------------

    //! Gráfica de barras de créditos por día (7 días, hoy en verde lima,
    //! inicial del día UTC debajo) y conteos de la semana: PETICIONES,
    //! TOK/PETICIÓN, CACHÉ (cached / prompt) y el HISTÓRICO de tokens.
    private function drawActivity(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var title = "ACTIVIDAD · 7 D";
        var s = QuotaStore.getSeries();
        if (s == null) {
            drawNoSeries(dc, cx, title, "5/5");
            return;
        }
        var pY = pageY(dc);
        var titleY = sc(TITLE_Y);
        var hairY = titleY + mFh + sc(HAIR_GAP);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, titleY, Graphics.FONT_XTINY, title,
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - sc(HAIR_HALF), hairY, cx + sc(HAIR_HALF), hairY);

        // --- Barras: más antiguo a la izquierda, hoy a la derecha.
        var chartTop = hairY + sc(6);
        var chartH = sc(CHART_H);
        var slot = sc(CHART_SLOT);
        var barW = slot - sc1(5);
        var x0 = cx - (7 * slot) / 2;
        var maxC = 0.0;
        for (var b = 0; b < 7; b++) {
            var v = dayVal(s, "cr", b);
            if (v > maxC) {
                maxC = v;
            }
        }
        var today = QuotaStore.nowEpoch() / 86400;
        var letters = ["D", "L", "M", "X", "J", "V", "S"];
        for (var i = 0; i < 7; i++) {
            var back = 6 - i;
            var bx = x0 + i * slot + (slot - barW) / 2;
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, chartTop, barW, chartH);
            var v = dayVal(s, "cr", back);
            if (maxC > 0.0 && v > 0.0) {
                var bh = (chartH * v / maxC).toNumber();
                if (bh < 1) {
                    bh = 1;
                }
                dc.setColor((back == 0) ? Graphics.COLOR_GREEN : BAR_COLOR,
                    Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(bx, chartTop + chartH - bh, barW, bh);
            }
            dc.setColor((back == 0) ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY,
                Graphics.COLOR_TRANSPARENT);
            dc.drawText(bx + barW / 2, chartTop + chartH + sc1(1), Graphics.FONT_XTINY,
                letters[(today - back + 4) % 7], Graphics.TEXT_JUSTIFY_CENTER);
        }

        // --- Conteos de la semana (7 días: hoy parcial + 6 completos).
        var rq = 0.0;
        var tk = 0.0;
        var ca = 0.0;
        var pt = 0.0;
        for (var b = 0; b < 7; b++) {
            rq += dayVal(s, "rq", b);
            tk += dayVal(s, "tk", b);
            ca += dayVal(s, "ca", b);
            pt += dayVal(s, "pt", b);
        }
        var reqTxt = QuotaStore.tokenLabel(rq);
        var perTxt = (rq > 0.0) ? QuotaStore.tokenLabel(tk / rq) + " tok" : "—";
        var cacheTxt = "—";
        if (pt > 0.0) {
            var pct = (ca * 100.0 / pt + 0.5).toNumber();
            cacheTxt = ((pct > 100) ? 100 : pct) + "%";
        }
        var at = QuotaStore.getAllTimeTokens();
        var atTxt = QuotaStore.isNumeric(at) ? QuotaStore.tokenLabel(at) + " tok" : "—";

        var labels = ["PETICIONES", "TOK/PET", "CACHÉ", "HISTÓRICO"];
        var vals = [reqTxt, perTxt, cacheTxt, atTxt];
        var colors = [Graphics.COLOR_WHITE, TOK_COLOR, Graphics.COLOR_WHITE, TOK_COLOR];
        var p = sc(KV_PITCH_2);
        if (p < mFh - 1) {
            p = mFh - 1;
        }
        var y0 = chartTop + chartH + sc1(1) + mFh + sc(4);
        if (y0 + 3 * p + mFh > pY - sc1(1)) {
            p = (pY - sc1(1) - mFh - y0) / 3;
            if (p < mCap + 4) {
                p = mCap + 4;
            }
        }
        var maxL = 0;
        var maxV = 0;
        for (var i = 0; i < labels.size(); i++) {
            var lw = dc.getTextWidthInPixels(labels[i] as Lang.String, Graphics.FONT_XTINY);
            var vw = dc.getTextWidthInPixels(vals[i] as Lang.String, Graphics.FONT_XTINY);
            if (lw > maxL) {
                maxL = lw;
            }
            if (vw > maxV) {
                maxV = vw;
            }
        }
        var gx = cx + (maxL - maxV) / 2;
        var ys = [];
        for (var i = 0; i < labels.size(); i++) {
            ys.add(y0 + i * p);
        }
        gx = clampAxis(dc, cx, gx, labels, ys);
        for (var i = 0; i < labels.size(); i++) {
            drawKV(dc, y0 + i * p, gx, labels[i] as Lang.String, vals[i] as Lang.String,
                colors[i] as Graphics.ColorType);
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, pY, Graphics.FONT_XTINY, "5/5", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------------------
    // Navegación interna (llamadas del delegate)
    // -------------------------------------------------------------------------

    //! DOWN: pagina el desglose; desde su ÚLTIMA página pasa a 24 H -> 7 D ->
    //! ACTIVIDAD. Devuelve false sólo en ACTIVIDAD, donde DOWN cierra el
    //! ciclo -> popView a la principal (el delegate lo hace).
    function onNextPressed() as Lang.Boolean {
        if (mScreen == 0 && mPage < pageCount() - 1) {
            mPage++;
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen >= LAST_SCREEN) {
            return false;
        }
        mScreen++;
        QuotaStore.ensureSeries(SERIES_TTL_S);
        WatchUi.requestUpdate();
        return true;
    }

    //! UP: retrocede de pantalla (24 H -> desglose por su última página) y
    //! pagina el desglose; en su página 1 devuelve false -> principal.
    function onPrevPressed() as Lang.Boolean {
        if (mScreen > 1) {
            mScreen--;
            QuotaStore.ensureSeries(SERIES_TTL_S);
            WatchUi.requestUpdate();
            return true;
        }
        if (mScreen == 1) {
            mScreen = 0;
            mPage = pageCount() - 1;
            if (mPage < 0) {
                mPage = 0;
            }
            WatchUi.requestUpdate();
            return true;
        }
        if (mPage > 0) {
            mPage--;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    //! Re-clampa la página tras releer la caché (por si el desglose menguó).
    private function clampPage() as Void {
        if (mPage > pageCount() - 1) {
            mPage = pageCount() - 1;
        }
        if (mPage < 0) {
            mPage = 0;
        }
    }

    // -------------------------------------------------------------------------
    // Helpers de texto
    // -------------------------------------------------------------------------

    //! Recorta la ETIQUETA con ".." si no cabe en maxW píxeles (FONT_XTINY),
    //! CONSERVANDO lo que sigue al guion ("-K3", o el "-2" de desempate de
    //! assignLabels): dos filas jamás se ven iguales tras el recorte. Si ni el
    //! discriminador solo cupiera, cae al recorte plano clásico.
    private function fitLabel(dc as Graphics.Dc, label as Lang.String,
            maxW as Lang.Number) as Lang.String {
        if (maxW <= 0 || dc.getTextWidthInPixels(label, Graphics.FONT_XTINY)
                <= maxW) {
            return label;
        }
        var disc = "";
        var base = label;
        var idx = label.find("-");
        if (idx != null && idx > 0) {
            disc = label.substring(idx, label.length()) as Lang.String;
            base = label.substring(0, idx) as Lang.String;
        }
        var cut = base;
        while (cut.length() > 1
                && dc.getTextWidthInPixels(cut + ".." + disc,
                    Graphics.FONT_XTINY) > maxW) {
            var shorter = cut.substring(0, cut.length() - 1);
            if (shorter == null) {
                break;
            }
            cut = shorter;
        }
        var out = cut + ".." + disc;
        if (dc.getTextWidthInPixels(out, Graphics.FONT_XTINY) > maxW) {
            out = fitFlat(dc, label, maxW);     // el disc solo ya no cabe
        }
        return out;
    }

    //! El texto tal cual si cabe en maxW; si no, recorte plano con "..".
    private function fitFlatIfNeeded(dc as Graphics.Dc, txt as Lang.String,
            maxW as Lang.Number) as Lang.String {
        if (maxW <= 0
                || dc.getTextWidthInPixels(txt, Graphics.FONT_XTINY) <= maxW) {
            return txt;
        }
        return fitFlat(dc, txt, maxW);
    }

    //! Recorte plano clásico con ".." (defensa final de fitLabel).
    private function fitFlat(dc as Graphics.Dc, txt as Lang.String,
            maxW as Lang.Number) as Lang.String {
        var cut = txt;
        while (cut.length() > 1
                && dc.getTextWidthInPixels(cut + "..", Graphics.FONT_XTINY)
                    > maxW) {
            var shorter = cut.substring(0, cut.length() - 1);
            if (shorter == null) {
                break;
            }
            cut = shorter;
        }
        return cut + "..";
    }
}

//! Delegate de las pantallas 2/5..5/5: BACK vuelve a la principal; DOWN/UP
//! paginan el desglose y pasan de pantalla (actividad DOWN -> principal por
//! el ciclo; desglose pág. 1 UP -> principal). SELECT (START) alterna
//! créditos/tokens; el refresco manual sigue siendo cosa de la principal.
class NaNUsageBreakdownDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! BACK: pop del pushView hecho por NaNUsageDelegate.onNextPage().
    //! Siempre vuelve a la principal (la pila es Principal -> [esto]).
    function onBack() as Lang.Boolean {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    //! UP: pagina / retrocede de pantalla; false -> popView (a la principal).
    function onPreviousPage() as Lang.Boolean {
        var v = currentView();
        if (v != null && v.onPrevPressed()) {
            return true;
        }
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    //! DOWN: pagina / avanza de pantalla; false -> popView (ciclo a la
    //! principal desde la proyección).
    function onNextPage() as Lang.Boolean {
        var v = currentView();
        if (v != null && v.onNextPressed()) {
            return true;
        }
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    //! START: alterna créditos <-> tokens (la vista decide si aplica).
    function onSelect() as Lang.Boolean {
        var v = currentView();
        if (v != null) {
            v.onSelectPressed();
        }
        return true;
    }

    //! Mismo patrón del fix del CRASH B: WatchUi.getCurrentView() devuelve un
    //! array de DOS elementos [View, InputDelegate], NO la vista; el elemento
    //! correcto es el [0].
    private function currentView() as NaNUsageBreakdownView or Null {
        var views = WatchUi.getCurrentView();
        if (views != null && views.size() > 0) {
            return views[0] as NaNUsageBreakdownView;
        }
        return null;
    }
}
