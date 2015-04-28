require 'puppet'
require 'puppet/indirector/node/stacks'

describe Puppet::Node::Stacks do
  before :each do
    @stacks_inventory = double('stacks_inventory')
    @delegate = double('delegate')
  end

  def request_for(hostname)
    # this is what requests look like in the wild
    Puppet::Indirector::Request.new(:node, :find, hostname, nil)
  end

  def node_for(hostname)
    Puppet::Node.new(hostname)
  end

  it 'passes requests on to a delegate to produce an empty node' do
    hostname = 'nosuch.mgmt.local.net.local'
    request = request_for(hostname)
    node = node_for(hostname)
    @delegate.should_receive(:find).with(request).and_return(node)
    @stacks_inventory.should_receive(:find).with(hostname).and_return(nil)

    indirector = Puppet::Node::Stacks.new(@stacks_inventory, @delegate)
    result = indirector.find(request)

    result.should eql(node)
    result.classes.should eql([])
  end

  it 'uses the inventory\'s classes if it provides any' do
    hostname = 'te-stapp-001.mgmt.local.net.local'
    request = request_for(hostname)
    node = node_for(hostname)
    @delegate.should_receive(:find).with(request).and_return(node)
    machine = double('machine')
    machine.stub(:environment).and_return(Stacks::Environment.new("testenv", {}, nil, {}, {}))
    @stacks_inventory.should_receive(:find).with(hostname).and_return(machine)
    machine.should_receive(:to_enc).and_return("role::http_app" => { "application" => "JavaHttpRef" })

    indirector = Puppet::Node::Stacks.new(@stacks_inventory, @delegate)
    result = indirector.find(request)

    node.parameters['logicalenv'].should eql('testenv')

    result.should eql(node)
    # it is super-shitty that this is tested by reproducing the entire config,
    # but Puppet::Node::Stacks does not lend itself to mocking this
    result.classes.should eql("role::http_app" => { "application" => "JavaHttpRef" })
  end
end
