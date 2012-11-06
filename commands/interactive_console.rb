#!/usr/bin/env ruby -W0
require File.dirname(File.dirname(__FILE__)) + "/constants.rb"
include Constants

require LIB_ROOT + "/mavensmate.rb"
require LIB_ROOT + "/local_server.rb"

puts "Current project directory: #{MavensMate::get_project_folder()}"
puts "To load more modules enter: require LIB_ROOT + '/xyz.rb'"