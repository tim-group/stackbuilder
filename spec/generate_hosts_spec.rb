require 'ipaddr'
require 'pp'

module NetDSL
  class HostsFile
    def initialize(file)

    end

    def load()

    end

    def save()

    end
  end

  class Network
    def initialize(name, options)
      @name = name
      @options = options
      @hosts = {}
      @net = IPAddr.new(options[:range])
      @hosts_file = Host
    end

    def allocate(host)
      return unless @hosts[host].nil?
      max = @hosts.values.max
      if max.nil?
        ip = @net.to_range.first.succ.succ
      else
        ip = IPAddr.new(max).succ
      end
      @hosts[host] = ip.to_s
    end
  end

  def net(name, options)
    return Network.new(name,options)
  end
end

describe "generate_hosts" do

  it 'can allocate new ips'
  it 'can write hosts->ip mappings to a file' 
  it 'can read hosts back in'
  it 'calls things sensible things'

  it 'returns preallocated ips' do
    extend NetDSL
    mgmt = net "mgmt", :range=>"192.168.1.0/32"
    prod = net "prod", :range=>"192.168.2.0/32"

    mgmt.allocate("dev-puppetmaster")
    mgmt.allocate("dev-lb")
    mgmt.allocate("dev-puppetmaster")
    

    pp mgmt
#    network = IPAddr.new("192.168.0.0/16")

#    pp network.to_range.first.succ.succ
  end

end
