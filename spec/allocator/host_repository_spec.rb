require 'allocator/host_repository'
require 'stacks/factory'

describe StackBuilder::Allocator::HostRepository do
  before do
    extend Stacks::DSL
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

  it 'creates a Hosts object with corresponding Host objects' do
    env = test_env_with_refstack
    machines = env.flatten.map(&:hostname)

    compute_node_client = double
    n = 5
    result = {}
    n.times do |i|
      result["h#{i}"] = {
        :active_domains => machines,
        :inactive_domains => []
      }
    end

    preference_functions = []
    compute_node_client.stub(:audit_hosts).and_return(result)

    host_repo = StackBuilder::Allocator::HostRepository.new(
      :machine_repo => self,
      :preference_functions => preference_functions,
      :compute_node_client => compute_node_client)

    hosts = host_repo.find_compute_nodes("t")
    hosts.hosts.size.should eql(n)
    hosts.hosts.each do |host|
      host.preference_functions.should eql(preference_functions)
      host.machines.should eql(env.flatten.map(&:to_specs).flatten)
    end
  end

  it 'includes missing machine specs for machines that do not exist in the model' do
    env = test_env_with_refstack
    machines = env.flatten.map(&:hostname)
    machine_specs = env.flatten.map(&:to_specs).flatten
    machines << "roguemachine"
    machine_specs << { :hostname => "roguemachine", :in_model => false }
    compute_node_client = double
    n = 5
    result = {}
    n.times do |i|
      result["h#{i}"] = {
        :active_domains => machines,
        :inactive_domains => []
      }
    end

    preference_functions = []
    compute_node_client.stub(:audit_hosts).and_return(result)

    host_repo = StackBuilder::Allocator::HostRepository.new(
      :machine_repo => self,
      :preference_functions => preference_functions,
      :compute_node_client => compute_node_client)

    hosts = host_repo.find_compute_nodes("t")
    hosts.hosts.size.should eql(n)
    hosts.hosts.each do |host|
      host.preference_functions.should eql(preference_functions)
      host.machines.should eql(machine_specs)
    end
  end
end
