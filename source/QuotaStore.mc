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
class ModelCredit {

    var mModel;      //!< p.ej. "glm5.3"
    var mCredits;    //!< Float: créditos consumidos por el modelo en la ventana

    function initialize(model, credits) {
        mModel = model;
        mCredits = credits;
    }

    function model() { return mModel; }
    function credits() { return mCredits; }

    //! Crédito de este modelo como fracción del TOTAL de la ventana
    //! (totals.credits, p.ej. 3884.6), NUNCA del allowance del periodo de
    //! facturación (7000): así las filas no pueden parecer que suman el héroe.
    function windowFraction(windowTotal as Lang.Float) as Lang.Float {
        if (windowTotal == null || windowTotal <= 0.0 || mCredits == null) {
            return 0.0;
        }
        var f = mCredits * 1.0 / windowTotal;
        if (f < 0.0) { f = 0.0; }
        if (f > 1.0) { f = 1.0; }
        return f;
    }

    //! Short display name: drops everything after "-".
    function shortName() {
        var idx = mModel.find("-");
        if (idx != null && idx > 0) {
            return mModel.substring(0, idx);
        }
        return mModel;
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
    var mModels;       //!< Array<ModelCredit> pre-ordenado por créditos desc

    function initialize(allowance, used, remaining, frozen, periodDay, windowTotal, models) {
        mAllowance = allowance;
        mUsed = used;
        mRemaining = remaining;
        mFrozen = frozen;
        mPeriodDay = periodDay;
        mWindowTotal = windowTotal;
        mModels = models;
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
                if (name == null || credits == null) {
                    continue;
                }
                models.add(new ModelCredit(name, credits));
            }
        }
        var frozenV = d.get("f");
        var frozen = false;
        if (frozenV instanceof Lang.Boolean) {
            frozen = frozenV as Lang.Boolean;
        }
        return new CreditState(allowance, used, QuotaStore.asFloat(d.get("r")),
            frozen, d.get("d"), QuotaStore.asFloat(d.get("t")), models);
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

    //! Fires a request to the NaN Cloud API. The callback receives
    //! (state as CreditState or Null, error as String or Null).
    public static function refresh(callback as Method(state as CreditState or Null, err as Lang.String or Null)) {
        QuotaStore.sCallback = callback;

        // B2: TODO intento (incluso el que acaba en "Sin API key") se marca al
        // INICIAR; en fail() se re-escribe al concluir. Así el anti-rebote de
        // onShow() no re-dispara la red en cada apertura.
        Application.Storage.setValue(QuotaStore.ATTEMPT_KEY, QuotaStore.nowEpoch());

        var key = Properties.getValue("api_key") as Lang.String;
        if (key == null || key.length() < 8) {
            QuotaStore.fail("Sin API key (ajustes)");
            return;
        }

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

        var windowTotal = null;
        var models = [];
        var toV = data.get("totals");
        if (toV instanceof Lang.Dictionary) {
            var to = toV as Lang.Dictionary;
            windowTotal = QuotaStore.asFloat(to.get("credits"));
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
                    if (name == null || credits == null) {
                        continue;
                    }
                    models.add(new ModelCredit(name, credits));
                }
            }
        }

        QuotaStore.sortModelsDesc(models);
        return new CreditState(allowance, used, remaining, frozen, periodDay,
            windowTotal, models);
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
                if (b.credits() > a.credits()) {
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
    //! Dictionary son almacenables; "m" va pre-ordenado por créditos desc.
    private static function serializeState(state as CreditState) {
        var ms = [];
        var models = state.models();
        for (var i = 0; i < models.size(); i++) {
            var m = models[i] as ModelCredit;
            if (m == null) {
                continue;
            }
            ms.add({
                "n" => m.model(),
                "c" => m.credits()
            });
        }
        return {
            "a" => state.allowance(),
            "u" => state.used(),
            "r" => state.remaining(),
            "f" => state.frozen(),
            "d" => state.periodDay(),
            "t" => state.windowTotal(),
            "m" => ms
        };
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
