angular.module('Dynflow.execution-plans')
    .config(['$stateProvider', function ($stateProvider) {
        $stateProvider
            .state('execution-plans', {
                abstract: true,
                template: '<ui-view/>'
            })
            .state('execution-plans.index', {
                url: "/execution_plans",
                templateUrl: "views/execution-plans.index.html",
                controller: "ExecutionPlansIndexController"
            })
            .state('execution-plans.details', {
                url: "/execution_plans/:executionPlanId",
                templateUrl: "views/execution-plans.details.html",
                controller: "ExecutionPlansDetailsController"
            })
            .state('execution-plans.details.action', {
                url: "/actions/:actionId",
                controller: "ExecutionPlansDetailsActionController"
            })
    }])
