require 'stacks/environment'

describe Stacks::NatServer do

  subject do

    class Group
      attr_accessor :name

      def initialize(name)
        @name = name
      end
    end

    Stacks::NatServer.new(Group.new("my-nat-server"), "001")
  end

  it 'has access to the front, prod and mgmt networks' do

    subject.to_specs[0][:networks].should eql [:mgmt,:prod,:front]
  end
end
