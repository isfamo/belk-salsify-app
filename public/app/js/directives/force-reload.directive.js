/**
 * @ngdoc directive
 * @name app.directives.forceReload:forceReload
 * @restrict A
 * @element a
 * @description
 * # Force Reload Directive
 *
 * This directive will force the route reload, when clicking on a link that has the same href as the current route
 *
 * @usage
    <a force-reload href="/route">click</a>
 */
angular.module('app.directives.forceReload', ['ngRoute']).directive('forceReload', forceReload);

forceReload.$inject = ['$location', '$route'];

function forceReload($location, $route) {
    return function(scope, element, attrs) {
        element.bind('click', function() {
            scope.$apply(function() {
                if ($location.path() === attrs.href) {
                    $location.search('');
                    $route.reload();
                }
            });
        });
    };
}
