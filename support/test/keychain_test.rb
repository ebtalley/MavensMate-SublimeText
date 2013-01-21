require "test/unit"

require_relative '../../constants.rb'
include Constants

require LIB_ROOT + '/mavensmate.rb'
require LIB_ROOT + '/keychain.rb'

class KeyChainTests < Test::Unit::TestCase
  def test_keychain
    account = 'testaccount'
    service = 'testservice'
    pw = 'testpassword'
    KeyChain::add_generic_password(account, service, pw)
    assert_equal(pw, KeyChain::find_generic_password(account, service))
  end

  def test_keychain_no_password
    assert_equal('', KeyChain::find_generic_password('testaccountwhichdoesnotexist', 'testservicewhichdoesnotexist'))
  end
end
