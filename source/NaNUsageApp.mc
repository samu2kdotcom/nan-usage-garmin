using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Lang;

//! Entry point of the NaN Cloud usage widget.
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
