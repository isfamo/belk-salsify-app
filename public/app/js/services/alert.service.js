/**
 * @ngdoc service
 * @name app.services.alert:alertService
 * @description
 * # Show success/error/warning/info alerts
 *
 * This service will allow you to display different types of alerts to the user
 *
 * If alert is set to persist it will not close by itself, but it will close when route is changed
 */
angular.module('app.services.alert', []).factory('alertService', alertService);

alertService.$inject = ['$interval'];

function alertService($interval) {
    var _this = this;
    this.alert = false;
    /**
     * @ngdoc
     * @name app.services.alert#add
     * @methodOf app.services.alert:alertService
     *
     * @description
     * # Add a new alert
     *
     * @param {string} text to display to the user
     * @param {success | info | warning | danger=} [type=success] alert type
     * @param {boolean=} [autoDismiss=true] if true, alert will close after 5 seconds
     * @example
     <pre>
      alertService.add('text');

      alertService.add('text', 'alert-danger');

      alertService.add('text', 'alert-danger', false);
     </pre>
     */
    this.add = function(text, type, autoDismiss) {
        if (angular.isUndefined(autoDismiss)) {
            autoDismiss = true;
        }
        var alertTypes = ['success', 'info', 'warning', 'danger'];
        if (angular.isUndefined(type) || alertTypes.indexOf(type) === -1) {
        }
        if (angular.isString(text) && text.length > 0) {
            this.alert = {
                text: text,
                type: 'alert-' + type,
                persist: !autoDismiss
            };
            if (autoDismiss) {
                $interval(function() {
                    _this.alert = false;
                }, 5000, 10);
            }
        }
    };
    /**
     * @ngdoc
     * @name app.services.alert#dismiss
     * @methodOf app.services.alert:alertService
     *
     * @description
     * # Dismiss a alert
     *
     * @example
     <pre>
     alertService.dismiss();
     </pre>
     */
    this.dismiss = function() {
        this.alert = false;
    };
    return this;
}
