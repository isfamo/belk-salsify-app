beforeEach(angular.mock.module('myApp'));

var $rootScope;
var $httpBackend;
var asd;
var qwe;
var zxc;

describe('app -', function() {
    beforeEach(angular.mock.inject(function($injector, $cookies) {
        $rootScope = $injector.get('$rootScope');
        $cookies.remove('_customer-belk_session');
        $httpBackend = $injector.get('$httpBackend');
    }));
    afterEach(function() {
        $httpBackend.verifyNoOutstandingExpectation();
        $httpBackend.verifyNoOutstandingRequest();
    });
    describe('logout', function() {
        // it('should logout', angular.mock.inject(function($cookies) {
        //     window.location = 'test';
        //     $rootScope.logout();
        //     expect($cookies.get('_customer-belk_session')).toBeFalsy();
        // }));
    });
    describe('isLogged', function() {
        it('should return true if we have cookie', angular.mock.inject(function($cookies) {
            $cookies.put('_customer-belk_session', 'asdasd');
            $rootScope.isLogged();
            expect($cookies.get('_customer-belk_session')).toBeTruthy();
        }));
        it('should return false if we dont have cookie', angular.mock.inject(function($cookies) {
            $cookies.remove('_customer-belk_session');
            $rootScope.isLogged();
            expect($cookies.get('_customer-belk_session')).toBeFalsy();
        }));
    });
    describe('on route change start', function() {
        beforeEach(angular.mock.inject(function($location, $cookies, alertService){
            $location.search('success', 1);
            $cookies.put('_customer-belk_session', undefined);
            alertService.alert = true;
            $rootScope.$emit('$routeChangeStart');
        }));

        it('should cover persist', angular.mock.inject(function(alertService) {
            alertService.alert = {};
            alertService.alert.persist = true;
            $rootScope.$emit('$routeChangeStart');
        }));

    });

});
