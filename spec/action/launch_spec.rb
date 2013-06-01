### TODO
##    use HostRepository in test so that when Hosts are build the prefs can be set
##    there
##    define correct way to add policies and preference algo
## =>   remove the need for set_preference_functions
# =>    move files into main source tree
#
#     plumbing
##
require 'stacks/hosts/host_repository'
require 'stacks/hosts/hosts'
require 'stacks/hosts/host_preference'
require 'stacks/core/services'
require 'stacks/core/actions'


describe 'launch' do

  it 'creates a Hosts object with corresponding Host objects' do
    env = test_env_with_refstack
    machines = env.flatten.map {|machine| machine.hostname}

    compute_node_client = double
    n = 5
    result = {}
    n.times do |i|
      result["h#{i}"] = {
        :active_domains=>machines
      }
    end

    preference_functions = []
    compute_node_client.stub(:audit_hosts).and_return(result)

    host_repo = HostRepository.new(
      :machine_repo => self,
      :preference_functions=>preference_functions,
      :compute_node_client => compute_node_client)

    hosts = host_repo.find_current("t")
    hosts.hosts.size.should eql(n)
    hosts.hosts.each do |host|
      host.preference_functions.should eql(preference_functions)
      host.machines.should eql(env.flatten)
    end
  end

  before do
    extend Stacks::DSL
    extend Stacks::Actions
  end

  def test_env_with_refstack
    stack "ref" do
      virtual_appserver "refapp"
    end

    env "test", :primary_site => "t" do
      instantiate_stack "ref"
    end

    find_environment("test")
  end

  def standard_preference_functions
    return [Stacks::Hosts::HostPreference.least_machines(), Stacks::Hosts::HostPreference.alphabetical_fqdn]
  end

  def host_repo_with_hosts(n, preference_functions=standard_preference_functions, &block)
    compute_node_client = double

    result = {}
    n.times do |i|
      result["h#{i}"] = {
        :active_vms=>[]
      }
    end

    compute_node_client.stub(:audit_hosts).and_return(result)

    host_repox = HostRepository.new(
      :preference_functions=>preference_functions,
      :compute_node_client => compute_node_client)

      host_repo = double
      hosts = []
      n.times do |i|
        host = Stacks::Hosts::Host.new("h#{i+1}")
        block.call(host,i) unless block.nil?
        hosts << host
      end

      host_repo.stub(:find_current).and_return(Stacks::Hosts::Hosts.new(:hosts=>hosts, :preference_functions=>preference_functions))
      host_repo
  end

  it 'gives me a list of machines that I want to launch but are already launched' do
    env = test_env_with_refstack
    hx = Stacks::Hosts::Host.new("hx")
    hx.allocated_machines=env.flatten
    hosts = Stacks::Hosts::Hosts.new(:hosts => [hx])

    hosts.hosts.each do |host|
      pp host.fqdn
      pp host.allocated_machines
    end

  end

  it 'will allocate machines to machines in the correct fabric' do

  end

  it 'will allocate and launch a bunch of machines' do
    env = test_env_with_refstack
    compute_controller = double
    services = Services.new(
      :host_repo => host_repo_with_hosts(3),
      :compute_controller=> compute_controller)

      compute_controller.should_receive(:launch).with(
        "h1" => [find("test-refapp-001.mgmt.t.net.local").to_spec],
        "h2" => [find("test-refapp-002.mgmt.t.net.local").to_spec]
      )

      get_action("launch").call(services, env)
  end

  it 'will not allocate machines that are already allocated' do
    env = test_env_with_refstack
    compute_controller = double
    host_repo = host_repo_with_hosts(2) do |host,i|
      host.allocated_machines << find("test-refapp-001.mgmt.t.net.local")
    end
    services = Services.new(
      :host_repo => host_repo,
      :compute_controller=> compute_controller)

      compute_controller.should_receive(:launch).with(
        "h1" => [find("test-refapp-002.mgmt.t.net.local").to_spec]
      )

      get_action("launch").call(services, env)
  end

  it 'will not allocate to the machine with the highest preference' do
    env = test_env_with_refstack
    compute_controller = double

    chooseh3 = Proc.new do |host|
      if host.fqdn =~/h3/
        0
      else
        1
      end
    end

    host_repo = host_repo_with_hosts(3, [chooseh3])

    services = Services.new(
      :host_repo => host_repo,
      :compute_controller=> compute_controller)

      compute_controller.should_receive(:launch).with(
        "h3" => [find("test-refapp-001.mgmt.t.net.local").to_spec,
          find("test-refapp-002.mgmt.t.net.local").to_spec]
      )

      get_action("launch").call(services, env)
  end

  it 'will not allocate to a machine that fails a policy' do
    env = test_env_with_refstack
    compute_controller = double
    host_repo = host_repo_with_hosts(3) do |host, i|
      host.add_policy do |host, machine|
        host.fqdn !~ /h2/
      end
    end

    services = Services.new(
      :host_repo => host_repo,
      :compute_controller=> compute_controller)

      compute_controller.should_receive(:launch).with(
        "h1" => [find("test-refapp-001.mgmt.t.net.local").to_spec],
        "h3" => [find("test-refapp-002.mgmt.t.net.local").to_spec]
      )

      get_action("launch").call(services, env)
  end


  ha_policy = Proc.new do |host, machine|
    host.machines.each do |m|
      if m.group == machine.group
        NO
      end
    end
  end

  enough_ram_policy = Proc.new do |host, machine|
    host.ram - machine.ram >0
  end

end
