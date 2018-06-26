beforeEach(angular.mock.module('app.services.alert'));

describe('alertService - ', function() {
    it('test alert is false', angular.mock.inject(function($rootScope, alertService) {
        expect(alertService.alert).toBe(false);
    }));
    describe('text - ', function() {
        it('test text is OK', angular.mock.inject(function($rootScope, alertService) {
            var text = 'sample_text';
            alertService.add(text);
            expect($rootScope.alertService.alert.text).toEqual(text);
        }));
        it('test empty text is OK', angular.mock.inject(function($rootScope, alertService) {
            alertService.add('');
            expect($rootScope.alertService.alert).toBe(false);
        }));
        it('test undefined text is OK', angular.mock.inject(function($rootScope, alertService) {
            alertService.add();
            expect($rootScope.alertService.alert).toBe(false);
        }));
        it('test null text is OK', angular.mock.inject(function($rootScope, alertService) {
            alertService.add(null);
            expect($rootScope.alertService.alert).toBe(false);
        }));
        it('test boolean-true text is OK', angular.mock.inject(function($rootScope, alertService) {
            alertService.add(true);
            expect($rootScope.alertService.alert).toBe(false);
        }));
        it('test boolean-false text is OK', angular.mock.inject(function($rootScope, alertService) {
            alertService.add(false);
            expect($rootScope.alertService.alert).toBe(false);
        }));
    });
    describe('type - ', function() {
        it('test type is OK', angular.mock.inject(function($rootScope, alertService) {
            var text = 'sample_text';
            alertService.add(text, 'danger');
            expect($rootScope.alertService.alert.type).toEqual('alert-danger');
        }));
    });
    describe('persist - ', function() {
        it('test default persist is false', angular.mock.inject(function($rootScope, alertService) {
            var text = 'sample_text';
            alertService.add(text, 'danger');
            expect($rootScope.alertService.alert.persist).toBe(false);
        }));
        it('test persist is false', angular.mock.inject(function($rootScope, alertService) {
            var text = 'sample_text';
            alertService.add(text, 'danger', true);
            expect($rootScope.alertService.alert.persist).toBe(false);
        }));
        it('test persist is true', angular.mock.inject(function($rootScope, alertService) {
            var text = 'sample_text';
            alertService.add(text, 'danger', false);
            expect($rootScope.alertService.alert.persist).toBe(true);
        }));
    });
    describe('dismiss - ', function() {
        it('test auto dismiss true', angular.mock.inject(function($rootScope, alertService, $interval) {
            var text = 'sample_text';
            var type = 'success';
            alertService.add(text, type, true);
            expect($rootScope.alertService.alert).not.toEqual(false);
            $interval.flush(5000);
            expect($rootScope.alertService.alert).toEqual(false);
        }));
        it('test auto dismiss false', angular.mock.inject(function($rootScope, alertService) {
            var text = 'sample_text';
            var type = 'success';
            alertService.add(text, type, false);
            expect($rootScope.alertService.alert).not.toEqual(false);
        }));
        it('test dismiss', angular.mock.inject(function($rootScope, alertService) {
            var text = 'sample_text';
            var type = 'success';
            alertService.add(text, type, false);
            expect($rootScope.alertService.alert).not.toEqual(false);
            alertService.dismiss();
            expect($rootScope.alertService.alert).toEqual(false);
        }));
    });
});
