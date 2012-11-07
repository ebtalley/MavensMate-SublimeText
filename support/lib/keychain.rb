# Simple interface for reading and writing Internet passwords to
# the KeyChain.
require SUPPORT + '/lib/os.rb'

module KeyChain
  class << self
    def add_generic_password(account, service, password)
      if MavensMate::OS.mac? then
        %x{security add-generic-password -a #{account} -s \"MavensMate: #{service}\" -w #{password} -U}
      elsif MavensMate::OS.linux? or MavensMate::OS.windows? then
        %x("#{ROOT}/bin/keyring-cli.py" set "MavensMate: #{service}" "#{account}" "#{password}")
      end
    end
    def find_generic_password(account, service)
      if MavensMate::OS.mac? then
        result = %x{security find-generic-password -ga "#{account}" -s \"MavensMate: #{service}\" 2>&1 >/dev/null}
        result =~ /^password: "(.*)"$/ ? $1 : nil
      elsif MavensMate::OS.linux? or MavensMate::OS.windows? then
        %x("#{ROOT}/bin/keyring-cli.py" get "MavensMate: #{service}" "#{account}").strip
      end
    end
    def add_internet_password(user, proto, host, path, pass)
      if MavensMate::OS.mac? then
        %x{security add-internet-password -a "#{user}" -s "#{host}" -r "#{proto}" -p "#{path}" -w "#{pass}"}
      elsif MavensMate::OS.linux? or MavensMate::OS.windows? then
        %x("#{ROOT}/bin/keyring-cli.py" set "MavensMate: #{service}" "#{account}" "#{pass}")
      end
    end
    def find_internet_password(aname)
      if MavensMate::OS.mac? then
        result = %x{security find-generic-password -ga "#{aname}" 2>&1 >/dev/null}
        result =~ /^password: "(.*)"$/ ? $1 : nil
      elsif MavensMate::OS.linux? or MavensMate::OS.windows? then
        %x("#{ROOT}/bin/keyring-cli.py" get "MavensMate: #{aname}" "#{aname}").strip
      end
    end
  end
end
