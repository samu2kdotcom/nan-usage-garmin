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
// única en MAYÚSCULAS ("GLM5.3", "GLM5.3-F"; assignLabels nunca repite
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
// "—". Los renglones se estrechan con la cuerda del círculo (chordHalf):
// el ancho útil por fila decrece hacia el borde (margen >= 10 px + 4 px de
// aire interior), como subAvailWidth() en la vista principal.
//
// Paginación del desglose: 7 filas por página (la cabecera es fija); con más
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

    // --- geometría compartida (misma piel y centro 130,130 que la principal) ---
    private const TITLE_Y = 46;         // top de "DESGLOSE · 30 D" (46..67)
    private const TOTAL_Y = 70;         // top del total (70..91)
    private const HAIR_Y = 96;          // hairline 1 px bajo la cabecera
    private const ROW_FIRST_BASE = 116; // línea base fila 1; top = base - asc
    private const ROW_PITCH = 18;       // bases 116/134/152/170/188/206/224
    // Ancho de fila 68 (antes 66): libera sitio al cluster nombre+créditos+
    // tokens. Esquina de la fila/barra más baja (base 224, barY 228..229):
    // dx=68, dy=99 -> r=sqrt(68^2+99^2)=120.1, margen ~10 px al cristal.
    private const ROW_HALF = 68;        // filas de x=cx-68 a x=cx+68 (62..198)
    private const BAR_H = 2;            // barra fina (la principal usa 3)
    // Pie del indicador: 230 (antes 234) para que el combinado "1/2 · 2/3"
    // (~77 px -> esquinas a dx=38.5, dy=121 -> r=126.3) quede dentro del
    // círculo real; "3/3" y "2/3" caben de sobra.
    private const PAGE_Y = 230;         // top del indicador de página/pantalla
    private const ROWS_PER_PAGE = 7;    // caben 7 filas entre hairline y pie

    // --- geometría de la pantalla PROYECCIÓN ---
    // UNA hairline por vista (regla de marca): la sección de conteos se
    // separa de la de periodo sólo con aire (QUEDAN acaba en 162, TOKENS
    // arranca en 168). Filas a pitch 21/20: los textos son MAYÚSCULAS y
    // dígitos (sin descendentes), sin riesgo de solape de ink.
    private const PROJ_HAIR_Y = 72;     // hairline bajo "PROYECCIÓN"
    private const R_RITMO_Y = 78;       // RITMO      | ~123/d
    private const R_PROY_Y = 99;        // PROYECCIÓN | 8.1K
    private const R_VERDICT_Y = 120;    // TE PASARÁS +1.1K / VAS BIEN / JUSTO
    private const R_QUEDAN_Y = 141;     // QUEDAN     | 20 D · 3.1K
    private const R_TOKENS_Y = 168;     // TOKENS     | 156M
    private const R_PETIC_Y = 188;      // PETICIONES | 1.2K
    private const R_CACHE_Y = 208;      // CACHÉ      | 64%
    private const PAGE_PAD = 4;         // aire interior del half de cuerda

    private var mState;   //!< CreditState o null (instantánea de la caché)
    private var mPage;    //!< página del desglose, 0-based
    private var mScreen;  //!< 0 = DESGLOSE (2/3), 1 = PROYECCIÓN (3/3)
    private var mTokFont; //!< fuente pequeña de tokens (vectorial 13 px) o null

    function initialize() {
        View.initialize();
        mState = QuotaStore.getCachedState();
        mPage = 0;
        mScreen = 0;
        mTokFont = null;
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
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, TITLE_Y, Graphics.FONT_XTINY, "DESGLOSE · 30 D",
            Graphics.TEXT_JUSTIFY_CENTER);

        var total = QuotaStore.creditLabel(mState.used()) + " de "
            + QuotaStore.creditLabel(mState.allowance()) + " créditos";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, TOTAL_Y, Graphics.FONT_XTINY, total,
            Graphics.TEXT_JUSTIFY_CENTER);

        // Hairline de 1 px en DK_GRAY, mismo trazo (cx±74) que la principal.
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 74, HAIR_Y, cx + 74, HAIR_Y);
    }

    //! Página corriente de la lista: ETIQUETA única (LT_GRAY, MAYÚSCULAS,
    //! truncada conservando el discriminador "-F"/"-M"...) a la izquierda;
    //! a la derecha los créditos (WHITE) y, si caben, los TOKENS en gris y
    //! más pequeño ("2.1K · 156M"); bajo el texto, barra fina de pista
    //! DK_GRAY con relleno COLOR_PURPLE proporcional a la cuota sobre
    //! totals.credits (ventana).
    private function drawRows(dc as Graphics.Dc, cx as Lang.Number) as Void {
        var models = mState.models();
        var ascent = (0.78 * dc.getFontHeight(Graphics.FONT_XTINY)).toNumber();
        var left = cx - ROW_HALF;
        var right = cx + ROW_HALF;
        var span = 2 * ROW_HALF;
        var start = mPage * ROWS_PER_PAGE;

        for (var i = 0; i < ROWS_PER_PAGE; i++) {
            var idx = start + i;
            if (idx >= models.size()) {
                break;
            }
            var m = models[idx] as ModelCredit;
            if (m == null) {
                continue;
            }
            var baseY = ROW_FIRST_BASE + i * ROW_PITCH;
            var topY = baseY - ascent;
            var barY = baseY + 4;               // 120/138/156/174/192/210/228

            var credits = m.credits();
            var creditTxt = (credits == null) ? "—"
                : QuotaStore.creditLabel(credits);
            var creditW = dc.getTextWidthInPixels(creditTxt,
                Graphics.FONT_XTINY);

            // Tokens de la fila ("156M"), en gris y más pequeño, SI CABEN.
            // Escalera "si cabe" por fila (el nombre NUNCA se sacrifica):
            //   1. "2.1K · 156M" (cluster con separador de marca)
            //   2. "2.1K 156M"   (sin separador, sólo 2 px de aire)
            //   3. "2.1K"        (sin tokens: etiquetas largas)
            var tokTxt = (m.tokens() == null)
                ? null : QuotaStore.tokenLabel(m.tokens());
            var tokFont = tokFontSmall();
            var tokW = 0;
            var sepW = 0;
            if (tokTxt != null) {
                tokW = dc.getTextWidthInPixels(tokTxt, tokFont);
                sepW = dc.getTextWidthInPixels(" · ", tokFont);
            }
            // ancho mínimo de nombre para no truncar etiquetas cortas
            // ("GLM5.3" mide 55 px con FONT_XTINY en fr955)
            var NAME_MIN = 55;
            var tokMode = 0;            // 1 = con separador, 2 = sin separador
            if (tokTxt != null) {
                if (span - creditW - tokW - sepW - 6 - 2 - NAME_MIN >= 0) {
                    tokMode = 1;
                } else if (span - creditW - tokW - 2 - 6 - 2 - NAME_MIN >= 0) {
                    tokMode = 2;
                }
            }
            var tokBlockW = (tokMode == 1) ? tokW + sepW
                : ((tokMode == 2) ? tokW + 2 : 0);

            var nameAvail = span - creditW - tokBlockW - 6 - 2;
            var name = fitLabel(dc, m.label(), nameAvail);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, topY, Graphics.FONT_XTINY, name,
                Graphics.TEXT_JUSTIFY_LEFT);

            if (tokMode > 0) {
                // Cluster derecho: créditos blancos en XTINY y tokens en la
                // fuente pequeña, alineados por la línea de base. Con modo 1
                // los tokens van tras el separador " · " (gris); con modo 2,
                // tras 2 px de aire.
                var hTok = dc.getFontHeight(tokFont);
                var tokTop = topY
                    + (0.78 * (dc.getFontHeight(Graphics.FONT_XTINY) - hTok))
                        .toNumber();
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
            dc.fillRectangle(left, barY, span, BAR_H);
            var fillW = (span * f).toNumber();
            if (fillW < 1 && f > 0.0) {
                fillW = 1;
            }
            if (fillW > 0) {
                dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(left, barY, fillW, BAR_H);
            }
        }
    }

    //! Fuente PEQUEÑA para los tokens: vectorial "RobotoCondensed-Regular"
    //! 13 px (cara verificada en el fr955, simulator.json) con fallback a
    //! FONT_XTINY; el display nunca asume que sea más pequeña (el ancho se
    //! mide y el token se omite si no cabe).
    private function tokFontSmall() as Graphics.FontType {
        if (mTokFont == null) {
            var f = null;
            // CRASH fr255: sin getVectorFont en el dispositivo la llamada es
            // un error fatal no capturable; comprobar el símbolo antes.
            if (Graphics has :getVectorFont) {
                try {
                    f = Graphics.getVectorFont(
                        { :face => "RobotoCondensed-Regular", :size => 13 });
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
        dc.drawText(cx, PAGE_Y, Graphics.FONT_XTINY, txt,
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
        dc.drawText(cx, cy + 34, Graphics.FONT_XTINY, "pulsa BACK para volver",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Páginas del desglose (>= 1).
    private function pageCount() as Lang.Number {
        var n = (mState == null) ? 0 : mState.models().size();
        var pages = (n + ROWS_PER_PAGE - 1) / ROWS_PER_PAGE;
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
        var rSafe = dc.getWidth() / 2 - 10;
        var h = dc.getFontHeight(Graphics.FONT_XTINY);
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
            - PAGE_PAD;
        return (half > 0) ? half : 0;
    }

    //! Renglón etiqueta (LT_GRAY, izquierda) / valor (color dado, derecha),
    //! ambos anclados a la cuerda del renglón.
    private function drawKV(dc as Graphics.Dc, topY as Lang.Number,
            label as Lang.String, value as Lang.String,
            valueColor as Graphics.ColorType) as Void {
        var cx = dc.getWidth() / 2;
        var half = chordHalf(dc, topY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - half, topY, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + half, topY, Graphics.FONT_XTINY, value,
            Graphics.TEXT_JUSTIFY_RIGHT);
    }

    //! Pantalla PROYECCIÓN (3/3): ritmo, proyección y veredicto del PERIODO
    //! (bloque "credits"), días/créditos restantes y los conteos de la
    //! VENTANA (tokens, peticiones, caché). Todo de la caché: sin red.
    private function drawProjection(dc as Graphics.Dc, cx as Lang.Number) as Void {
        // Cabecera de marca: título + la ÚNICA hairline de la vista.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, TITLE_Y, Graphics.FONT_XTINY, "PROYECCIÓN",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - 74, PROJ_HAIR_Y, cx + 74, PROJ_HAIR_Y);

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

        drawKV(dc, R_RITMO_Y, "RITMO",
            (estRate ? "~" : "") + QuotaStore.creditLabel(rate) + "/d",
            Graphics.COLOR_WHITE);
        drawKV(dc, R_PROY_Y, "PROYECCIÓN", QuotaStore.creditLabel(projection),
            Graphics.COLOR_WHITE);

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
        dc.setColor(vColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, R_VERDICT_Y, Graphics.FONT_XTINY, verdict,
            Graphics.TEXT_JUSTIFY_CENTER);

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
        var credW = dc.getTextWidthInPixels(credTxt, Graphics.FONT_XTINY);
        var sepW = dc.getTextWidthInPixels(" · ", Graphics.FONT_XTINY);
        var half = chordHalf(dc, R_QUEDAN_Y);
        var right = cx + half;
        if (days == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(right, R_QUEDAN_Y, Graphics.FONT_XTINY, credTxt,
                Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(right - credW - sepW, R_QUEDAN_Y, Graphics.FONT_XTINY,
                days + " D", Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(right - credW, R_QUEDAN_Y, Graphics.FONT_XTINY, " · ",
                Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(severityColor(mState.usedFraction()),
                Graphics.COLOR_TRANSPARENT);
            dc.drawText(right, R_QUEDAN_Y, Graphics.FONT_XTINY, credTxt,
                Graphics.TEXT_JUSTIFY_RIGHT);
        }

        // --- Segunda sección: conteos de la VENTANA (30 días). Dato
        // ausente -> "—" (tokenLabel ya lo resuelve para null).
        drawKV(dc, R_TOKENS_Y, "TOKENS", QuotaStore.tokenLabel(mState.totTokens()),
            Graphics.COLOR_WHITE);
        drawKV(dc, R_PETIC_Y, "PETICIONES",
            QuotaStore.tokenLabel(mState.totRequests()), Graphics.COLOR_WHITE);

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
        drawKV(dc, R_CACHE_Y, "CACHÉ", cacheTxt, Graphics.COLOR_WHITE);

        // Indicador de pantalla: 3/3.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, PAGE_Y, Graphics.FONT_XTINY, "3/3",
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
    //! CONSERVANDO el discriminador ("-F"/"-M"/"-P"/...): dos filas jamás se
    //! ven iguales tras el recorte ("QWEN..-F" vs "QWEN..-M"). Si ni el
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
