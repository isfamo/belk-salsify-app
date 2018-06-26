'use strict';

module.exports = function(grunt) {
    grunt.loadNpmTasks('grunt-ngdocs');

    grunt.initConfig({
        ngdocs: {
            options: {
                dest: 'docs',
                title: "Docs",
                image: "app/assets/logo.png",
                inlinePartials: true
            },
            all: ['app/js/**/*.js']
        }
    });
};
