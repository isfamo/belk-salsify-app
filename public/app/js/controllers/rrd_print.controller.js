/**
 * @ngdoc controller
 * @name app.controllers.rrd_print:RrdPrintController
 * @description
 * # RRDPrint Controller
 * This is the controller for the /rrd_print route
 *
 */
angular.module('app.controllers.rrd_print', ['ngRoute']).config(RrdControllerConfig).controller('RrdPrintController', RrdPrintController);

RrdControllerConfig.$inject = ['$routeProvider'];
RrdController.$inject = ['$scope', '$rootScope', '$http', 'alertService'];

function RrdControllerConfig($routeProvider) {
    $routeProvider.when('/rrd_print', {
        controller: 'RrdPrintController as ctrl',
        templateUrl: 'app/templates/rrd_print.html',
        reloadOnSearch: false
    });
}

function RrdPrintController($scope, $rootScope, $http, alertService) {

    $rootScope.pageTitle = "RRDPrint";

    var ctrl = this;
    $rootScope.loading = false;

    var init = function() {
      // Do stuff on page load
      $scope.isLoading = false;
      product_id = getParameterByName('product_id');
      if (product_id != null) {
        $rootScope.searchProductCode(product_id);
      }
    }

    function getParameterByName(name, url) {
      if (!url) url = window.location.href;
      name = name.replace(/[\[\]]/g, "\\$&");
      var regex = new RegExp("[?&]" + name + "(=([^&#]*)|&|#|$)"),
          results = regex.exec(url);
      if (!results) return null;
      if (!results[2]) return '';
      return decodeURIComponent(results[2].replace(/\+/g, " "));
    }

    $rootScope.searchProductCode = function(productCode) {
      $scope.isLoading = true;

      $http.get('/api/rrd_get_product?product_id='+productCode).success(function(response) {
        $scope.product = response.product;
        $scope.colors = response.colors;
        $scope.reqdColors = response.reqdColors;
        $scope.colorList = [];
        for (var i = 0; i < $scope.colors.length; i++) {
          $scope.colorList.push($scope.colors[i]['name'])
        }
        $scope.isLoading = false;
      }).error(function(response) {
        if (response.error) {
          alertService.add(response.error, 'danger', false);
        } else {
          alertService.add('There was an error getting the data from the server. Please refresh the page and try again!', 'danger', false);
        }
        $scope.isLoading = false;
      });
    }

    init();
}
