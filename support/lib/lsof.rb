require SUPPORT + '/lib/os.rb'

class Lsof
  class << self
    def kill(port)
      pids = listener_pids(port)
      pids.uniq!
      if MavensMate::OS.windows? then
        pids.each do |pid|
          %x{taskkill /F /PID #{pid}}
        end
      else
        `kill #{pids.join(' ')}`
      end
    end

    def running?(port)
      listener_pids(port).empty? ? false : true
    end
    
    # this isn't really lsof, but it's solving the same problem
    def running_remotely?(server, port)
      TCPSocket.new(server, port).close rescue return false
      return true
    end

    def listener_pids(port)
      output = `#{find_pids_cmd(port)}`
      output.split("\n").map do |port|
        if  MavensMate::OS.windows? then
          port = port.split(" ").last
        end
        Integer(port)
      end
    end

    def find_pids_cmd(port)
      if MavensMate::OS.windows? then
        #"SET LANG=en_US & netstat -aon | findstr :#{port} | findstr LISTENING"
        "chcp 437 > NUL & netstat -aon | findstr :#{port} | findstr LISTENING"
      else
        "lsof -i tcp:#{port} | grep '(LISTEN)' | awk '{print $2}'"
      end
    end
  end
end