beforeEach(angular.mock.module('app.controllers.tree'));

describe('TreeController', function() {
    describe('init', function() {
        var $controller;
        var $rootScope;
        var $httpBackend;
        var ctrl;
        var response = {
                 loading: false,
                 tree: {
                     root: {}
                 },
                 last_updated: ''
             };

        beforeEach(angular.mock.inject(function($injector) {
            $controller = $injector.get('$controller');
            $rootScope = $injector.get('$rootScope');
            $httpBackend = $injector.get('$httpBackend');

            ctrl = $controller('TreeController', {
                $rootScope: $rootScope
            });
        }));

        it('Controller should be defined', angular.mock.inject(function() {
            $httpBackend.when('GET', 'dummy.json').respond(200, response);
            expect(ctrl).toBeDefined();
            $httpBackend.flush();
        }));

    });

});
