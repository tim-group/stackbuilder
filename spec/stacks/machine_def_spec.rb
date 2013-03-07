require 'stacks/environment'
require 'stacks/machine_def'

describe Stacks::MachineDef do

  it 'produces x.net.local for the prod network' do
    machinedef = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("env", {:primary=>"st"}, {})
    machinedef.bind_to(env)
    machinedef.prod_fqdn.should eql("env-test.st.net.local")
  end
end
