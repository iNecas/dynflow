//= require jquery
//= require underscore-min
//= require bootstrap
//= require angular
//= require angular-resource
//= require angular-ui-router
//= require ui-bootstrap
//= require ui-bootstrap-tpls

angular.module('dynflowConsole', ['ngResource', 'ui.router', 'ui.bootstrap', 'ui.bootstrap.tpls']);

angular.module('dynflowConsole')
    .run(['$rootScope', '$window', '$state', '$stateParams',
         function($rootScope, $window, $state, $stateParams) {
        $rootScope.$state = $state;
        $rootScope.$stateParams = $stateParams;

        $rootScope.dynflowPageTitleSuffix = 'dynFlow Console'

        $rootScope.setPageTitle = function (value) {
            if (value) {
                $window.document.title = value + ' : ' + $rootScope.dynflowPageTitleSuffix;
            } else {
                $window.document.title = $rootScope.dynflowPageTitleSuffix;
            }
        };
    }])
    .factory('Action', ['$resource', function ($resource) {
        var resource = $resource('./api/execution_plans/:executionPlanId/actions/:id', {executionPlanId: '@executionPlanId', id: '@id'});

        return function (executionPlanId, actionId) {
            var self = this;

            self.executionPlanId = executionPlanId;
            self.id = actionId;

            self.children = [];

            self.planStep = { phase: 'plan' };
            self.runStep = { phase: 'run' };
            self.finalizeStep = { phase: 'finalize' };

            self.loaded = false;

            self.updateStep = function (step) {
                if (/PlanStep/.test(step['class'])) {
                    step.phase = 'plan';
                    self.class = step['action_class'];
                    self.planStep = step;
                } else if (/RunStep/.test(step['class'])) {
                    step.phase = 'run';
                    self.runStep = step;
                } else if (/FinalizeStep/.test(step['class'])) {
                    step.phase = 'finalize';
                    self.finalizeStep = step;
                } else {
                    console.log('unknown step ' + step['class']);
                }
            }

            self.addChild = function (action) {
                self.children.push(action);
            }

            self.loadData = function () {
                resource.get({ executionPlanId: self.executionPlanId, id: self.id }, function (action) {
                    self.input = action.input;
                    self.output = action.output;
                    self.loaded = true;
                });
            }
        }
    }])
    .factory('ExecutionPlan', ['$resource', '$timeout', '$q', 'Action',
                               function ($resource, $timeout, $q, Action) {
        var resource = $resource('./api/execution_plans/:id', {id: '@id'});

        function executionPlanExtension(self) {

            self.actions = {};
            self.stepsById = {};
            self.rootAction = undefined;
            self.refreshedActions = {};

            self.scheduleUpdate = function () {
                $timeout(function () { self.refresh() }, 1500);
            };

            self.refresh = function () {
                var actionUpdatePromieses = [];

                resource.get({ id: this.id }, function (executionPlan) {
                    self.state = executionPlan.state;
                    self.result = executionPlan.result;
                    self.progress = executionPlan.progress;
                    _.each(executionPlan.steps, function(step) {
                        self.stepsById[step.id].state = step.state;
                    });
                    actionUpdatePromieses = _.map(self.refreshedActions, function (action) {
                        return action.loadData();
                    });
                    $q.all(actionUpdatePromieses).then(self.scheduleUpdate);
                })
            };

            self.showAction = function (action) {
                self.refreshedActions[action.id] = action;
                action.showDetails = true;
            }

            self.hideAction = function (action) {
                delete self.refreshedActions[action.id];
                action.showDetails = false;
            }

            function findAction (actionId) {
                if (!self.actions[actionId]) {
                    self.actions[actionId] = new Action(self.id, actionId);
                }
                return self.actions[actionId];
            }

            function findStepAction (stepId) {
                var actionId = self.stepsById[stepId]['action_id'];
                return findAction(actionId);
            }

            function loadSteps () {
                _.each(self.steps, function (step) {
                    self.stepsById[step.id] = step;
                });
                _.each(self.steps, function (step) {
                    var action = findAction(step['action_id']);
                    action.updateStep(step);
                    if (step.children) {
                        _.each(step.children, function (childStepId) {
                            action.addChild(findStepAction(childStepId));
                        })
                            }
                });
            }

            function loadRootAction () {
                self.rootAction = findStepAction(self['root_plan_step_id']);
            }

            loadSteps();
            loadRootAction();
        }

        return {
            get: function (id, callback) {
                var res = resource.get({ id: id }, function (executionPlan) {
                    executionPlanExtension(executionPlan);
                    if (callback) {
                        callback(executionPlan);
                    }
                });

                return res;
            },

            query: function () {
                return resource.query();
            }
        }
    }])
    .factory('World', ['$resource', function ($resource) {
        var resource = $resource('./api/worlds', {});
        return resource;
    }])
    .directive('dynflowStep', [function () {
        return {
            restrict: 'A',
            scope: {
                step: '=dynflowStep',
            },
            templateUrl: 'views/step.directive.html',
            link: function (scope, element, attr) {
                scope.$watch('step.state', function (value) {
                    var mapping = { 'pending': ['label-default'],
                                    'success': ['label-success'],
                                    'running': ['label-success label-blink'],
                                    'suspended': ['label-success label-blink dynflow-step-suspended'],
                                    'skipping': ['label-warning'],
                                    'skipped': ['label-warning'],
                                    'error': ['label-danger'],
                                    'else': ['label-default'],
                                  }
                    scope.cssClass = (mapping[value] || mapping['else']).join(' ');
                });
            }
        }
    }])
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
    .controller('WorldsIndexController', ['$scope', 'World', function($scope, World) {
        $scope.worlds = World.query();
    }])
    .config(function ($stateProvider, $urlRouterProvider) {
        //
        // For any unmatched url, redirect to /state1
        $urlRouterProvider.otherwise("/execution_plans");
        //
        // Now set up the states
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
            .state('worlds', {
                abstract: true,
                template: '<ui-view/>'
            })
            .state('worlds.index', {
                url: "/worlds",
                templateUrl: "views/worlds.index.html",
                controller: "WorldsIndexController"
            })
    });
