require 'stacks/environment'

describe Stacks::NatServer do

  subject do
    Stacks::NatServer.new("my-nat-server")
  end

  it 'has access to the front, prod and mgmt networks' do

    subject.to_specs[0][:networks].should eql [:mgmt,:prod,:front]
  end
end
