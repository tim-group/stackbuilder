require 'stacks/environment'

describe Stacks::Services::NatServer do
  it 'has access to the front, prod and mgmt networks' do
    class Group
      attr_accessor :name
      def initialize(name)
        @name = name
      end
    end
    machinedef = Stacks::Services::NatServer.new(Group.new("my-nat-server"), "001")
    env = Stacks::Environment.new("noenv", { :primary_site => "local" }, nil, {}, {})
    machinedef.bind_to(env)
    machinedef.to_spec[:networks].should eql [:mgmt, :prod, :front]
  end
end
