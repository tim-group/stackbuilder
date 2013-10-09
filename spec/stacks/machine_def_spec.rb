require 'stacks/environment'
require 'stacks/machine_def'

describe Stacks::MachineDef do

  it 'produces x.net.local for the prod network' do
    machinedef = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("env", {:primary_site=>"st"}, {})
    machinedef.bind_to(env)
    machinedef.prod_fqdn.should eql("env-test.st.net.local")
  end

  it 'should set invalid hostname if owner fact is missing for local site' do
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
    env = Stacks::Environment.new("env", {:primary_site=>"local"}, {})
    machinedef.bind_to(env)
    machinedef.hostname.should include('OWNER-FACT-NOT-FOUND')

  end

  it 'should set hostname to include owner fact for local site' do
    module Facter

      def self.initialize
      end

      def self.loadfacts
      end

      def self.value(value)
        'testusername'
      end
    end

    machinedef = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("env", {:primary_site=>"local"}, {})
    machinedef.bind_to(env)
    machinedef.hostname.should include('testusername')
    machinedef.hostname.should_not include('OWNER-FACT-NOT-FOUND')

  end
end
