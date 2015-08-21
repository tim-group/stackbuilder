require 'stackbuilder/stacks/factory'

describe Stacks::Inventory do
  before :each do
    @stacks_dir = File.dirname(__FILE__) + '/teststack'
  end

  it 'blows up if a stackbuilder config file contains errors' do
    expect do
      Dir.mktmpdir("stacks-test-config") do |dir|
        File.open("#{dir}/ruby_file_with_errors.rb", 'w') do |file|
          file.write("burp!")
        end
        Stacks::Inventory.new(dir)
      end
    end.to raise_error
  end

  it 'returns nil when asked to find an unknown node' do
    hostname = 'nosuch.mgmt.space.net.local'

    inventory = Stacks::Inventory.new(@stacks_dir)
    result = inventory.find(hostname)

    result.should eql(nil)
  end

  it 'finds known nodes' do
    hostname = 'te-stapp-001.mgmt.space.net.local'

    inventory = Stacks::Inventory.new(@stacks_dir)
    result = inventory.find(hostname)

    result.hostname.should eql("te-stapp-001")
    result.domain.should eql("space.net.local")
    result.virtual_service.vip_fqdn(:prod, 'space').should eql("te-stapp-vip.space.net.local")
  end
end
