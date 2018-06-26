angular.module('app.controllers.attribute_refresh', ['ngRoute']).config(AttributeRefreshConfig).controller('AttributeRefresh', AttributeRefresh);

AttributeRefreshConfig.$inject = ['$routeProvider'];
AttributeRefresh.$inject = ['$scope', '$rootScope', '$http', 'alertService'];

function AttributeRefreshConfig($routeProvider) {
    $routeProvider.when('/attribute_refresh', {
        controller: 'AttributeRefresh as ctrl',
        templateUrl: 'app/templates/attribute_refresh.html',
        reloadOnSearch: false
    });
}

function AttributeRefresh($scope, $rootScope, $http, alertService) {

    $rootScope.pageTitle = "Refresh Enrichment Attributes";
    $rootScope.loading = false;

    $scope.showButton = true
    $scope.showSucess = false

    $scope.refresh = function() {
      $http.post('/api/refresh_attributes').success(function(response) {
        $scope.showButton = false;
        $scope.showSucess = true;
      }).error(function(response) {
        if (response.error) {
          alertService.add(response.error, 'danger', false);
        } else {
          alertService.add('There was an error getting the data from the server. Please try again!', 'danger', false);
        }
      });
    };


}
