require 'stacks/hosts/hosts'
require 'stacks/hosts/host_policies'

describe Stacks::Hosts::HostPolicies do
  before do
    @machine_repo = Object.new
    @machine_repo.extend Stacks::DSL
  end

  def test_env_with_refstack
    @machine_repo.stack "ref" do
      virtual_appserver "refapp"
    end

    @machine_repo.env "test", :primary_site => "t" do
      instantiate_stack "ref"
    end

    @machine_repo.find_environment("test")
  end

  it 'allows allocations that have no machine of the same group to the same host' do
    env = test_env_with_refstack
    machines = env.flatten
    h1 = Stacks::Hosts::Host.new("h1")
    Stacks::Hosts::HostPolicies.ha_group_policy().call(h1, machines[1]).should eql(true)
  end

  it 'rejects allocations that allocate >1 machine of the same group to the same host' do
    env = test_env_with_refstack
    machines = env.flatten
    h1 = Stacks::Hosts::Host.new("h1")
    h1.allocated_machines << machines[0]
    Stacks::Hosts::HostPolicies.ha_group_policy().call(h1, machines[1]).should eql(false)
  end

end