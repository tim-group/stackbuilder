require 'stacks/namespace'
require 'allocator/host_repository'
require 'allocator/ephemeral_allocator'

describe StackBuilder::Allocator::EphemeralAllocator do
  before do
    extend Stacks::DSL
  end

  it 'provides lists of already allocated and newly allocated hosts' do
    candidate_machine = {
      :hostname=>"candidate_machine"
    }

    existing_machine = {
      :hostname => "existing machine"
    }

    h1 = StackBuilder::Allocator::Host.new("h1")
    h1.allocated_machines << existing_machine

    hosts = StackBuilder::Allocator::Hosts.new(:hosts => [h1], :preference_functions => [])

    host_repository = double
    host_repository.stub(:find_current).and_return(hosts)

    allocator = StackBuilder::Allocator::EphemeralAllocator.new(:host_repository => host_repository)

    allocation_result = allocator.allocate([candidate_machine, existing_machine])

    allocation_result[:already_allocated].should eql({existing_machine => 'h1'})
    allocation_result[:newly_allocated].should eql({'h1' => [candidate_machine]})
  end

end
