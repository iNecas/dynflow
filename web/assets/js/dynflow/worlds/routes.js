angular.module('Dynflow.worlds')
    .config(['$stateProvider', function ($stateProvider) {
        $stateProvider
            .state('worlds', {
                abstract: true,
                template: '<ui-view/>'
            })
            .state('worlds.index', {
                url: "/worlds",
                templateUrl: "js/dynflow/worlds/views/index.html",
                controller: "WorldsIndexController"
            })
    }])
