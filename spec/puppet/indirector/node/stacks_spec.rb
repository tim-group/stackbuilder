require 'puppet'
require 'puppet/indirector/node/stacks'
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

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

    indirector = Puppet::Node::Stacks.new(@stacks_inventory, @delegate, false)
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

    indirector = Puppet::Node::Stacks.new(@stacks_inventory, @delegate, false)
    result = indirector.find(request)

    node.parameters['logicalenv'].should eql('testenv')

    result.should eql(node)
    # it is super-shitty that this is tested by reproducing the entire config,
    # but Puppet::Node::Stacks does not lend itself to mocking this
    result.classes.should eql("role::http_app" => { "application" => "JavaHttpRef" })
  end

  it 'should dump a copy of the enc data for each node to local disk and log requests' do
    tmp_dir = Dir.mktmpdir
    enc_dir = "#{tmp_dir}/stacks/enc"
    log_file = "#{tmp_dir}/stacks/enc.log"

    begin
      hostname = 'te-stapp-001.mgmt.local.net.local'
      dump_file = "#{enc_dir}/#{hostname}.yaml"
      request = request_for(hostname)
      node = node_for(hostname)
      @delegate.should_receive(:find).with(request).and_return(node)
      machine = double('machine')
      machine.stub(:environment).and_return(Stacks::Environment.new("testenv", {}, nil, {}, {}))
      @stacks_inventory.should_receive(:find).with(hostname).and_return(machine)
      machine.should_receive(:to_enc).and_return("role::http_app" => { "application" => "JavaHttpRef" })
      indirector = Puppet::Node::Stacks.new(@stacks_inventory, @delegate, true, enc_dir, log_file)
      indirector.find(request)

      File.exist?(dump_file).should eql(true)
      dumped_enc = YAML.load_file(dump_file)
      dumped_enc.should eql("role::http_app" => { "application" => "JavaHttpRef" })

      File.exist?(log_file).should eql(true)
      log_contents = File.read(log_file)
      log_contents.should include('Node found: te-stapp-001.mgmt.local.net.local')

    ensure
      FileUtils.remove_entry_secure tmp_dir
    end
  end
end
