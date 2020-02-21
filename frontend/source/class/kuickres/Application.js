/* ************************************************************************
   Copyright: 2020 Tobias Oetiker
   License:   ???
   Authors:   Tobias Oetiker <tobi@oetiker.ch>
 *********************************************************************** */

/**
 * Main application class.
 * @asset(kuickres/*)
 *
 */
qx.Class.define("kuickres.Application", {
    extend : callbackery.Application,
    members : {
        main : function() {
            // Call super class
            this.base(arguments);
        }
    }
});
