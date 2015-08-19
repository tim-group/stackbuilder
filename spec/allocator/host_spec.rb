require 'stackbuilder/allocator/host'
require 'stackbuilder/stacks/factory'

describe StackBuilder::Allocator::Host do
  it 'removes the ha policy when using local fabric' do
    policies =  Stacks::Factory.new.policies
    expect(policies.size).to eql(6)

    storage = { :used => '1.0' }
    h1 = StackBuilder::Allocator::Host.new("h1", :policies => policies, :storage => storage)
    expect(h1.relevant_policies("latest").length).to eql(6)
    expect(h1.relevant_policies("local").length).to eql(5)
  end
end
