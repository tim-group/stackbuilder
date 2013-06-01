require 'stacks/hosts/hosts'
require 'stacks/hosts/host_preference'

describe Stacks::Hosts::HostPreference do
  it 'does shit' do
    preference_function = Proc.new do |host|
      host.machines.size
    end

    h1 = Stacks::Hosts::Host.new("h1")
    h2 = Stacks::Hosts::Host.new("h2")
    h3 = Stacks::Hosts::Host.new("h3")

    h1.allocated_machines << "x"
    hosts = [h3,h1,h2]
    hosts.sort_by {|host| [preference_function.call(host), host.fqdn]}.map {|host| host.fqdn}.should eql(["h2","h3","h1"])
  end

  it 'rejects' do
    preference_function = Proc.new do |host|
      host.machines.size
    end

    h1 = Stacks::Hosts::Host.new("h1")
    h2 = Stacks::Hosts::Host.new("h2")
    h3 = Stacks::Hosts::Host.new("h3")

    h1.allocated_machines << "x"
    hosts = [h3,h1,h2]
    hosts.sort_by {|host| [preference_function.call(host), host.fqdn]}.map {|host| host.fqdn}.should eql(["h2","h3","h1"])
  end

end