/**
 * @ngdoc controller
 * @name app.controllers.status:StatusController
 * @description
 * # Status Controller
 * This is the controller for the /status route
 *
 */
angular.module('app.controllers.status', ['ngRoute']).config(StatusControllerConfig).controller('StatusController', StatusController);

StatusControllerConfig.$inject = ['$routeProvider'];
StatusController.$inject = ['$scope', '$rootScope', '$http'];

function StatusControllerConfig($routeProvider) {
    $routeProvider.when('/status', {
        controller: 'StatusController as ctrl',
        templateUrl: 'app/templates/status.html',
        reloadOnSearch: false
    });
}


    //  <a ng-click="runExport()" class="export">Fucking export me</a>
     //
    //  $scope.runExport = function(avaraible) {
     //
    //  }

function StatusController($scope, $rootScope, $http) {

    $rootScope.pageTitle = "Belk Job Status";

    var ctrl = this;
    $rootScope.loading = false;

    var init = function() {
      $http.get('/api/job_status').success(function(response) {
        console.log(response.cma_job);
        $scope.cma_job = response.cma_job
        $scope.cfh_job = response.cfh_job
        $scope.offline_cfh_job = response.offline_cfh_job
        $scope.color_job = response.color_job
        $scope.inventory = response.inventory
        $scope.dwre_master = response.dwre_master
        $scope.dwre_limited = response.dwre_limited
      });
    }

    init();
}
