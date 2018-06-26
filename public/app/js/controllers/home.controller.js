/**
 * @ngdoc controller
 * @name app.controllers.home:HomeController
 * @description
 * # Home Controller
 * This is the controller for the / route
 *
 * This route is also the default route
 */
angular.module('app.controllers.home', ['ngRoute']).config(HomeControllerConfig).controller('HomeController', HomeController);

HomeControllerConfig.$inject = ['$routeProvider'];
HomeController.$inject = ['$rootScope'];

function HomeControllerConfig($routeProvider) {
    $routeProvider.when('/', {
        controller: 'HomeController as ctrl',
        templateUrl: 'app/templates/home.html',
        reloadOnSearch: false,
        pageTitle: 'Belk Category Browser - Salsify'
    });
}

function HomeController($rootScope) {
    $rootScope.pageTitle = "Home - Salsify";
}
