/**
 * @ngdoc controller
 * @name app.controllers.tree:TreeController
 * @description
 * # Categories Controller
 * This is the controller for the /tree route
 *
 */
angular.module('app.controllers.tree', ['ngRoute']).config(TreeControllerConfig).controller('TreeController', TreeController);

TreeControllerConfig.$inject = ['$routeProvider'];
TreeController.$inject = ['$rootScope', '$http', 'alertService', '$cookies'];



function TreeControllerConfig($routeProvider) {
    $routeProvider.when('/tree', {
        controller: 'TreeController as ctrl',
        templateUrl: 'app/templates/tree.html',
        reloadOnSearch: false
    });
}

function TreeController($rootScope, $http, alertService, $cookies) {

    $rootScope.pageTitle = "Belk Categories Browser - Salsify";

    var ctrl = this;
    var $searchableTree;
    $rootScope.loading = true;

    /**
     * @ngdoc
     * @name app.controllers.tree#init
     * @methodOf app.controllers.tree:TreeController
     *
     * @description
     * # init method
     * Init method will load the categories by making a get call on /categories
     * Until the call is finished, a loading will be shown, $rootScope.loading variable is taking care of this aspect
     *
     * When we have a good response from the server, we will initialize the treeview with the data from the server
     * The updated at field displayed in the UI is first formated to be readable and adjusted to current timezone with moment.js
     *
     * If the server responds with error it may be because the user is not logged in, in this case we'll redirect the user to /login, otherwise an general error will be displayed
     *
     */

    var init = function() {
        $http.get('/api/categories').success(function(response) {
            $rootScope.loading = false;
            $rootScope.error = false;
            if (response.loading) {
                alertService.add('The categories are updating in the background. Please refresh the page in about 30 seconds to see the updates!', 'success', false);
            } else {
                if (response.tree.root) {
                    $searchableTree = $('#tree').treeview({
                      data: [response.tree.root],
                      allows_export: response.allows_export
                    });

                    var lu = response.last_updated;
                    var vd = moment(lu).format(); // to locale
                    var gd = moment(vd).format('MM-DD-YYYY HH:mm A'); // to readable

                    $rootScope.last_update = gd;
                    $rootScope.isdata = response.tree.root?true:false;

                    var search = function(e) {
                        //collapse all before searching again
                        $searchableTree.treeview('collapseAll');
                        var pattern = $('#input-search').val();
                        var options = {
                            ignoreCase: true,
                            revealResults: true
                        };
                        var results = $searchableTree.treeview('search', [ pattern, options ]);
                        var output = '<p>' + results.length + ' matches found</p>';
                        $('#search-output').html(output);
                    }
                } else {
                    alertService.add('The server could not return data, please use Refresh Category Tree button to generate new data!', 'warning', false);
                }
            }

            $('#btn-search').on('click', search);
            $('#form').on('submit', search);

        }).error(function(err, code) {
            if (code == 401) {
                alertService.add('You need to be logged in to access this page, you will be redirected!', 'danger');
                $cookies.remove('_customer-belk_session');
                $rootScope.error = true;

                setTimeout(function(){
                    window.location = '/login';
                }, 2000);
            } else {
                alertService.add('There was an error getting the data from the server. Please try refreshing the page!', 'danger');
                $rootScope.error = true;
                $rootScope.loading = false;
            }
        });
    } // end init

    init();

    /**
     * @ngdoc
     * @name app.controllers.tree#export
     * @methodOf app.controllers.tree:TreeController
     *
     * @description
     * # Change source
     * This method is used to make the GET call on /refresh and add an alert notification
     *
     */

    $(document).on("click", "a.export", function() {
      alertService.add('CFH report is generating and will be emailed when complete. This may take several minutes!', 'success', false);
        var sid = $(this).attr('data-sid');
        $http.get('/api/demand?sid='+sid).success(function(response) {
        }).error(function(response) {
            if (response.error) {
                alertService.add(response.error, 'danger');
            } else {
                alertService.add('There was an error getting the data from the server. Please try again!', 'danger');
            }
        });
    });

    $(document).on("click", "a.full_export", function() {
      alertService.add('CFH report is generating and will be placed on Belk FTP upon completion. This may take several minutes!', 'success', false);
        var sid = $(this).attr('data-sid');
        $http.get('/api/full?sid='+sid).success(function(response) {
        }).error(function(response) {
            if (response.error) {
                alertService.add(response.error, 'danger');
            } else {
                alertService.add('There was an error getting the data from the server. Please try again!', 'danger');
            }
        });
    });

    /**
     * @ngdoc
     * @name app.controllers.tree#changeSource
     * @methodOf app.controllers.tree:TreeController
     *
     * @description
     * # Change source
     * This method is used to make the GET call on /refresh and add an alert notification
     *
     */
    $rootScope.changeSource = function() {
        if (confirm("While the categories are refreshing, you will not be able to see the tree. Are you sure you want to refresh?") == true) {
            $http.get('/api/refresh').success(function(response) {
                // window.location.reload();
            }).error(function() {
                // window.location.reload();
            });
            alertService.add('The categories are updating in the background. Please refresh the page in about 30 seconds to see the updates!', 'success', false);
            $searchableTree.remove();
        }
    }

}
