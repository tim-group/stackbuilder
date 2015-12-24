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
    expect(@delegate).to receive(:find).with(request).and_return(node)
    expect(@stacks_inventory).to receive(:find).with(hostname).and_return(nil)

    indirector = Puppet::Node::Stacks.new(@stacks_inventory, @delegate, false)
    result = indirector.find(request)

    expect(result).to eql(node)
    expect(result.classes).to eql([])
  end

  it 'uses the inventory\'s classes if it provides any' do
    hostname = 'te-stapp-001.mgmt.local.net.local'
    request = request_for(hostname)
    node = node_for(hostname)
    expect(@delegate).to receive(:find).with(request).and_return(node)
    machine = double('machine')
    allow(machine).to receive(:environment).and_return(Stacks::Environment.new("testenv", {}, nil, {}, {}, Stacks::CalculatedDependenciesCache.new))
    expect(@stacks_inventory).to receive(:find).with(hostname).and_return(machine)
    expect(machine).to receive(:to_enc).and_return("role::http_app" => { "application" => "JavaHttpRef" })

    indirector = Puppet::Node::Stacks.new(@stacks_inventory, @delegate, false)
    result = indirector.find(request)

    expect(node.parameters['logicalenv']).to eql('testenv')

    expect(result).to eql(node)
    # it is super-shitty that this is tested by reproducing the entire config,
    # but Puppet::Node::Stacks does not lend itself to mocking this
    expect(result.classes).to eql("role::http_app" => { "application" => "JavaHttpRef" })
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
      expect(@delegate).to receive(:find).with(request).and_return(node)
      machine = double('machine')
      allow(machine).to receive(:environment).and_return(Stacks::Environment.new("testenv", {}, nil, {}, {}, Stacks::CalculatedDependenciesCache.new))
      expect(@stacks_inventory).to receive(:find).with(hostname).and_return(machine)
      expect(machine).to receive(:to_enc).and_return("role::http_app" => { "application" => "JavaHttpRef" })
      indirector = Puppet::Node::Stacks.new(@stacks_inventory, @delegate, true, enc_dir, log_file)
      indirector.find(request)

      expect(File.exist?(dump_file)).to eql(true)
      dumped_enc = YAML.load_file(dump_file)
      expect(dumped_enc).to eql("role::http_app" => { "application" => "JavaHttpRef" })

      expect(File.exist?(log_file)).to eql(true)
      log_contents = File.read(log_file)
      expect(log_contents).to include('Node found: te-stapp-001.mgmt.local.net.local')

    ensure
      FileUtils.remove_entry_secure tmp_dir
    end
  end
end
