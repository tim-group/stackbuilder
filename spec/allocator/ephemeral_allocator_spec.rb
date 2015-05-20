require 'allocator/ephemeral_allocator'
require 'stacks/factory'

describe StackBuilder::Allocator::EphemeralAllocator do
  before do
    extend Stacks::DSL
  end

  it 'provides lists of already allocated and newly allocated hosts' do
    candidate_machine = {
      :hostname => "candidate_machine",
      :fabric => "f1"
    }

    candidate_machine_2 = {
      :hostname => "candidate_machine_2",
      :fabric => "f2"
    }

    existing_machine = {
      :hostname => "existing machine",
      :fabric => "f1"
    }

    h1 = StackBuilder::Allocator::Host.new("h1")
    h1.allocated_machines << existing_machine

    h2 = StackBuilder::Allocator::Host.new("h2")

    hosts = StackBuilder::Allocator::Hosts.new(:hosts => [h1], :preference_functions => [])
    f2_hosts = StackBuilder::Allocator::Hosts.new(:hosts => [h2], :preference_functions => [])

    host_repository = double
    host_repository.stub(:find_compute_nodes).with("f1").and_return(hosts)
    host_repository.stub(:find_compute_nodes).with("f2").and_return(f2_hosts)

    allocator = StackBuilder::Allocator::EphemeralAllocator.new(:host_repository => host_repository)

    allocation_result = allocator.allocate([candidate_machine, candidate_machine_2, existing_machine])

    allocation_result[:already_allocated].should eql(existing_machine => 'h1')
    allocation_result[:newly_allocated].should eql(
      'h1' => [candidate_machine],
      'h2' => [candidate_machine_2])
  end
end
