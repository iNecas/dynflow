angular.module('Dynflow.execution-plans')
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
    }]);
