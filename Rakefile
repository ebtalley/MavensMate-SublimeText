require 'simplecov'
require 'rake/testtask'

desc "run all unit tests"
Rake::TestTask.new do |t|
	SimpleCov.configure do
		command_name 'test_all'
		add_filter 'support/test/*test.rb'
	end
	SimpleCov.start if ENV["COVERAGE"]
	t.libs = []
	t.name = "test_all"
	t.test_files = FileList['support/test/*test.rb']
end

task :default => [:test_all]
