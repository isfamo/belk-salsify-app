module.exports = function(config) {
    config.set({
        files: [

            'http://ajax.googleapis.com/ajax/libs/jquery/1.12.4/jquery.min.js',
            'http://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js',

            'http://ajax.googleapis.com/ajax/libs/angularjs/1.5.8/angular.min.js',
            'http://ajax.googleapis.com/ajax/libs/angularjs/1.5.8/angular-route.min.js',
            'http://ajax.googleapis.com/ajax/libs/angularjs/1.5.8/angular-cookies.min.js',
            'http://cdnjs.cloudflare.com/ajax/libs/moment.js/2.15.2/moment.min.js',

            '../app/js/**/*.js',

            'mock/*.js',

            './tests/**/*.test.js',
            '../app/templates/**/*.html'

        ],

        autoWatch: true,
        singleRun: false,

        frameworks: ['jasmine'],

        // browsers: ['Chrome', 'Firefox', 'Safari', 'PhantomJS'],
        browsers: ['Chrome'],

        preprocessors: {
            '../app/js/**/*.js': 'coverage',
            '../app/js/*.js': 'coverage',
            '../app/templates/**/*.html': 'ng-html2js'
        },
        exclude: ['../app/lib/bootstrap-treeview.js'],
        reporters: ['progress', 'coverage'],
        coverageReporter: {
            reporters: [
                { type: 'lcov', dir: '../reports/coverage', subdir: 'unit' }
            ]
        }

    });
};
