require 'allocator/host'
require 'stacks/factory'

describe StackBuilder::Allocator::Host do
  it 'removes the ha policy when using local fabric' do
    policies =  Stacks::Factory.new.policies
    policies.size.should eql(6)

    storage = { :used => '1.0' }
    h1 = StackBuilder::Allocator::Host.new("h1", :policies => policies, :storage => storage)
    h1.relevant_policies("latest").length.should eql(6)
    h1.relevant_policies("local").length.should eql(5)
  end
end
