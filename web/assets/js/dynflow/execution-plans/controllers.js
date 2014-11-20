angular.module('Dynflow.execution-plans')
    .controller('ExecutionPlansIndexController', ['$scope', 'ExecutionPlan', function($scope, ExecutionPlan) {
        $scope.executionPlans = ExecutionPlan.query();
    }])

    .controller('ExecutionPlansDetailsController',
                ['$scope', 'ExecutionPlan',
                 function ($scope, ExecutionPlan) {
                     $scope.executionPlan = ExecutionPlan.get($scope.$stateParams.executionPlanId, function (executionPlan) {
                         executionPlan.scheduleUpdate();
                         $scope.action = executionPlan.rootAction;
                     });

                     $scope.$watch('executionPlan.progress', function (value) {
                         if (value) {
                             $scope.setPageTitle(Math.round(value * 100) + "%");
                         } else {
                             $scope.setPageTitle();
                         }
                     });

                     function updateProgressLook (value) {
                         var classes = ['progress-striped'],
                             state = $scope.executionPlan.state,
                             result = $scope.executionPlan.result;
                         if (!state || !result) {
                             return
                         }
                         if (state === 'running') {
                             classes.push('active');
                         }
                         switch(result) {
                         case 'success':
                             $scope.progressType = 'success';
                             break;
                         case 'error':
                             $scope.progressType = 'danger';
                             break;
                         case 'warning':
                             $scope.progressType = 'warning';
                             break;
                         default:
                             $scope.progressType = 'info';
                         }

                         $scope.progressCssClasses = classes.join(' ');
                     }

                     $scope.$watch('executionPlan.state', updateProgressLook);
                     $scope.$watch('executionPlan.result', updateProgressLook);
    }])

    .controller('ExecutionPlansDetailsActionController',
                ['$scope', '$timeout', '$location', '$anchorScroll', 'ExecutionPlan',
                 function ($scope, $timeout, $location, $anchorScroll, ExecutionPlan) {

                     function scrollToAction () {
                         var anchor = 'dynflow-action-link/' + $scope.$stateParams.executionPlanId + '/' + $scope.$stateParams.actionId;
                         $location.hash(anchor);
                         // scroll to the anchor after the digest finishes
                         $timeout($anchorScroll, 0, false);
                     }

                     $scope.$parent.executionPlan.$promise.then(function (executionPlan) {
                         $scope.action = executionPlan.actions[$scope.$stateParams.actionId];
                         executionPlan.showAction($scope.action);
                         scrollToAction();
                     });

                     $scope.$on('$destroy', function () {
                         if($scope.action) {
                             $scope.$parent.executionPlan.hideAction($scope.action);
                         }
                     });

    }])
