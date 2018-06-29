require 'stackbuilder/allocator/ephemeral_allocator'
require 'stackbuilder/stacks/factory'

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
    allow(host_repository).to receive(:get_fabric_allocator).with("f1").and_return(hosts)
    allow(host_repository).to receive(:get_fabric_allocator).with("f2").and_return(f2_hosts)

    allocator = StackBuilder::Allocator::EphemeralAllocator.new(:host_repository => host_repository)

    allocation_result = allocator.allocate([candidate_machine, candidate_machine_2, existing_machine])

    expect(allocation_result[:already_allocated]).to eql(existing_machine => 'h1')
    expect(allocation_result[:newly_allocated]).to eql(
      'h1' => [candidate_machine],
      'h2' => [candidate_machine_2])
  end
end
