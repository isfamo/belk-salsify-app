/**
 * @ngdoc controller
 * @name app.controllers.cma:CMAController
 * @description
 * # CMA Controller
 * This is the controller for the /cma route
 *
 */
angular.module('app.controllers.cma', ['ngRoute']).config(CMAControllerConfig).controller('CMAController', CMAController);

CMAControllerConfig.$inject = ['$routeProvider'];
CMAController.$inject = ['$rootScope', '$http', 'alertService'];

function CMAControllerConfig($routeProvider) {
    $routeProvider.when('/cma', {
        controller: 'CMAController as ctrl',
        templateUrl: 'app/templates/cma.html',
        reloadOnSearch: false
    });
}

function CMAController($rootScope, $http, alertService) {

    $rootScope.pageTitle = "Belk CMA";

    var ctrl = this;
    $rootScope.loading = false;

    /**
     * @ngdoc
     * @name app.controllers.cma#onDemand
     * @methodOf app.controllers.tree:CMAController
     *
     * @description
     * # Change source
     * This method is used to make the GET call on /cma and trigger the on demand export
     *
     */
    $rootScope.onDemand = function() {
      var filename = $('#input-cma')[0].value;

      $http.get('/api/cma_on_demand?filename='+filename).success(function(response) {
        alertService.add('CMA feed is generating, it will be placed on FTP upon completion.', 'success', false);
      }).error(function(response) {
        if (response.error) {
          alertService.add(response.error, 'danger', false);
        } else {
          alertService.add('There was an error getting the data from the server. Please try again!', 'danger', false);
        }
      });
    }

}
