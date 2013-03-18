require 'puppet'
require 'puppet/indirector/node/stacks'

describe Puppet::Node::Stacks do

  before :each do
    @stacks_dir = File.dirname(__FILE__)
    @delegate = double
  end

  def request_for(hostname)
    # this is what requests look like in the wild
    Puppet::Indirector::Request.new(:node, :find, hostname, nil)
  end

  def node_for(hostname)
    Puppet::Node.new(hostname)
  end

  it 'blows up if there is no stacks file in the specified directory' do
    expect {
      Puppet::Node::Stacks.new('/dev') # pretty sure that this will exist, and not contain a stacks.rb
    }.to raise_error("no stacks.rb found in /dev")
  end

  it 'passes requests on to a delegate to produce an empty node' do
    hostname = 'nosuch.mgmt.local.net.local'
    request = request_for(hostname)
    node = node_for(hostname)
    @delegate.should_receive(:find).with(request).and_return(node)

    indirector = Puppet::Node::Stacks.new(@stacks_dir, @delegate)
    result = indirector.find(request)

    result.should eql(node)
    result.classes.should eql([])
  end

  it 'uses the inventory\'s classes if it provides any' do
    hostname = 'te-stapp-001.mgmt.local.net.local'
    request = request_for(hostname)
    node = node_for(hostname)
    @delegate.should_receive(:find).with(request).and_return(node)

    indirector = Puppet::Node::Stacks.new(@stacks_dir, @delegate)
    result = indirector.find(request)

    result.should eql(node)
    # it is super-shitty that this is tested by reproducing the entire config, but Puppet::Node::Stacks does not lend itself to mocking this
    result.classes.should eql({"role::http_app"=>{"application"=>"JavaHttpRef", "group"=>"blue", "environment"=>"te", "vip_fqdn"=>"te-stapp-vip.local.net.local"}})
  end

end
