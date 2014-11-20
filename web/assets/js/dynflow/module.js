angular.module('Dynflow', ['ngResource', 'ui.router', 'ui.bootstrap', 'ui.bootstrap.tpls'])
    .run(['$rootScope', '$window', '$state', '$stateParams',
         function($rootScope, $window, $state, $stateParams) {
        $rootScope.$state = $state;
        $rootScope.$stateParams = $stateParams;

        $rootScope.dynflowPageTitleSuffix = 'DynFlow Console'

        $rootScope.setPageTitle = function (value) {
            if (value) {
                $window.document.title = value + ' : ' + $rootScope.dynflowPageTitleSuffix;
            } else {
                $window.document.title = $rootScope.dynflowPageTitleSuffix;
            }
        };
    }])
    .config(['$stateProvider', '$urlRouterProvider',
             function ($stateProvider, $urlRouterProvider) {
        $urlRouterProvider.otherwise("/execution_plans");
    }]);
