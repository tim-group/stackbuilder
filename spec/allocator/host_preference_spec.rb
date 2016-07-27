require 'stackbuilder/allocator/host_preference'
require 'stackbuilder/stacks/factory'

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
    expect(hosts.sort_by { |host| [preference_function.call(host), host.fqdn] }.map(&:fqdn)).to eql(%w(h2 h3 h1))
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
    expect(hosts.sort_by { |host| [preference_function.call(host), host.fqdn] }.map(&:fqdn)).to eql(%w(h2 h3 h1))
  end

  it 'prefers not G9s' do
    h1 = StackBuilder::Allocator::Host.new("h1", :allocation_tags => ['G7'])
    h2 = StackBuilder::Allocator::Host.new("h2", :allocation_tags => ['Gen9'])
    h3 = StackBuilder::Allocator::Host.new("h3", :allocation_tags => ['G7'])
    h4 = StackBuilder::Allocator::Host.new("h4", :allocation_tags => ['G6'])

    hosts = [h1, h4, h2, h3]
    expect(hosts.sort_by { |host| [StackBuilder::Allocator::HostPreference.prefer_not_g9.call(host), host.fqdn] }.map(&:fqdn)).
      to eql(%w(h1 h3 h4 h2))
  end

  it 'prefers any g9 when requested' do
    h1 = StackBuilder::Allocator::Host.new("h1", :allocation_tags => ['Gen9'])
    h2 = StackBuilder::Allocator::Host.new("h2", :allocation_tags => ['Gen9'])
    h3 = StackBuilder::Allocator::Host.new("h3", :allocation_tags => ['Gen9'])
    h4 = StackBuilder::Allocator::Host.new("h4", :allocation_tags => ['Gen9'])

    hosts = [h1, h4, h2, h3]
    expect(hosts.sort_by { |host| [StackBuilder::Allocator::HostPreference.prefer_not_g9.call(host), host.fqdn] }.map(&:fqdn)).
      to eql(%w(h1 h2 h3 h4))
  end
end
