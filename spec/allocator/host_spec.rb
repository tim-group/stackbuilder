require 'allocator/host'
require 'stacks/factory'

describe StackBuilder::Allocator::Host do

#FIXME: Remove this test once storage exists for all nodes
  it 'selects only relevant policies when storage is nil' do


    h1 = StackBuilder::Allocator::Host.new("h1", {:policies => Stacks::Factory.new.policies})
    h1.relevant_policies.length.should eql(3)

  end

end
