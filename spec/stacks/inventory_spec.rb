require 'stacks/environment'
require 'stacks/inventory'

describe Stacks::Inventory do

  before :each do
    @stacks_dir = File.dirname(__FILE__) + '/teststack'
  end

  it 'blows up if there is no stacks file in the specified directory' do
    expect {
      Stacks::Inventory.new('/dev') # pretty sure that this will exist, and not contain a stack.rb
    }.to raise_error("no stack.rb found in /dev")
  end

  it 'returns nil when asked to find an unknown node' do
    hostname = 'nosuch.mgmt.local.net.local'

    inventory = Stacks::Inventory.new(@stacks_dir)
    result = inventory.find(hostname)

    result.should eql(nil)
  end

  it 'finds known nodes' do
    hostname = 'te-stapp-001.mgmt.dev.net.local'

    inventory = Stacks::Inventory.new(@stacks_dir)
    result = inventory.find(hostname)

    result.hostname.should eql("te-stapp-001")
    result.domain.should eql("dev.net.local")
    result.vip_fqdn.should eql("te-stapp-vip.local.net.local")
  end

end
