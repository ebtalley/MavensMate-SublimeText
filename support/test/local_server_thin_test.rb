require "test/unit"
require  File.join(File.expand_path(File.dirname(__FILE__)), './test_helper.rb')

# require_relative '../../constants.rb'
require  File.join(File.expand_path(File.dirname(__FILE__)), '../../constants.rb')
include Constants

require LIB_ROOT + '/mavensmate.rb'
require LIB_ROOT + '/lsof.rb'
require LIB_ROOT + '/local_server_thin.rb'


class LocalServerTests < Test::Unit::TestCase
  def test_start_stop
    MavensMate::LocalServerThin::stop
    assert !(Lsof::running? 7777)
    pid = Process.spawn("ruby -r #{ENV['TM_BUNDLE_SUPPORT']}/lib/local_server_thin.rb -e 'MavensMate::LocalServerThin.start'", :out => '/dev/null')
    Process.detach pid
    sleep 1
    assert Lsof::running? 7777
    MavensMate::LocalServerThin::stop
    assert !(Lsof::running? 7777)
  end
end
