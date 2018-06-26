beforeEach(angular.mock.module('app.controllers.home'));

describe('HomeController', function() {
    var $controller;
    var $rootScope;
    var $httpBackend;
    var ctrl;

    beforeEach(angular.mock.inject(function($injector) {
        $controller = $injector.get('$controller');
        $rootScope = $injector.get('$rootScope');
        $httpBackend = $injector.get('$httpBackend');

        ctrl = $controller('HomeController', {
            $rootScope: $rootScope
        });
    }));
    afterEach(function() {
        $httpBackend.verifyNoOutstandingExpectation();
        $httpBackend.verifyNoOutstandingRequest();
    });

    it('Controller should be defined', angular.mock.inject(function() {
        expect(ctrl).toBeDefined();
    }));
    it('test route', angular.mock.inject(function($route) {
        $httpBackend.expectGET('app/templates/home.html').respond(200);
        $httpBackend.flush();
        expect($route.routes['/'].controller).toBe('HomeController as ctrl');
        expect($route.routes['/'].templateUrl).toBe('app/templates/home.html');
        expect($route.routes['/'].reloadOnSearch).toBe(false);
    }));

    it('Should have some properties', angular.mock.inject(function() {
        expect($rootScope.pageTitle).toBeDefined();
    }));
});
