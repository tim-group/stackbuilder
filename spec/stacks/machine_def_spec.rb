require 'stacks/environment'
require 'stacks/machine_def'

describe Stacks::MachineDef do

  it 'produces x.net.local for the prod network' do
    machinedef = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("env", {:primary_site=>"st"}, {})
    machinedef.bind_to(env)
    machinedef.prod_fqdn.should eql("env-test.st.net.local")
  end

  it 'should raise exception is owner fact is missing' do
    module Facter

      def self.initialize
      end

      def self.loadfacts
      end

      def self.value(value)
        nil
      end
    end
    machinedef = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("env", {:primary_site=>"st"}, {})
    expect { machinedef.owner_fact }.to raise_error /Owner fact was not found/

  end
end
