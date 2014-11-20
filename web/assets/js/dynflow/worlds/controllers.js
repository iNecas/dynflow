angular.module('Dynflow.worlds')
    .controller('WorldsIndexController', ['$scope', 'World', function($scope, World) {
        $scope.worlds = World.query();
    }]);
