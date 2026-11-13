using Toybox.Lang;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;

// =============================================================================
// PANTALLAS SECUNDARIAS: DESGLOSE POR MODELOS (2/3) + PROYECCIÓN (3/3)
// — nan.builders, fr955 260x260 redondo.
//
// Se PUSH desde la vista principal con DOWN (NaNUsageDelegate.onNextPage() ->
// pushView) y trae SU PROPIO delegate, de modo que la vista principal conserva
// intactos su SELECT (refresco) y su BACK (salir). Es UNA vista con DOS
// pantallas internas (mScreen): apilar Desglose y Proyección como views
// separadas obligaría a doble popView para cerrar el ciclo Proyección ->
// Principal, que WatchUi no garantiza atómico; así DOWN/UP manejan el ciclo
// con transiciones de una sola operación sobre la pila.
//
// NAVEGACIÓN (3 pantallas, ciclo):
//   Principal --DOWN--> Desglose --DOWN (última página)--> Proyección
//   Proyección --DOWN--> Principal (ciclo: popView)
//   Proyección --UP--> Desglose (última página); Desglose --UP (pág. 1)-->
//   Principal (popView); dentro del desglose DOWN/UP PAGINAN.
//   BACK siempre vuelve a la principal (y desde la principal, sale). SELECT
//   se consume aquí a propósito: el refresco manual es de la vista principal.
//
// DESGLOSE (2/3): cabecera "DESGLOSE · 30 D" + total "4.0K de 7.0K créditos"
// del PERIODO (bloque "credits"), y debajo la lista de los modelos con
// consumo de totals.by_model (de la CACHÉ de QuotaStore: esta pantalla NO
// toca red; los modelos con credits <= 0 —gratuitos— NO se listan, si tras
// filtrar no queda ninguno se muestra "Sin consumo"). Cada fila: etiqueta
// única compacta en MAYÚSCULAS ("GLM5.3", "GLM5.3F", "DS4.1PRO"; assignLabels nunca repite
// etiqueta), créditos en blanco y TOKENS en gris y más pequeño
// ("GLM5.3  2.1K · 156M") si caben; debajo, barra fina (2 px) de pista
// DK_GRAY con relleno COLOR_PURPLE de marca proporcional a la cuota sobre
// totals.credits (la ventana, NO el allowance del periodo: no suman el
// héroe). El "53%" de cuota deja su sitio a los tokens: la barra ya codifica
// la fracción.
//
// PROYECCIÓN (3/3): con los datos ya cacheados (credits + totals + by_model),
// sin red. RITMO créditos/día = used / días transcurridos desde period_start
// (guardado en caché como "ps"; si falta —caché vieja— se estima con 30 días
// y se marca "~"). PROYECCIÓN a fin de periodo = ritmo × días totales del
// periodo, con veredicto semafórico: > allowance -> "TE PASARÁS +exceso" en
// rojo; < 80 % -> "VAS BIEN" en verde; si no -> "JUSTO" en ámbar. QUEDAN
// días del periodo y créditos restantes. Segunda sección con los conteos de
// la ventana: TOKENS, PETICIONES y CACHÉ % (cached/total). Dato ausente ->
// "—". Los renglones son una tabla con eje común: etiquetas alineadas a la
// derecha y valores a la izquierda del eje, desplazado para centrar el
// bloque; si una etiqueta no cupiera en la cuerda del círculo se recorta.
//
// MULTI-DISPOSITIVO: márgenes escalados (base 260) y pasos verticales desde
// las métricas reales de FONT_XTINY; ver la cabecera de constantes.
//
// Paginación del desglose: hasta 7 filas por página (las que quepan entre la
// hairline y el pie en cada dispositivo; la cabecera es fija); con más
// de una página, el pie combina página y pantalla: "1/2 · 2/3"; si no, sólo
// "2/3" (y "3/3" en proyección). Indicador discreto LT_GRAY abajo.
//
// Estilo idéntico: fondo negro, textos blancos/grises, UNA hairline DK_GRAY
// por vista (regla de marca) y violeta COLOR_PURPLE exacto (el fr955
// cuantiza cualquier hex a su paleta de 64 colores).
//
// Si un campo falta (caché antigua sin extensión tk/rq/ca o sin "ps"), la
// fila muestra "—" en su lugar y NO rompe el arranque (ver QuotaStore: el
// nombre es el único campo imprescindible).
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
    private const TITLE_Y = 46;         // top de "DESGLOSE · 30 D" / "PROYECCIÓN"
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
    private const KV_PITCH_2 = 20;      // TOKENS/PETICIONES/CACHÉ
    private const SECTION_GAP = 6;      // aire entre las dos secciones
    private const KV_MARGIN = 10;       // margen al cristal de los renglones
    private const PAGE_PAD = 4;         // aire interior del half de cuerda
    private const KV_GUTTER = 5;        // medio eje central etiqueta | valor

    private var mState;   //!< CreditState o null (instantánea de la caché)
    private var mPage;    //!< página del desglose, 0-based
    private var mScreen;  //!< 0 = DESGLOSE (2/3), 1 = PROYECCIÓN (3/3)
    private var mTokFont; //!< fuente pequeña de tokens (vectorial) o null
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
        mTokFont = null;
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
            mTokFont = null;
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
        if (mState == null) {
            drawNoData(dc, cx, h / 2, "Sin datos");
            return;
        }

        if (mScreen == 1) {
            drawProjection(dc, cx);
        } else {
            if (mState.models().size() == 0) {
                drawNoData(dc, cx, h / 2, "Sin consumo");
                return;
            }
            drawHeader(dc, cx);
            drawRows(dc, cx);
            drawPageIndicator(dc, cx);
        }
    }

    // -------------------------------------------------------------------------
    // DESGLOSE (2/3)
    // -------------------------------------------------------------------------

    //! Cabecera: etiqueta de sección gris (patrón .sechead: MAYÚSCULAS,
    //! discreta) con el total del PERIODO en blanco y la hairline de marca.
    private function drawHeader(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var titleY = sc(TITLE_Y);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, titleY, Graphics.FONT_XTINY,
            fitFlatIfNeeded(dc, "DESGLOSE · 30 D", 2 * chordHalf(dc, titleY)),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Total del periodo; si no cabe en la cuerda, sin " créditos".
        var tY = totalY();
        var maxW = 2 * chordHalf(dc, tY);
        var short = QuotaStore.creditLabel(mState.used()) + " de "
            + QuotaStore.creditLabel(mState.allowance());
        var total = short + " créditos";
        if (dc.getTextWidthInPixels(total, Graphics.FONT_XTINY) > maxW) {
            total = fitFlatIfNeeded(dc, short, maxW);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, tY, Graphics.FONT_XTINY, total,
            Graphics.TEXT_JUSTIFY_CENTER);

        // Hairline de 1 px en DK_GRAY, mismo trazo (cx±74) que la principal.
        var hairY = breakdownHairY();
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - sc(HAIR_HALF), hairY, cx + sc(HAIR_HALF), hairY);
    }

    //! Página corriente de la lista: ETIQUETA única (LT_GRAY, MAYÚSCULAS,
    //! compacta, truncada sólo si aun así no cupiera) a la izquierda;
    //! a la derecha los créditos (WHITE) y, si caben, los TOKENS en gris y
    //! más pequeño ("2.1K · 156M"); bajo el texto, barra fina de pista
    //! DK_GRAY con relleno COLOR_PURPLE proporcional a la cuota sobre
    //! totals.credits (ventana).
    private function drawRows(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var models = mState.models();
        var rowHalf = rowHalfWidth(dc);
        var left = cx - rowHalf;
        var right = cx + rowHalf;
        var span = 2 * rowHalf;
        var start = mPage * mRowsPerPage;
        var firstBase = rowFirstBase();
        var pitch = rowPitch();
        var barOff = rowBarOff();
        var barH = sc1(BAR_H);
        // Hueco créditos|tokens sin separador (modo 2): un espacio de la
        // fuente de tokens; con 2 px "980147M" se leía como un solo número.
        var gap = dc.getTextWidthInPixels(" ", tokFontSmall());
        if (gap < sc1(3)) {
            gap = sc1(3);
        }

        for (var i = 0; i < mRowsPerPage; i++) {
            var idx = start + i;
            if (idx >= models.size()) {
                break;
            }
            var m = models[idx] as ModelCredit;
            if (m == null) {
                continue;
            }
            var baseY = firstBase + i * pitch;
            var topY = baseY - mAsc;
            var barY = baseY + barOff;

            var credits = m.credits();
            var creditTxt = (credits == null) ? "—"
                : QuotaStore.creditLabel(credits);
            var creditW = dc.getTextWidthInPixels(creditTxt,
                Graphics.FONT_XTINY);

            // Tokens de la fila ("156M"), en gris y más pequeño, SI CABEN.
            // Escalera "si cabe" por fila (el nombre NUNCA se sacrifica):
            //   1. "2.1K · 156M" (cluster con separador de marca)
            //   2. "2.1K 156M"   (sin separador, un espacio de aire)
            //   3. "2.1K"        (sin tokens: la etiqueta entera no cabría)
            var tokTxt = (m.tokens() == null)
                ? null : QuotaStore.tokenLabel(m.tokens());
            var tokFont = tokFontSmall();
            var tokW = 0;
            var sepW = 0;
            if (tokTxt != null) {
                tokW = dc.getTextWidthInPixels(tokTxt, tokFont);
                sepW = dc.getTextWidthInPixels(" · ", tokFont);
            }
            // El nombre COMPLETO manda: los tokens sólo se muestran si cabe
            // la etiqueta entera (nada de "DS4.1.." por enseñar "147M").
            var nameMin = dc.getTextWidthInPixels(m.label(), Graphics.FONT_XTINY);
            var air = sc(6) + sc1(2);
            var tokMode = 0;            // 1 = con separador, 2 = sin separador
            if (tokTxt != null) {
                if (span - creditW - tokW - sepW - air - nameMin >= 0) {
                    tokMode = 1;
                } else if (span - creditW - tokW - gap - air - nameMin >= 0) {
                    tokMode = 2;
                }
            }
            var tokBlockW = (tokMode == 1) ? tokW + sepW
                : ((tokMode == 2) ? tokW + gap : 0);

            var nameAvail = span - creditW - tokBlockW - air;
            var name = fitLabel(dc, m.label(), nameAvail);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, topY, Graphics.FONT_XTINY, name,
                Graphics.TEXT_JUSTIFY_LEFT);

            if (tokMode > 0) {
                // Cluster derecho: créditos blancos en XTINY y tokens en la
                // fuente pequeña, alineados por la línea de base. Con modo 1
                // los tokens van tras el separador " · " (gris); con modo 2,
                // tras un espacio.
                var tokTop = baseY - Graphics.getFontAscent(tokFont);
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(right, tokTop, tokFont,
                    (tokMode == 1 ? " · " : "") + tokTxt,
                    Graphics.TEXT_JUSTIFY_RIGHT);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(right - tokBlockW, topY, Graphics.FONT_XTINY,
                    creditTxt, Graphics.TEXT_JUSTIFY_RIGHT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(right, topY, Graphics.FONT_XTINY, creditTxt,
                    Graphics.TEXT_JUSTIFY_RIGHT);
            }

            // Barra fina: relleno = cuota del modelo sobre totals.credits.
            var f = (credits == null)
                ? 0.0
                : m.windowFraction(mState.windowTotal());
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(left, barY, span, barH);
            var fillW = (span * f).toNumber();
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

    //! Fuente PEQUEÑA para los tokens: vectorial "RobotoCondensed-Regular"
    //! a ~0,62 de la altura de FONT_XTINY (13 px en fr955, cara verificada
    //! en simulator.json) con fallback a
    //! FONT_XTINY; el display nunca asume que sea más pequeña (el ancho se
    //! mide y el token se omite si no cabe).
    private function tokFontSmall() as Graphics.FontType {
        if (mTokFont == null) {
            var f = null;
            // CRASH fr255: sin getVectorFont en el dispositivo la llamada es
            // un error fatal no capturable; comprobar el símbolo antes.
            if (Graphics has :getVectorFont) {
                try {
                    var sz = (0.62 * mFh + 0.5).toNumber();
                    f = Graphics.getVectorFont(
                        { :face => "RobotoCondensed-Regular", :size => sz });
                } catch (e) {
                    f = null;
                }
            }
            mTokFont = (f == null) ? Graphics.FONT_XTINY : f;
        }
        return mTokFont;
    }

    //! Indicador de pie: página del desglose + pantalla. Con más de una
    //! página "1/2 · 2/3"; si no, sólo la pantalla ("2/3").
    private function drawPageIndicator(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var pages = pageCount();
        var txt = ((pages > 1) ? ((mPage + 1) + "/" + pages + " · ") : "")
            + "2/3";
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
        var n = (mState == null) ? 0 : mState.models().size();
        var pages = (n + mRowsPerPage - 1) / mRowsPerPage;
        return (pages < 1) ? 1 : pages;
    }

    // -------------------------------------------------------------------------
    // PROYECCIÓN (3/3)
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

    //! Pantalla PROYECCIÓN (3/3): ritmo, proyección y veredicto del PERIODO
    //! (bloque "credits"), días/créditos restantes y los conteos de la
    //! VENTANA (tokens, peticiones, caché). Todo de la caché: sin red.
    private function drawProjection(dc as Graphics.Dc, cx as Lang.Number) as Void {
        // Geometría vertical desde la fuente: renglones a paso >= altura de
        // FONT_XTINY (en fr955: 78/99/120/141 y 168/188/208). Si en algún
        // dispositivo la pila no cupiera sobre el pie, se comprime el paso
        // (nunca por debajo de mayúsculas + 4 px) y se sube la cabecera.
        var pY = pageY(dc);
        var titleY = sc(TITLE_Y);
        var p1 = sc(KV_PITCH_1);
        var p2 = sc(KV_PITCH_2);
        if (p1 < mFh) {
            p1 = mFh;
        }
        if (p2 < mFh - 1) {
            p2 = mFh - 1;
        }
        var secGap = sc(SECTION_GAP);
        var head = mFh + sc(HAIR_GAP) + sc(KV_TOP_GAP);
        // de titleY al bottom de CACHÉ (celda completa) + 1 px sobre el pie
        var need = head + 4 * p1 + secGap + 2 * p2 + mFh;
        var avail = pY - sc1(1) - titleY;
        if (need > avail) {
            var minTitle = sc(TITLE_Y) / 2;
            var lift = need - avail;
            if (lift > titleY - minTitle) {
                lift = titleY - minTitle;
            }
            titleY -= lift;
            avail += lift;
        }
        if (need > avail) {
            var k = (avail - head - mFh) * 1.0 / (4 * p1 + secGap + 2 * p2);
            var minP = mCap + 4;
            p1 = (p1 * k).toNumber();
            p2 = (p2 * k).toNumber();
            secGap = (secGap * k).toNumber();
            if (p1 < minP) {
                p1 = minP;
            }
            if (p2 < minP) {
                p2 = minP;
            }
        }
        var hairY = titleY + mFh + sc(HAIR_GAP);
        var ritmoY = hairY + sc(KV_TOP_GAP);
        var proyY = ritmoY + p1;
        var verdictY = proyY + p1;
        var quedanY = verdictY + p1;
        var tokensY = quedanY + p1 + secGap;
        var peticY = tokensY + p2;
        var cacheY = peticY + p2;

        // Cabecera de marca: título + la ÚNICA hairline de la vista.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, titleY, Graphics.FONT_XTINY, "PROYECCIÓN",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - sc(HAIR_HALF), hairY, cx + sc(HAIR_HALF), hairY);

        var allowance = mState.allowance();
        var used = mState.used();

        // --- RITMO (créditos/día): used / días transcurridos del periodo.
        // Sin period_start en la caché (caché vieja): 30 días y "~".
        var ps = mState.periodStart();
        var endDay = mState.periodDay();
        var estRate = (ps == null);
        var elapsedDays = 30;
        if (!estRate) {
            var diff = QuotaStore.nowEpoch() - ps;
            elapsedDays = (diff < 0) ? 1 : diff / 86400;
            if (elapsedDays < 1) {
                elapsedDays = 1;            // periodo arrancado hoy: /1 día
            }
        }
        var rate = used * 1.0 / elapsedDays;

        // --- PROYECCIÓN a fin de periodo: ritmo x días TOTALES del periodo
        // (period_end - period_start; con period_start ausente, 30 días).
        var totalDays = 30;
        if (!estRate && endDay != null) {
            totalDays = endDay - ps / 86400;
            if (totalDays < 1) {
                totalDays = 1;
            }
        }
        var projection = rate * totalDays;

        var ritmoTxt = (estRate ? "~" : "") + QuotaStore.creditLabel(rate) + "/d";
        var proyTxt = QuotaStore.creditLabel(projection);

        // --- Veredicto: > allowance -> TE PASARÁS (rojo, con el exceso);
        // < 80 % -> VAS BIEN (verde); si no -> JUSTO (ámbar).
        var verdict;
        var vColor;
        if (allowance == null || allowance <= 0.0) {
            verdict = "—";
            vColor = Graphics.COLOR_LT_GRAY;
        } else if (projection > allowance) {
            verdict = "TE PASARÁS +"
                + QuotaStore.creditLabel(projection - allowance);
            vColor = Graphics.COLOR_RED;
        } else if (projection < allowance * 0.8) {
            verdict = "VAS BIEN";
            vColor = Graphics.COLOR_GREEN;
        } else {
            verdict = "JUSTO";
            vColor = Graphics.COLOR_YELLOW;
        }

        // --- QUEDAN: días hasta el reset + créditos restantes del periodo
        // (remaining de la API, o allowance - used si la API no lo trae).
        var days = QuotaStore.daysUntilReset(endDay);
        if (days != null && days < 0) {
            days = 0;                       // fecha pasada -> 0, nunca "-3 D"
        }
        var credLeft = mState.remaining();
        if (credLeft == null) {
            credLeft = allowance - used;
        }
        var credTxt = QuotaStore.creditLabel(credLeft);
        var dTxt = (days == null) ? null : days + " D";
        var quedanW = dc.getTextWidthInPixels(credTxt, Graphics.FONT_XTINY);
        if (dTxt != null) {
            quedanW += dc.getTextWidthInPixels(dTxt + " · ", Graphics.FONT_XTINY);
        }

        // --- Conteos de la VENTANA (30 días). Dato ausente -> "—".
        var tokTxt = QuotaStore.tokenLabel(mState.totTokens());
        var reqTxt = QuotaStore.tokenLabel(mState.totRequests());
        var cacheTxt = "—";
        if (mState.totTokens() != null && mState.totCached() != null
                && mState.totTokens() > 0) {
            var pct = (mState.totCached() * 1.0 / mState.totTokens() * 100.0
                + 0.5).toNumber();
            if (pct < 0) {
                pct = 0;
            }
            if (pct > 100) {
                pct = 100;
            }
            cacheTxt = pct + "%";
        }

        // --- Eje de la tabla: etiquetas a la derecha contra gx - g, valores
        // a la izquierda desde gx + g. El eje se desplaza para CENTRAR el
        // bloque (etiqueta más ancha + valor más ancho) en la pantalla.
        var labels = ["RITMO", "PROYECCIÓN", "QUEDAN", "TOKENS", "PETICIONES",
            "CACHÉ"];
        var values = [ritmoTxt, proyTxt, tokTxt, reqTxt, cacheTxt];
        var maxL = 0;
        for (var i = 0; i < labels.size(); i++) {
            var lw = dc.getTextWidthInPixels(labels[i] as Lang.String, Graphics.FONT_XTINY);
            if (lw > maxL) {
                maxL = lw;
            }
        }
        var maxV = quedanW;
        for (var i = 0; i < values.size(); i++) {
            var vw = dc.getTextWidthInPixels(values[i] as Lang.String, Graphics.FONT_XTINY);
            if (vw > maxV) {
                maxV = vw;
            }
        }
        var gx = cx + (maxL - maxV) / 2;

        drawKV(dc, ritmoY, gx, "RITMO", ritmoTxt, Graphics.COLOR_WHITE);
        drawKV(dc, proyY, gx, "PROYECCIÓN", proyTxt, Graphics.COLOR_WHITE);

        dc.setColor(vColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, verdictY, Graphics.FONT_XTINY, verdict,
            Graphics.TEXT_JUSTIFY_CENTER);

        drawKV(dc, quedanY, gx, "QUEDAN", "", Graphics.COLOR_WHITE);
        var x = gx + sc1(KV_GUTTER);
        if (dTxt != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, quedanY, Graphics.FONT_XTINY, dTxt,
                Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(dTxt, Graphics.FONT_XTINY);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, quedanY, Graphics.FONT_XTINY, " · ",
                Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(" · ", Graphics.FONT_XTINY);
            dc.setColor(severityColor(mState.usedFraction()),
                Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(x, quedanY, Graphics.FONT_XTINY, credTxt,
            Graphics.TEXT_JUSTIFY_LEFT);

        drawKV(dc, tokensY, gx, "TOKENS", tokTxt, Graphics.COLOR_WHITE);
        // "PETICIONES" es la etiqueta más larga: si no cabe a su altura de
        // la cuerda, sinónimo más corto en vez de recortar con "..".
        var reqLabel = "PETICIONES";
        if (gx - sc1(KV_GUTTER) - (cx - chordHalf(dc, peticY))
                < dc.getTextWidthInPixels(reqLabel, Graphics.FONT_XTINY)) {
            reqLabel = "LLAMADAS";
        }
        drawKV(dc, peticY, gx, reqLabel, reqTxt, Graphics.COLOR_WHITE);
        drawKV(dc, cacheY, gx, "CACHÉ", cacheTxt, Graphics.COLOR_WHITE);

        // Indicador de pantalla: 3/3.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, pY, Graphics.FONT_XTINY, "3/3",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------------------
    // Navegación interna (llamadas del delegate)
    // -------------------------------------------------------------------------

    //! DOWN (fr955: down -> nextPage): pagina el desglose; desde la ÚLTIMA
    //! página pasa a PROYECCIÓN. Devuelve false sólo en proyección, donde
    //! DOWN cierra el ciclo -> popView a la principal (el delegate lo hace).
    function onNextPressed() as Lang.Boolean {
        if (mScreen == 1) {
            return false;
        }
        if (mPage < pageCount() - 1) {
            mPage++;
            WatchUi.requestUpdate();
            return true;
        }
        mScreen = 1;
        WatchUi.requestUpdate();
        return true;
    }

    //! UP (fr955: up -> previousPage): pagina el desglose; en la página 1
    //! vuelve a la principal (popView). En proyección regresa al desglose
    //! (última página, por donde se entró).
    function onPrevPressed() as Lang.Boolean {
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
            disc = label.substring(idx, label.length());
            base = label.substring(0, idx);
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

//! Delegate de las pantallas 2/3 y 3/3: BACK vuelve a la principal; DOWN/UP
//! pagan el desglose y pasan de pantalla (última página -> proyección;
//! proyección DOWN -> principal por el ciclo; desglose pág. 1 UP ->
//! principal). SELECT se consume a propósito (aquí no hay acción: el
//! refresco manual sigue siendo cosa de la vista principal).
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

    //! Consumido: aquí SELECT no refresca (evita que el ENTER dispare
    //! acciones del sistema sobre esta vista pushed).
    function onSelect() as Lang.Boolean {
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
