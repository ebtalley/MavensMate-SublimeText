require 'rake/testtask'

desc "run all unit tests"
Rake::TestTask.new do |t|
	t.libs = []
	t.name = "test_all"
	t.test_files = FileList['support/test/*test.rb']
end

task :default => [:test_all]
