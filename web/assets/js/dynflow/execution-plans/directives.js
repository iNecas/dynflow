angular.module('Dynflow.execution-plans')
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
