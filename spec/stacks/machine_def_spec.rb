require 'stacks/environment'
require 'stacks/machine_def'

describe Stacks::MachineDef do

  class MockMachineDef < Stacks::MachineDef
    attr_accessor :parent

  end
#
#  def getMockMachineDefWithHostname(h)
#    machinedef = MockMachineDef.new("test")
#    machinedef.local_hostname = h
#    machinedef
#  end

  it 'produces x.net.local for the prod network' do
    machinedef = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("env", {:primary_site=>"st"}, {})
    machinedef.bind_to(env)
    machinedef.prod_fqdn.should eql("env-test.st.net.local")
  end


  it 'produces a machine with the correct hostname when running locally' do
    machinedef = MockMachineDef.new("refapp-001")
    env = Stacks::Environment.new("test", {:primary_site=>"local"}, {})
    machinedef.parent = 'machinex'
    machinedef.bind_to(env)
    machinedef.fabric.should eql("local")
    machinedef.domain.should eql("machinex.net.local")
    machinedef.prod_fqdn.should eql("test-refapp-001.machinex.net.local")
    machinedef.mgmt_fqdn.should eql("test-refapp-001.mgmt.machinex.net.local")
  end

  it 'produces a machine with the correct hostname when running locally and parent hostname is fqdn' do
    machinedef = MockMachineDef.new("refapp-001")
    env = Stacks::Environment.new("test", {:primary_site=>"local"}, {})
    machinedef.parent = 'sto-kvm-001.youdevise.com'
    machinedef.bind_to(env)
    machinedef.fabric.should eql("local")
    machinedef.domain.should eql("sto-kvm-001.net.local")
    machinedef.prod_fqdn.should eql("test-refapp-001.sto-kvm-001.net.local")
    machinedef.mgmt_fqdn.should eql("test-refapp-001.mgmt.sto-kvm-001.net.local")
  end
end
