/**
 * @ngdoc controller
 * @name app.controllers.rrd:RrdController
 * @description
 * # RRD Controller
 * This is the controller for the /rrd route
 *
 */
angular.module('app.controllers.rrd', ['ngRoute']).config(RrdControllerConfig).controller('RrdController', RrdController);

RrdControllerConfig.$inject = ['$routeProvider'];
RrdController.$inject = ['$scope', '$rootScope', '$http', 'alertService'];

function RrdControllerConfig($routeProvider) {
    $routeProvider.when('/rrd', {
        controller: 'RrdController as ctrl',
        templateUrl: 'app/templates/rrd.html',
        reloadOnSearch: false
    });
}

function RrdController($scope, $rootScope, $http, alertService) {

    $rootScope.pageTitle = "RRD";

    var ctrl = this;
    $rootScope.loading = false;

    var init = function() {
      // Do stuff on page load
      $rootScope.domain = new RegExp("^(.+)\/rrd.*$").exec(window.location.href)[1];
      product_id = getParameterByName('product_id');
      if (product_id != null) {
        $('#input-product-code').val(product_id);
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
      if (productCode == null) {
        productCode = $('#input-product-code')[0].value
      }

      // Disable search button so user knows to cool their shit
      var searchBtn = $('button#search-product-btn');
      searchBtn.prop('disabled', true);
      searchBtn.html('Searching...');

      $http.get('/api/rrd_get_product?product_id='+productCode).success(function(response) {
        $scope.product = response.product;
        $scope.colors = response.colors;
        $scope.reqdColors = response.reqdColors;
        $scope.submitDisabled = true;
        $scope.colorList = [];
        for (var i = 0; i < $scope.colors.length; i++) {
          $scope.colorList.push($scope.colors[i]['name'])
        }
        // Re-enable the search button
        searchBtn.prop('disabled', false);
        searchBtn.html('Search');
      }).error(function(response) {
        if (response.error) {
          alertService.add(response.error, 'danger', false);
        } else {
          alertService.add('There was an error getting the data from the server. Please refresh the page and try again!', 'danger', false);
        }
        // Re-enable the search button
        searchBtn.prop('disabled', false);
        searchBtn.html('Search');
      });
    }

    $rootScope.checkIfAnySelected = function() {
      $scope.submitDisabled = true;
      $('input.color-selected').each(function(index, checkbox) {
        if (checkbox.checked) {
          $scope.submitDisabled = false;
          return;
        }
      });
    }

    $rootScope.submitRequests = function() {
      var requests = [];
      $('tr.color-row').each(function(index, row) {
        if ($(row).find('input.color-selected').prop('checked')) {
          requests.push(JSON.stringify({
            'product_id': $scope.product['salsify:id'],
            'color_id': $(row).find('input.color-selected').data('color-id'),
            'color_name': clean_symbols($(row).find('input.color-selected').data('color-name')),
            'of_or_sl': $(row).find('select.of-or-sl').val(),
            'on_hand_or_from_vendor': $(row).find('select.on-hand-or-from-vendor').val(),
            'sample_type': $(row).find('select.sample-type').val(),
            'turn_in_date': $(row).find('input.turn-in-date').val(),
            'must_be_returned': $(row).find('input.must-be-returned').prop('checked'),
            'return_to': $(row).find('select.return-to').val(),
            'return_notes': clean_symbols($(row).find('textarea.return-notes').val()),
            'silhouette_required': $(row).find('input.silhouette').prop('checked'),
            'instructions': clean_symbols($(row).find('textarea.instructions').val())
          }));
        }
      });

      if (requests.length < 1) {
        alertService.add('No samples requested, please check the "Request?" checkbox to indicate which samples you are requesting.', 'danger', false);
        $('#search-product-btn').click();
      } else {
        $http.post('/api/rrd_submit_requests?requests=['+requests+']').success(function(response) {
          alertService.add(('Successfully scheduled '+response.created_reqs.length+' sample request(s)!'), 'success', false);
        }).error(function(response) {
          if (response.error) {
            alertService.add(response.error, 'danger', false);
          } else {
            alertService.add('There was an error sending the sample requests to the server. Please refresh the page and try again!', 'danger', false);
          }
        });
      }
    }

    function clean_symbols(text) {
      return text.replace(/#/g, '$HASH$').replace(/&/g, '$AMP$');
    }

    init();
}
