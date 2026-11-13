using Toybox.Lang;
using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Communications;
using Toybox.System;
using Toybox.Time;

//! Un modelo del desglose de créditos de la VENTANA DE 30 DÍAS
//! (totals.by_model de GET /v1/usage?limit=1). Ya no hay topes de tokens:
//! la cuenta de NaN va por CRÉDITOS, y este desglose cubre la ventana
//! (start_date..end_date del reporte), no el periodo de facturación.
//!
//! Desglose por modelos (NaNUsageBreakdownView): lista SOLO los modelos con
//! créditos > 0 (los gratuitos cuentan en los totales pero no se listan,
//! filterBilled()). Cada fila muestra su etiqueta única (assignLabels), su
//! crédito y sus TOKENS (total_tokens); api_requests/cached_tokens viajan
//! crudos para los totales de la ventana. Pueden ser null (cachés del
//! formato anterior o payload sin esas claves) y el display usa "—".
class ModelCredit {

    var mModel;      //!< p.ej. "glm5.3"
    var mCredits;    //!< Float: créditos consumidos por el modelo en la ventana
    var mTokens;     //!< Number/Long: total_tokens del modelo, o null si falta
    var mRequests;   //!< Number/Long: api_requests del modelo, o null si falta
    var mCached;     //!< Number/Long: cached_tokens del modelo, o null si falta
    var mLabel;      //!< etiqueta corta ÚNICA de la lista (assignLabels)

    function initialize(model, credits, tokens, requests, cached) {
        mModel = model;
        mCredits = credits;
        mTokens = tokens;
        mRequests = requests;
        mCached = cached;
    }

    function model() { return mModel; }
    function credits() { return mCredits; }
    function tokens() { return mTokens; }
    function apiRequests() { return mRequests; }
    function cachedTokens() { return mCached; }

    //! Crédito de este modelo como fracción del TOTAL de la ventana
    //! (totals.credits, p.ej. 3884.6), NUNCA del allowance del periodo de
    //! facturación (7000): así las filas no pueden parecer que suman el héroe.
    //! Tolerante a null (modelo sin cifra en la caché/API): 0.0.
    function windowFraction(windowTotal as Lang.Float or Null) as Lang.Float {
        if (windowTotal == null || windowTotal <= 0.0 || mCredits == null) {
            return 0.0;
        }
        var f = mCredits * 1.0 / windowTotal;
        if (f < 0.0) { f = 0.0; }
        if (f > 1.0) { f = 1.0; }
        return f;
    }

    //! Etiqueta CORTA y ÚNICA de la lista (p.ej. "GLM5.3F"); la calcula
    //! QuotaStore.assignLabels() sobre la lista COMPLETA (desambiguación de
    //! prefijos repetidos) y viaja con el objeto. Fallback defensivo: el
    //! nombre crudo del modelo si por algún motivo no tuviera etiqueta.
    function label() {
        if (mLabel == null || mLabel.equals("")) {
            return mModel;
        }
        return mLabel;
    }

    function setLabel(l as Lang.String) as Void {
        mLabel = l;
    }
}


//! Instantánea de la ventana de créditos de la cuenta NaN: bloque "credits"
//! (allowance/used/remaining/period_end/frozen del PERIODO de facturación)
//! más "totals.credits" y "by_model" de la ventana de 30 días. El héroe es
//! used/allowance; el desglose por modelo vive en la ventana.
class CreditState {

    var mAllowance;    //!< Float: créditos del periodo (p.ej. 7000.0)
    var mUsed;         //!< Float: créditos usados del periodo (p.ej. 3884.6)
    var mRemaining;    //!< Float or null
    var mFrozen;       //!< Boolean: cuenta congelada -> aviso en vez del badge
    var mPeriodDay;    //!< Number: día civil (días desde epoch) de period_end
    var mWindowTotal;  //!< Float or null: totals.credits (ventana de 30 días)
    var mModels;       //!< Array<ModelCredit> filtrado (créditos > 0),
                       //!< pre-ordenado por créditos desc y CON etiquetas
    var mPeriodStart;  //!< Number or null: epoch (s) del inicio del periodo
                       //!< (period_start a las 00:00 UTC); null en cachés viejas
    var mTotTokens;    //!< Number/Long or null: total_tokens de la ventana
    var mTotRequests;  //!< Number/Long or null: api_requests de la ventana
    var mTotCached;    //!< Number/Long or null: cached_tokens de la ventana

    function initialize(allowance, used, remaining, frozen, periodDay,
            windowTotal, models, periodStart, totTokens, totRequests, totCached) {
        mAllowance = allowance;
        mUsed = used;
        mRemaining = remaining;
        mFrozen = frozen;
        mPeriodDay = periodDay;
        mWindowTotal = windowTotal;
        mModels = models;
        mPeriodStart = periodStart;
        mTotTokens = totTokens;
        mTotRequests = totRequests;
        mTotCached = totCached;
    }

    //! Fracción del allowance ya consumida (héroe, arco y semáforo), 0..1.
    function usedFraction() as Lang.Float {
        if (mAllowance == null || mAllowance <= 0.0 || mUsed == null) {
            return 0.0;
        }
        var f = mUsed * 1.0 / mAllowance;
        if (f < 0.0) { f = 0.0; }
        if (f > 1.0) { f = 1.0; }
        return f;
    }

    function allowance() { return mAllowance; }
    function used() { return mUsed; }
    function remaining() { return mRemaining; }
    function frozen() { return mFrozen; }
    function periodDay() { return mPeriodDay; }
    function windowTotal() { return mWindowTotal; }
    function models() { return mModels; }
    function periodStart() { return mPeriodStart; }
    function totTokens() { return mTotTokens; }
    function totRequests() { return mTotRequests; }
    function totCached() { return mTotCached; }
}


//! Fetches /v1/usage?limit=1 (misma key sk- con Bearer, mismo permiso
//! Communications) y cachea la instantánea en Application.Storage para que
//! la glance y las aperturas sin red pinten la última known data.
//!
//! CAMBIO DE FUENTE: antes era /api/usage/quota (topes de tokens por modelo,
//! una agregación que mostraba 13 % cuando el consumo real era 55 %). La
//! cuenta va por CRÉDITOS: ahora se parsea el bloque "credits" y el desglose
//! "totals.by_model". Las claves viejas "nan_models"/"nan_period_day" quedan
//! huérfanas en Storage (sin migración: cambia el formato, cambia la clave);
//! "nan_fetch_epoch" SE CONSERVA con el mismo nombre porque la glance la lee.
class QuotaStore {

    // Instantánea de créditos serializada (ver serializeState()).
    public static var CREDITS_KEY = "nan_credits";
    // B1: epoch de PARED en segundos UNIX (Time.now().value()), NO
    // System.getTimer() (ms desde boot: tras un reboot la edad mentía).
    // Se mantiene el literal "nan_fetch_epoch": la glance lo lee de Storage.
    public static var FETCH_KEY = "nan_fetch_epoch";
    // B2: epoch de pared del último INTENTO (éxito o fallo). El anti-rebote /
    // backoff de onShow() usa esta marca, no sólo la del éxito.
    public static var ATTEMPT_KEY = "nan_attempt_epoch";
    // B3: texto del error del último intento (se borra cuando hay un éxito).
    public static var LAST_ERR_KEY = "nan_last_err";
    // B4: true si el último intento acabó en 401 (key revocada o mal
    // tecleada); SELECT abre el editor para corregirla y un éxito lo borra.
    public static var AUTH_ERR_KEY as Lang.String = "nan_auth_err";

    private static var sCallback = null;

    //! Conversión JSON -> Float a prueba de tipos. El parser JSON de CIQ
    //! devuelve Long/Number para enteros ("allowance": 7000) y Double/Float
    //! para decimales ("used": 3884.6); además Number es un INT de 32 bits,
    //! así que los enteros grandes llegan como Long de 64. instanceof no
    //! lanza (el cast "as" sí: UnexpectedType), y "* 1.0" fuerza la
    //! aritmética flotante con el mismo idioma que usa el resto del código.
    public static function asFloat(v) as Lang.Float or Null {
        if (v == null) {
            return null;
        }
        if (v instanceof Lang.Float || v instanceof Lang.Double
                || v instanceof Lang.Number || v instanceof Lang.Long) {
            return v * 1.0;
        }
        return null;
    }

    //! Formato compacto de créditos compartido por la vista y sus filas:
    //! < 1000 -> entero ("320"); >= 1000 -> una decimal y "K" ("3.9K",
    //! "7.0K"). 3884.6 -> "3.9K", 7000 -> "7.0K", 319.5 -> "320".
    public static function creditLabel(v as Lang.Float) as Lang.String {
        if (v == null) {
            return "?";
        }
        if (v < 0.0) {
            v = 0.0;
        }
        if (v < 1000.0) {
            return (v + 0.5).toNumber().toString();   // round half-up y trunco
        }
        var tenths = (v / 100.0 + 0.5).toNumber();    // décimas de K redondeadas
        return (tenths / 10) + "." + (tenths % 10) + "K";
    }

    //! Formato compacto de CONTEOS (tokens y peticiones): < 1000 entero;
    //! después una decimal con K/M/B y SIN ".0" (156.0M -> "156M",
    //! 2.1M -> "2.1M"). 156000000 -> "156M", 1234567 -> "1.2M". Null o no
    //! numérico -> "—" (manejo de dato ausente).
    public static function tokenLabel(v) as Lang.String {
        if (!QuotaStore.isNumeric(v)) {
            return "—";
        }
        var f = v * 1.0;
        if (f < 0.0) {
            f = 0.0;
        }
        if (f < 1000.0) {
            return (f + 0.5).toNumber().toString();
        }
        var suffix;
        var tenths;
        if (f < 1000000.0) {
            suffix = "K";
            tenths = (f / 100.0 + 0.5).toNumber();
        } else if (f < 1000000000.0) {
            suffix = "M";
            tenths = (f / 100000.0 + 0.5).toNumber();
        } else {
            suffix = "B";
            tenths = (f / 100000000.0 + 0.5).toNumber();
        }
        if (tenths % 10 == 0) {
            return (tenths / 10) + suffix;
        }
        return (tenths / 10) + "." + (tenths % 10) + suffix;
    }

    //! true si `v` es un valor numérico del parser JSON/Storage (Number int32,
    //! Long int64, Float o Double); false en null, String, Boolean, etc.
    public static function isNumeric(v) as Lang.Boolean {
        if (v == null) {
            return false;
        }
        return v instanceof Lang.Float || v instanceof Lang.Double
            || v instanceof Lang.Number || v instanceof Lang.Long;
    }

    //! Mayúsculas ASCII: Lang.String.toUpperCase() no está disponible en el
    //! SDK 9.3.0 del fr955 (los nombres de modelo son ASCII, basta una tabla
    //! con find()). ÚNICA copia: las vistas usan las etiquetas de assignLabels.
    public static function upperAscii(s as Lang.String) as Lang.String {
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

    //! Minúsculas ASCII (gemela de upperAscii) por si la API mezclara cajas.
    private static function lowerAscii(s as Lang.String) as Lang.String {
        var lower = "abcdefghijklmnopqrstuvwxyz";
        var upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        var out = "";
        for (var i = 0; i < s.length(); i++) {
            var ch = s.substring(i, i + 1);
            if (ch == null) {
                break;
            }
            var idx = upper.find(ch);
            out += (idx == null || idx < 0) ? ch : lower.substring(idx, idx + 1);
        }
        return out;
    }

    //! Abreviatura de la FAMILIA del modelo. Las de hasta 4-5 letras se
    //! quedan tal cual (GLM, KIMI, MIMO, LLAMA); las largas se acortan
    //! (deepseek -> DS) y qwen pasa a QW (es la más repetida en la lista). Familia desconocida y larga: sus 4 primeras letras.
    private static function familyAbbr(f as Lang.String) as Lang.String {
        var keys = ["deepseek", "minimax", "hunyuan", "mistral", "gemini",
            "claude", "nemotron", "baichuan", "doubao", "longcat", "magistral",
            "codestral", "devstral", "qwen"];
        var vals = ["DS", "MM", "HY", "MIS", "GEM", "CL", "NEMO", "BC", "DB",
            "LC", "MAG", "COD", "DEV", "QW"];
        for (var i = 0; i < keys.size(); i++) {
            if (f.equals(keys[i])) {
                return vals[i];
            }
        }
        var u = QuotaStore.upperAscii(f);
        return (u.length() > 5) ? u.substring(0, 4) : u;
    }

    //! Abreviatura de una palabra de VARIANTE (flash -> F, pro -> PRO...).
    //! Desconocida: sus 3 primeras letras en mayúsculas.
    private static function variantAbbr(v as Lang.String) as Lang.String {
        var keys = ["flash", "pro", "max", "mini", "lite", "turbo", "plus",
            "air", "thinking", "think", "instruct", "coder", "chat", "preview",
            "exp", "reasoner", "omni", "ultra", "nano", "large", "medium",
            "small", "vision", "versatile", "latest", "base", "distill"];
        var vals = ["F", "PRO", "MAX", "MINI", "L", "T", "PLUS", "AIR", "TH",
            "TH", "I", "C", "CHAT", "P", "X", "R", "O", "U", "N", "L", "M",
            "S", "V", "", "", "", "D"];
        for (var i = 0; i < keys.size(); i++) {
            if (v.equals(keys[i])) {
                return vals[i];
            }
        }
        var u = QuotaStore.upperAscii(v);
        return (u.length() > 3) ? u.substring(0, 3) : u;
    }

    //! Etiqueta COMPACTA de un id de modelo, sin puntos suspensivos en lo
    //! posible: familia abreviada + versión + variantes abreviadas, todo
    //! pegado. Ejemplos: "deepseek4.1flash" / "deepseek-v4.1-flash" ->
    //! "DS4.1F"; "deepseek4.1pro" -> "DS4.1PRO"; "glm5.3-flash" ->
    //! "GLM5.3F"; "hunyuan-4" -> "HY4"; "kimi-k3" -> "KIMI-K3"; "minimax-m2"
    //! -> "MM-M2"; "qwen3-235b-a22b-instruct-2507" -> "QW3I".
    //! Reglas: se ignora el prefijo de proveedor ("org/"); la "v" pegada a
    //! la versión cae (v4 -> 4); los tamaños ("235b", "a22b") y las fechas
    //! (números de >= 4 cifras sin punto) se descartan; una letra pegada a
    //! un número que no sea "v" (k3, m2, r1) forma parte de la versión y va
    //! tras guion si la etiqueta acaba en letra.
    public static function shortLabel(model as Lang.String) as Lang.String {
        if (model == null) {
            return "";
        }
        var s = QuotaStore.lowerAscii(model) as Lang.String;
        var slash = s.find("/");
        while (slash != null && slash >= 0 && slash + 1 < s.length()) {
            s = s.substring(slash + 1, s.length()) as Lang.String;
            slash = s.find("/");
        }
        // Tramos: [tipo, texto, pegado-al-anterior] con tipo 0 = letras,
        // 1 = número (dígitos y puntos); cualquier otro carácter separa.
        var runs = [];
        var cur = "";
        var curType = -1;
        var attached = false;
        var sep = false;
        var chars = s.toCharArray();
        for (var i = 0; i <= chars.size(); i++) {
            var t = -1;
            var c = null;
            if (i < chars.size()) {
                c = chars[i];
                var n = (c as Lang.Char).toNumber();
                if (n >= 97 && n <= 122) {
                    t = 0;
                } else if ((n >= 48 && n <= 57) || (n == 46 && curType == 1)) {
                    t = 1;
                }
            }
            if (t != curType || t == -1) {
                if (curType >= 0 && cur.length() > 0) {
                    runs.add([curType, cur, attached]);
                }
                attached = (t >= 0 && curType >= 0 && !sep);
                sep = (t == -1);
                cur = "";
                curType = t;
            }
            if (t >= 0) {
                cur += (c as Lang.Char).toString();
            }
        }
        if (runs.size() == 0) {
            return QuotaStore.upperAscii(model);
        }

        var out = "";
        var start = 0;
        if (runs[0][0] == 0) {
            out = QuotaStore.familyAbbr(runs[0][1]);
            start = 1;
        }
        var prefix = "";
        var k = start;
        while (k < runs.size()) {
            var r = runs[k];
            var txt = r[1] as Lang.String;
            var nxt = (k + 1 < runs.size()) ? runs[k + 1] : null;
            if (r[0] == 0) {
                // Letra suelta pegada a un número que la sigue: prefijo de
                // versión (v cae; k/m/r... se conservan).
                if (txt.length() == 1 && nxt != null && nxt[0] == 1
                        && nxt[2] == true) {
                    prefix = txt.equals("v") ? "" : QuotaStore.upperAscii(txt);
                    k++;
                    continue;
                }
                out += QuotaStore.variantAbbr(txt);
                k++;
                continue;
            }
            // Número: tamaño ("235b"/"a22b") o fecha (>= 4 cifras sin punto)
            // -> se descarta junto con su prefijo.
            var isSize = (nxt != null && nxt[0] == 0 && nxt[2] == true
                && (nxt[1].equals("b") || nxt[1].equals("m")
                    || nxt[1].equals("k")));
            if (isSize) {
                prefix = "";
                k += 2;
                continue;
            }
            if (txt.find(".") == null && txt.length() >= 4) {
                prefix = "";
                k++;
                continue;
            }
            var piece = prefix + txt;
            if (prefix.length() > 0 && QuotaStore.endsWithLetter(out)) {
                out += "-";
            }
            out += piece;
            prefix = "";
            k++;
        }
        if (out.length() == 0) {
            return QuotaStore.upperAscii(model);
        }
        return out;
    }

    private static function endsWithLetter(s as Lang.String) as Lang.Boolean {
        if (s.length() == 0) {
            return false;
        }
        var n = s.toCharArray()[s.length() - 1].toNumber();
        return (n >= 65 && n <= 90) || (n >= 97 && n <= 122);
    }

    //! Asigna a cada ModelCredit de la lista una etiqueta corta (MAYÚSCULAS)
    //! y ÚNICA con shortLabel() ("glm5.3" -> "GLM5.3", "glm5.3-flash" ->
    //! "GLM5.3F", "deepseek-v4" -> "DS4"). Garantía: NUNCA dos etiquetas
    //! iguales en la misma lista: si dos ids compactan igual, la segunda y
    //! siguientes se numeran ("DS4", "DS4-2").
    public static function assignLabels(models as Lang.Array) as Void {
        var n = models.size();
        if (n == 0) {
            return;
        }
        var labels = [];
        for (var i = 0; i < n; i++) {
            var m = models[i] as ModelCredit;
            labels.add((m == null) ? "" : QuotaStore.shortLabel(m.model()));
        }
        for (var i = 0; i < n; i++) {
            if (labels[i].equals("")) {
                continue;
            }
            var seq = 1;
            for (var j = i + 1; j < n; j++) {
                if (labels[j].equals(labels[i])) {
                    // siguiente sufijo libre en TODA la lista
                    var cand = labels[i];
                    var free = false;
                    while (!free) {
                        seq++;
                        cand = labels[i] + "-" + seq;
                        free = true;
                        for (var q = 0; q < n; q++) {
                            if (labels[q].equals(cand)) {
                                free = false;
                                break;
                            }
                        }
                    }
                    labels[j] = cand;
                }
            }
        }
        for (var i = 0; i < n; i++) {
            var m = models[i] as ModelCredit;
            if (m != null) {
                m.setLabel(labels[i]);
            }
        }
    }

    //! Quita de la lista los modelos SIN consumo (credits == null o <= 0:
    //! planes gratuitos). Se siguen usando para los TOTALES (que vienen del
    //! bloque "totals" de la API o se sumaron antes de filtrar), sólo dejan
    //! de LISTARSE. Devuelve un array nuevo; la entrada no se toca.
    public static function filterBilled(models as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < models.size(); i++) {
            var m = models[i] as ModelCredit;
            if (m == null) {
                continue;
            }
            var c = m.credits();
            if (c == null || c <= 0.0) {
                continue;
            }
            out.add(m);
        }
        return out;
    }

    //! Reads the cached snapshot; returns a CreditState or null.
    public static function getCachedState() as CreditState or Null {
        var raw = Application.Storage.getValue(QuotaStore.CREDITS_KEY);
        if (!(raw instanceof Lang.Dictionary)) {
            return null;
        }
        var d = raw as Lang.Dictionary;
        var allowance = QuotaStore.asFloat(d.get("a"));
        var used = QuotaStore.asFloat(d.get("u"));
        if (allowance == null || used == null) {
            return null;
        }
        var models = [];
        var mRaw = d.get("m");
        if (mRaw instanceof Lang.Array) {
            for (var i = 0; i < mRaw.size(); i++) {
                var eV = mRaw[i];
                if (!(eV instanceof Lang.Dictionary)) {
                    continue;
                }
                var e = eV as Lang.Dictionary;
                var name = e.get("n") as Lang.String;
                var credits = QuotaStore.asFloat(e.get("c"));
                // Compatibilidad de arranque: una caché ANTERIOR (o una
                // entrada sin "tk"/"rq"/"ca") no debe romper nada: los campos
                // extra llegan null y el desglose pinta "—" en lo que falte.
                // El nombre es lo único imprescindible para listar el modelo.
                if (name == null) {
                    continue;
                }
                models.add(new ModelCredit(name, credits,
                    e.get("tk"), e.get("rq"), e.get("ca")));
            }
        }
        var frozenV = d.get("f");
        var frozen = false;
        if (frozenV instanceof Lang.Boolean) {
            frozen = frozenV as Lang.Boolean;
        }

        // period_start en epoch (s); las cachés viejas no lo traen -> null y
        // la pantalla de PROYECCIÓN estima el ritmo con 30 días (~).
        var periodStart = null;
        if (QuotaStore.isNumeric(d.get("ps"))) {
            periodStart = d.get("ps");
        }

        // Totales de la ventana (tokens/peticiones/caché): claves "tt"/"ar"/
        // "ct". CACHÉS VIEJAS sin ellas: se suman las entradas tk/rq/ca de
        // TODOS los modelos ANTES de filtrar los gratuitos (cuentan igual).
        var totTokens = QuotaStore.isNumeric(d.get("tt")) ? d.get("tt") : null;
        var totRequests = QuotaStore.isNumeric(d.get("ar")) ? d.get("ar") : null;
        var totCached = QuotaStore.isNumeric(d.get("ct")) ? d.get("ct") : null;
        if (totTokens == null || totRequests == null || totCached == null) {
            var sT = 0;
            var sR = 0;
            var sC = 0;
            var anyT = false;
            var anyR = false;
            var anyC = false;
            for (var i = 0; i < models.size(); i++) {
                var sm = models[i] as ModelCredit;
                if (sm == null) {
                    continue;
                }
                if (sm.tokens() != null) {
                    sT += sm.tokens();
                    anyT = true;
                }
                if (sm.apiRequests() != null) {
                    sR += sm.apiRequests();
                    anyR = true;
                }
                if (sm.cachedTokens() != null) {
                    sC += sm.cachedTokens();
                    anyC = true;
                }
            }
            if (totTokens == null && anyT) {
                totTokens = sT;
            }
            if (totRequests == null && anyR) {
                totRequests = sR;
            }
            if (totCached == null && anyC) {
                totCached = sC;
            }
        }

        // Filtrado de modelos sin consumo + etiquetas únicas (la lista que
        // viaja en el estado ya NO contiene gratuitos ni duplicados visuales).
        models = QuotaStore.filterBilled(models);
        QuotaStore.assignLabels(models);

        return new CreditState(allowance, used, QuotaStore.asFloat(d.get("r")),
            frozen, d.get("d"), QuotaStore.asFloat(d.get("t")), models,
            periodStart, totTokens, totRequests, totCached);
    }

    //! Epoch de pared (segundos UNIX) AHORA. B1: System.getTimer() es ms desde
    //! el boot y miente tras un reboot; Time.now().value() es tiempo de pared.
    public static function nowEpoch() as Lang.Number {
        return Time.now().value();
    }

    //! Epoch de pared (s) del último fetch CON ÉXITO, 0 cuando nunca se ha
    //! traído nada.
    public static function getLastFetchEpoch() as Lang.Number {
        var v = Application.Storage.getValue(QuotaStore.FETCH_KEY);
        if (v == null) {
            return 0;
        }
        return v;
    }

    //! Epoch de pared (s) del último INTENTO (éxito o fallo), 0 si nunca.
    //! Es la marca que usa el anti-rebote/backoff de onShow() (B2).
    public static function getLastAttemptEpoch() as Lang.Number {
        var v = Application.Storage.getValue(QuotaStore.ATTEMPT_KEY);
        if (v == null) {
            return 0;
        }
        return v;
    }

    //! Texto del error del último intento, o null si el último intento fue
    //! éxito (B3: el aviso ámbar sobrevive a reabrir la vista).
    public static function getLastErr() {
        return Application.Storage.getValue(QuotaStore.LAST_ERR_KEY);
    }

    //! true si hay una API key utilizable en Properties: no nula y con el
    //! MISMO umbral de longitud que refresh() (>= 8). La comparten el hint
    //! del estado vacío, el delegate (SELECT/MENU) y refresh().
    public static function hasApiKey() as Lang.Boolean {
        var key = Properties.getValue("api_key") as Lang.String;
        return key != null && key.length() >= 8;
    }

    //! true SOLO si el último intento acabó en 401 (key revocada o mal
    //! tecleada). Null-safe: sin marca en Storage, o con un valor que no sea
    //! el booleano true, devuelve false.
    public static function hasAuthError() as Lang.Boolean {
        var v = Application.Storage.getValue(QuotaStore.AUTH_ERR_KEY) as Lang.Boolean;
        return v != null && v;
    }

    //! Guarda la API key tecleada EN EL RELOJ (sideload por USB: no hay
    //! editor de ajustes de Garmin Connect). Valida el mismo umbral de
    //! refresh(); si no vale, deja "Key demasiado corta" como último error
    //! (el estado vacío lo muestra) y devuelve false SIN tocar Properties.
    //! Si vale, la persiste y borra "Falta la API key" y la marca de 401
    //! (B3/B4, las claves de fail()/getLastErr() y de hasAuthError()).
    public static function saveApiKey(key as Lang.String) as Lang.Boolean {
        if (key == null || key.length() < 8) {
            Application.Storage.setValue(QuotaStore.LAST_ERR_KEY as Lang.String,
                "Key demasiado corta");
            return false;
        }
        Properties.setValue("api_key", key);
        // B3/B4: el cast evita el aviso por las claves de Storage sin tipo.
        Application.Storage.deleteValue(QuotaStore.LAST_ERR_KEY as Lang.String);
        Application.Storage.deleteValue(QuotaStore.AUTH_ERR_KEY as Lang.String);
        return true;
    }

    //! Fires a request to the NaN Cloud API. The callback receives
    //! (state as CreditState or Null, error as String or Null).
    public static function refresh(callback as Method(state as CreditState or Null, err as Lang.String or Null)) {
        QuotaStore.sCallback = callback;

        // B2: TODO intento (incluso el que acaba en "Falta la API key") se
        // marca al INICIAR; en fail() se re-escribe al concluir. Así el
        // anti-rebote de onShow() no re-dispara la red en cada apertura.
        Application.Storage.setValue(QuotaStore.ATTEMPT_KEY, QuotaStore.nowEpoch());

        if (!QuotaStore.hasApiKey()) {
            QuotaStore.fail("Falta la API key");
            return;
        }
        var key = Properties.getValue("api_key") as Lang.String;

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Authorization" => "Bearer " + key },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        var receptor = new QuotaStore();
        Communications.makeWebRequest(
            "https://api.nan.builders/v1/usage?limit=1",
            null,
            options,
            receptor.method(:onResponse)
        );
    }

    function onResponse(responseCode as Lang.Number, data as Null or Lang.ByteArray or Lang.Dictionary or Lang.String or Toybox.PersistedContent.Iterator) as Void {
        if (responseCode != 200 || data == null) {
            var msg = "HTTP " + responseCode;
            if (responseCode == 401) {
                // B4: key revocada o mal tecleada -> SELECT abrirá el editor
                // para corregirla; la marca se borra en el próximo éxito.
                Application.Storage.setValue(QuotaStore.AUTH_ERR_KEY as Lang.String, true);
                msg = "API key rechazada";
            } else if (responseCode == -300) {
                msg = "Sin conexión";
            } else if (responseCode == -2 || responseCode == -104) {
                msg = "Sin móvil/BLE";
            }
            QuotaStore.fail(msg);
            return;
        }
        QuotaStore.parseSnapshot(data as Lang.Dictionary);
    }

    //! Parses the /v1/usage payload and refreshes the cache.
    public static function parseSnapshot(data as Lang.Dictionary) {
        var state = QuotaStore.stateFromJson(data);
        if (state == null) {
            // HTTP 200 con una forma inesperada (la API cambió): fallo blando,
            // se conserva la caché anterior, igual que con un error HTTP.
            QuotaStore.fail("Respuesta inesperada");
            return;
        }
        Application.Storage.setValue(QuotaStore.CREDITS_KEY, QuotaStore.serializeState(state));
        // B1: epoch de PARED en segundos (sobrevive a reboots), no System.getTimer().
        Application.Storage.setValue(QuotaStore.FETCH_KEY, QuotaStore.nowEpoch());
        // B3: éxito -> el aviso de error persistido desaparece.
        Application.Storage.deleteValue(QuotaStore.LAST_ERR_KEY);
        // B4: y la marca de 401: la key vuelve a ser válida.
        Application.Storage.deleteValue(QuotaStore.AUTH_ERR_KEY as Lang.String);

        if (QuotaStore.sCallback != null) {
            QuotaStore.sCallback.invoke(state, null);
        }
    }

    //! Builds a CreditState from the /v1/usage JSON. Devuelve null si falta
    //! el bloque "credits" (allowance y used son imprescindibles) o si el
    //! payload no es un diccionario; los demás bloques degradan a null/[].
    public static function stateFromJson(data as Lang.Dictionary) as CreditState or Null {
        if (data == null) {
            return null;
        }

        var crV = data.get("credits");
        if (!(crV instanceof Lang.Dictionary)) {
            return null;
        }
        var cr = crV as Lang.Dictionary;

        var allowance = QuotaStore.asFloat(cr.get("allowance"));
        var used = QuotaStore.asFloat(cr.get("used"));
        if (allowance == null || used == null) {
            return null;
        }

        var remaining = QuotaStore.asFloat(cr.get("remaining"));

        var frozenV = cr.get("frozen");
        var frozen = false;
        if (frozenV instanceof Lang.Boolean) {
            frozen = frozenV as Lang.Boolean;
        }

        // "2026-12-03T10:13:36Z" -> día civil para el badge de reset.
        var periodDay = null;
        var pe = cr.get("period_end") as Lang.String;
        if (pe != null) {
            periodDay = QuotaStore.parseIsoDay(pe);
        }

        // period_start -> epoch (s) a las 00:00 UTC del día (precisión de
        // día, la que usa el cálculo del ritmo). Se guarda en la caché junto
        // a period_end para la pantalla de PROYECCIÓN.
        var periodStart = null;
        var ps = cr.get("period_start") as Lang.String;
        if (ps != null) {
            var psDay = QuotaStore.parseIsoDay(ps);
            if (psDay != null) {
                periodStart = psDay * 86400;
            }
        }

        var windowTotal = null;
        var totTokens = null;
        var totRequests = null;
        var totCached = null;
        var models = [];
        var toV = data.get("totals");
        if (toV instanceof Lang.Dictionary) {
            var to = toV as Lang.Dictionary;
            windowTotal = QuotaStore.asFloat(to.get("credits"));
            // Conteos de la ventana si el bloque "totals" los trae; si no,
            // abajo se suman desde by_model (incluye los modelos gratuitos:
            // el saldo se calcula ANTES de filtrar los modelos sin créditos).
            totTokens = QuotaStore.isNumeric(to.get("total_tokens"))
                ? to.get("total_tokens") : null;
            totRequests = QuotaStore.isNumeric(to.get("api_requests"))
                ? to.get("api_requests") : null;
            totCached = QuotaStore.isNumeric(to.get("cached_tokens"))
                ? to.get("cached_tokens") : null;
            var list = to.get("by_model");
            if (list instanceof Lang.Array) {
                for (var i = 0; i < list.size(); i++) {
                    var eV = list[i];
                    if (!(eV instanceof Lang.Dictionary)) {
                        continue;
                    }
                    var e = eV as Lang.Dictionary;
                    var name = e.get("model") as Lang.String;
                    var credits = QuotaStore.asFloat(e.get("credits"));
                    if (name == null) {
                        continue;
                    }
                    // total_tokens / api_requests / cached_tokens crudos
                    // (Number o Long de 64); se conservan tal cual y pueden
                    // ser null si la API los omite.
                    models.add(new ModelCredit(name, credits,
                        e.get("total_tokens"), e.get("api_requests"),
                        e.get("cached_tokens")));
                }
            }
        }
        if (totTokens == null || totRequests == null || totCached == null) {
            var sT = 0;
            var sR = 0;
            var sC = 0;
            var anyT = false;
            var anyR = false;
            var anyC = false;
            for (var i = 0; i < models.size(); i++) {
                var sm = models[i] as ModelCredit;
                if (sm == null) {
                    continue;
                }
                if (sm.tokens() != null) {
                    sT += sm.tokens();
                    anyT = true;
                }
                if (sm.apiRequests() != null) {
                    sR += sm.apiRequests();
                    anyR = true;
                }
                if (sm.cachedTokens() != null) {
                    sC += sm.cachedTokens();
                    anyC = true;
                }
            }
            if (totTokens == null && anyT) {
                totTokens = sT;
            }
            if (totRequests == null && anyR) {
                totRequests = sR;
            }
            if (totCached == null && anyC) {
                totCached = sC;
            }
        }

        // Orden por créditos desc -> filtrado de modelos sin consumo (los
        // gratuitos NO se listan) -> etiquetas únicas por lista.
        QuotaStore.sortModelsDesc(models);
        models = QuotaStore.filterBilled(models);
        QuotaStore.assignLabels(models);

        return new CreditState(allowance, used, remaining, frozen, periodDay,
            windowTotal, models, periodStart, totTokens, totRequests,
            totCached);
    }

    //! Selección directa por créditos DESC (la API manda "by_model" ordenado
    //! "como quiere"); el orden se fija UNA vez aquí y se persiste, la vista
    //! y la glance no re-ordenan.
    private static function sortModelsDesc(models as Lang.Array) as Void {
        var n = models.size();
        for (var i = 0; i < n; i++) {
            var best = i;
            for (var j = i + 1; j < n; j++) {
                var a = models[best] as ModelCredit;
                var b = models[j] as ModelCredit;
                if (a == null || b == null) {
                    continue;
                }
                // Modelo sin créditos (null) = 0.0 para no romper la
                // comparación numérica con valores Long/Float mixtos.
                var ca = a.credits();
                var cb = b.credits();
                if (ca == null) {
                    ca = 0.0;
                }
                if (cb == null) {
                    cb = 0.0;
                }
                if (cb > ca) {
                    best = j;
                }
            }
            if (best != i) {
                var tmp = models[i];
                models[i] = models[best];
                models[best] = tmp;
            }
        }
    }

    //! Compact serialisation for Application Storage. Float/Boolean/Array/
    //! Dictionary son almacenables; "m" va pre-ordenado por créditos desc,
    //! FILTRADO (sin modelos de 0 créditos) y con etiquetas ya asignadas.
    //! Por entrada: "n" nombre, "c" créditos y (si la API los trajo, si no
    //! la clave NO existe para que una caché antigua siga siendo legible)
    //! "tk"=total_tokens, "rq"=api_requests, "ca"=cached_tokens. A nivel de
    //! instantánea: "ps"=period_start (epoch s), "tt"=tokens de la ventana,
    //! "ar"=peticiones y "ct"=tokens caché (opcionales, mismo criterio).
    private static function serializeState(state as CreditState) {
        var ms = [];
        var models = state.models();
        for (var i = 0; i < models.size(); i++) {
            var m = models[i] as ModelCredit;
            if (m == null) {
                continue;
            }
            var e = {
                "n" => m.model(),
                "c" => m.credits()
            };
            if (m.tokens() != null) {
                e.put("tk", m.tokens());
            }
            if (m.apiRequests() != null) {
                e.put("rq", m.apiRequests());
            }
            if (m.cachedTokens() != null) {
                e.put("ca", m.cachedTokens());
            }
            ms.add(e);
        }
        var out = {
            "a" => state.allowance(),
            "u" => state.used(),
            "r" => state.remaining(),
            "f" => state.frozen(),
            "d" => state.periodDay(),
            "t" => state.windowTotal(),
            "m" => ms
        };
        if (state.periodStart() != null) {
            out.put("ps", state.periodStart());
        }
        if (state.totTokens() != null) {
            out.put("tt", state.totTokens());
        }
        if (state.totRequests() != null) {
            out.put("ar", state.totRequests());
        }
        if (state.totCached() != null) {
            out.put("ct", state.totCached());
        }
        return out;
    }

    //! Days-since-epoch (civil) for a y/m/d triple, Howard Hinnant's algorithm.
    public static function dayNumber(y as Lang.Number, mo as Lang.Number, d as Lang.Number) as Lang.Number {
        if (mo <= 2) { y -= 1; }
        var era = y / 400;
        var yoe = y - era * 400;
        var mp = (mo > 2) ? (mo - 3) : (mo + 9);
        var doy = (153 * mp + 2) / 5 + d - 1;
        var doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146097 + doe - 719468;
    }

    //! "2026-12-01T00:00:00Z" -> day number, using only the date part.
    public static function parseIsoDay(iso as Lang.String) {
        if (iso == null || iso.length() < 10) {
            return null;
        }
        var y = iso.substring(0, 4).toNumber();
        var mo = iso.substring(5, 7).toNumber();
        var d = iso.substring(8, 10).toNumber();
        if (y == null || mo == null || d == null) {
            return null;
        }
        return QuotaStore.dayNumber(y, mo, d);
    }

    //! Whole days between today (local clock) and the reset date, or null.
    public static function daysUntilReset(periodDay) {
        if (periodDay == null) {
            return null;
        }
        // Time.today() -> local midnight Moment; value() -> UNIX seconds.
        var todaySeconds = Time.today().value();
        var today = todaySeconds / 86400;
        return periodDay - today;
    }

    private static function fail(msg as Lang.String) {
        // B2: el fallo TAMBIÉN es un intento -> backoff/anti-rebote de 30 s.
        // B3: se recuerda el texto para que el subtítulo ámbar sobreviva a
        // reabrir la vista (un éxito lo borra en parseSnapshot()).
        Application.Storage.setValue(QuotaStore.ATTEMPT_KEY, QuotaStore.nowEpoch());
        Application.Storage.setValue(QuotaStore.LAST_ERR_KEY, msg);
        if (QuotaStore.sCallback != null) {
            QuotaStore.sCallback.invoke(null, msg);
        }
    }
}
