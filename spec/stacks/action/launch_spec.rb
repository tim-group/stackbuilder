require 'stacks/hosts/host_repository'
require 'stacks/hosts/hosts'
require 'stacks/hosts/host_preference'
require 'stacks/core/services'
require 'stacks/core/actions'

describe 'launch' do
  before do
    extend Stacks::DSL
    extend Stacks::Core::Actions
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
    return [
      Stacks::Hosts::HostPreference.least_machines(),
      Stacks::Hosts::HostPreference.alphabetical_fqdn]
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

    host_repox = Stacks::Hosts::HostRepository.new(
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

  it 'gives me a list of machines that are already launched' do
    env = test_env_with_refstack
    hx = Stacks::Hosts::Host.new("hx")
    hx.allocated_machines=env.flatten
    hosts = Stacks::Hosts::Hosts.new(:hosts => [hx])

    Hash[hosts.allocated_machines(env.flatten).map do |machine, host|
      [ machine.mgmt_fqdn,host.fqdn]
    end].should eql({
      "test-refapp-001.mgmt.t.net.local" => "hx",
      "test-refapp-002.mgmt.t.net.local" => "hx"
    })
  end

  it 'gives me a list of machines that are going to be launched' do
    env = test_env_with_refstack
    hx = Stacks::Hosts::Host.new("hx")
    hosts = Stacks::Hosts::Hosts.new(:hosts => [hx], :preference_functions=>[])

    hosts.allocate(env.flatten)
    Hash[hosts.new_machine_allocation().map do |machine, host|
      [ machine.mgmt_fqdn,host.fqdn]
    end].should eql({
      "test-refapp-001.mgmt.t.net.local" => "hx",
      "test-refapp-002.mgmt.t.net.local" => "hx"
    })
  end

  it 'will allocate machines to machines in the correct fabric' do

  end

  it 'will allocate and launch a bunch of machines' do
    env = test_env_with_refstack
    compute_controller = double
    services = Stacks::Core::Services.new(
    :host_repo => host_repo_with_hosts(3),
    :compute_controller=> compute_controller)

    compute_controller.should_receive(:launch_raw).with(
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
    services = Stacks::Core::Services.new(
    :host_repo => host_repo,
    :compute_controller=> compute_controller)

    compute_controller.should_receive(:launch_raw).with(
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

    services = Stacks::Core::Services.new(
    :host_repo => host_repo,
    :compute_controller=> compute_controller)

    compute_controller.should_receive(:launch_raw).with(
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

    services = Stacks::Core::Services.new(
    :host_repo => host_repo,
    :compute_controller=> compute_controller)

    compute_controller.should_receive(:launch_raw).with(
    "h1" => [find("test-refapp-001.mgmt.t.net.local").to_spec],
    "h3" => [find("test-refapp-002.mgmt.t.net.local").to_spec]
    )

    get_action("launch").call(services, env)
  end

end
