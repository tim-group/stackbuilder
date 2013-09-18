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
    Stacks::Hosts::HostPolicies.ha_group().call(h1, machines[1]).should eql(true)
  end

  it 'rejects allocations that allocate >1 machine of the same group to the same host' do
    env = test_env_with_refstack
    machines = env.flatten
    h1 = Stacks::Hosts::Host.new("h1")
    h1.allocated_machines << machines[0]
    Stacks::Hosts::HostPolicies.ha_group().call(h1, machines[1]).should eql(false)
  end

  it 'allows allocation if the availability group is unset' do
    machine = double
    running_machine= double
    
    machine.stub(:availability_group).and_return(nil)
    running_machine.stub(:availability_group).and_return(nil)

    h1 = Stacks::Hosts::Host.new("h1")
    h1.allocated_machines << running_machine
    Stacks::Hosts::HostPolicies.ha_group().call(h1, machine).should eql(true)
  end

  it 'allows allocations where the host ram is sufficient' do
    env = test_env_with_refstack
    machines = env.flatten
    h1 = Stacks::Hosts::Host.new("h1", :ram => '4194304')
    h1.allocated_machines << machines[0]
    Stacks::Hosts::HostPolicies.ha_group().call(h1, machines[1]).should eql(true)
  end

  it 'rejects allocations where the host ram is insufficient' do
    env = test_env_with_refstack
    machines = env.flatten
    h1 = Stacks::Hosts::Host.new("h1", :ram => '4194303')
    h1.allocated_machines << machines[0]
    Stacks::Hosts::HostPolicies.ha_group().call(h1, machines[1]).should eql(false)
  end
end
