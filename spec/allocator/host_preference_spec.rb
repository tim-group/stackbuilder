require 'allocator/hosts'
require 'allocator/host_preference'

describe StackBuilder::Allocator::HostPreference do
  it 'does shit' do
    preference_function = Proc.new do |host|
      host.machines.size
    end

    h1 = StackBuilder::Allocator::Host.new("h1")
    h2 = StackBuilder::Allocator::Host.new("h2")
    h3 = StackBuilder::Allocator::Host.new("h3")

    h1.allocated_machines << "x"
    hosts = [h3, h1, h2]
    hosts.sort_by { |host| [preference_function.call(host), host.fqdn] }.map { |host| host.fqdn }.should eql(["h2", "h3", "h1"])
  end

  it 'rejects' do
    preference_function = Proc.new do |host|
      host.machines.size
    end

    h1 = StackBuilder::Allocator::Host.new("h1")
    h2 = StackBuilder::Allocator::Host.new("h2")
    h3 = StackBuilder::Allocator::Host.new("h3")

    h1.allocated_machines << "x"
    hosts = [h3, h1, h2]
    hosts.sort_by { |host| [preference_function.call(host), host.fqdn] }.map { |host| host.fqdn }.should eql(["h2", "h3", "h1"])
  end

end
