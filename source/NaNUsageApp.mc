using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

//! Entry point of the NaN Cloud usage widget.
//!
//! (:glance) marca la clase como parte del proceso de glance (es quien
//! devuelve getGlanceView()); así el compilador no la "añade implícitamente".
//! (:typecheck(disableGlanceCheck)) silencia SÓLO aquí el aviso de que
//! getInitialView() construye la vista principal, que no existe en el proceso
//! de glance (64 KB): esa comprobación sigue activa en NaNUsageGlanceView, que
//! es el único código que de verdad corre en glance y no debe tocar
//! QuotaStore ni las vistas principales.
(:glance, :typecheck(disableGlanceCheck))
class NaNUsageApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    //! Returns the main view and its input delegate when the widget is opened.
    function getInitialView() {
        return [new NaNUsageView(), new NaNUsageDelegate()];
    }

    //! Shown in the glance list: cached totals, no network.
    function getGlanceView() {
        return [new NaNUsageGlanceView()];
    }
}
