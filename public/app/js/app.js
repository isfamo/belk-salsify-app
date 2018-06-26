/**
 * @ngdoc interface
 * @name myApp
 * @description
 * # App description
 * This doc will describe how the app setup is done
 */
angular.module('myApp', ['ngRoute', 'ngCookies', 'app.controllers', 'app.services', 'app.directives']).config(AppConfig).run(run);

AppConfig.$inject = ['$locationProvider', '$routeProvider', '$httpProvider'];
run.$inject = ['$rootScope', '$location', '$window', '$http', '$cookies', 'alertService'];


/**
 * @ngdoc
 * @name myApp#config
 * @methodOf myApp
 *
 * @description
 * # App configuration
 *
 * During app configuration the following steps are made:
 * - enable HTML5 router
 * - defined default route
 * - set Accept header value
 *
 * @param {provider} $locationProvider $locationProvider
 * @param {provider} $routeProvider $routeProvider
 * @param {provider} $httpProvider $httpProvider
 */
function AppConfig($locationProvider, $routeProvider, $httpProvider) {
    $locationProvider.html5Mode({
        enabled: true,
        requireBase: false
    });
    $routeProvider.otherwise('/');
    $httpProvider.defaults.headers.common = {
        Accept: "application/vnd.v1.0"
    };
}
/**
 * @ngdoc
 * @name myApp#run
 * @methodOf myApp
 *
 * @description
 * # App runner
 *
 * During app run the following steps are made:
 * - set backend url
 * - set loading state
 * - set modal loading state
 * - set currentRoute
 * - set pageTitle
 * - handle incoming requests
 * - handle route change start
 * - handle route change error
 * - handle route change success
 *
 * @param {scope} $rootScope $rootScope
 * @param {service} $location $location
 * @param {service} $window $window
 * @param {service} $http $http
 * @param {service} $cookies $cookies
 */
function run($rootScope, $location, $window, $http, $cookies, alertService, $routeProvider, $locationProvider) {
    $rootScope.server = false;
    $rootScope.pageTitle = '';
    $rootScope.alertService = alertService;
    $rootScope.logout = function() {
        $cookies.remove('_customer-belk_session', { path: '/' });
        window.location = '/';
    }
    $rootScope.isLogged = function() {
        if ($cookies.get('_customer-belk_session')) {
            return true;
        } else {
            return false;
        }
    }
    $rootScope.$on('$routeChangeStart', function(event, next, current) {
        if ($location.path() == "/tree" && !$cookies.get('_customer-belk_session')) {
            window.location = '/login';
        }
        if ($location.path() == "/cma" && !$cookies.get('_customer-belk_session')) {
            window.location = '/login';
        }
        if ($location.path() == "/status" && !$cookies.get('_customer-belk_session')) {
            window.location = '/login';
        }
        if ($location.path() == "/rrd" && !$cookies.get('_customer-belk_session')) {
            window.location = '/login';
        }
        if ($location.path() == "/rrd_print" && !$cookies.get('_customer-belk_session')) {
            window.location = '/login';
        }
        if ($location.path() == "/attribute_refresh" && !$cookies.get('_customer-belk_session')) {
            window.location = '/login';
        }

        if ($location.search().success) {
            alertService.add($location.search().message, 'success');
        }
        if (alertService.alert) {
            if (alertService.alert.persist) {
                alertService.alert.persist = false;
            } else {
                alertService.dismiss();
            }
        }
    });
}

angular.module('app.controllers', [
  'app.controllers.home',
  'app.controllers.tree',
  'app.controllers.cma',
  'app.controllers.status',
  'app.controllers.rrd',
  'app.controllers.rrd_print',
  'app.controllers.attribute_refresh'
]);

angular.module('app.services', ['app.services.alert']);

angular.module('app.directives', ['app.directives.forceReload']);
