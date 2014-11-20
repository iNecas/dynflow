angular.module('Dynflow.worlds')
    .factory('World', ['$resource', function ($resource) {
        var resource = $resource('./api/worlds', {});
        return resource;
    }]);
