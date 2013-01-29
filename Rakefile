require 'rake/testtask'

desc "run all unit tests"
Rake::TestTask.new do |t|
	t.libs = []
	t.name = "test_all"
	t.test_files = FileList['support/test/*test.rb']
end

desc "run all unit tests and generate test coverage"
Rake::TestTask.new do |t|
	require 'simplecov'
	SimpleCov.configure do
		command_name 'test_all_with_coverage'
		add_filter 'support/test/*test.rb'
	end
	SimpleCov.start
	t.libs = []
	t.name = "test_all_with_coverage"
	t.test_files = FileList['support/test/*test.rb']
end

task :default => [:test_all]
