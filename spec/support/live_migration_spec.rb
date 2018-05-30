require 'stackbuilder/allocator/host'
require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/live_migration'

def new_environment(name, options)
  Stacks::Environment.new(name, options, nil, {}, {}, Stacks::CalculatedDependenciesCache.new)
end

describe Support::LiveMigrator do
  before do
    @stacks_factory = double("stacks_factory")
    policies = Stacks::Factory.new.policies
    storage = { :used => '1.0' }
    @source_host = StackBuilder::Allocator::Host.new("source_host", :policies => policies, :storage => storage)
    @live_migrator = Support::LiveMigrator.new(@stacks_factory, @source_host)
    @test_env = new_environment('env', :primary_site => 'oy')
  end

  it 'should refuse to migrate if machine does not have up-to-date definition' do
    @test_machine1 = Stacks::MachineDef.new(self, 'test1', @test_env, 'oy')
    @test_machine1.bind_to(@test_env)

    allow(@stacks_factory).to receive_message_chain(:compute_node_client, :check_vm_definitions).and_return([['host', { 'env-test1' => ['failure'] }]])

    lambda { @live_migrator.move(@test_machine1) }.should raise_error SystemExit
  end

  it 'should refuse to migrate if machine cannot be allocated elsewhere' do
    @test_machine1 = Stacks::MachineDef.new(self, 'test1', @test_env, 'oy')
    @test_machine1.bind_to(@test_env)

    allow(@stacks_factory).to receive_message_chain(:compute_node_client, :check_vm_definitions).and_return([['host', { 'env-test1' => ['success'] }]])

    allow(@stacks_factory).to receive_message_chain(:services, :allocator, :allocate).and_return(
      :already_allocated  => {},
      :newly_allocated    => {},
      :failed_to_allocate => { 'env-test1' => 'not enough cpus' }
    )

    lambda { @live_migrator.move(@test_machine1) }.should raise_error SystemExit
  end

  it 'should succeed if the stars are aligned' do
    @test_machine1 = Stacks::MachineDef.new(self, 'test1', @test_env, 'oy')
    @test_machine1.bind_to(@test_env)

    compute_node_client = spy("compute_node_client")
    allow(@stacks_factory).to receive(:compute_node_client).and_return(compute_node_client)

    allow(compute_node_client).to receive(:check_vm_definitions).and_return([['host', { 'env-test1' => ['success'] }]])

    allow(@stacks_factory).to receive_message_chain(:services, :allocator, :allocate).and_return(
      :already_allocated  => {},
      :newly_allocated    => { 'destination_host' => [{ :hostname => 'env-test1' }] },
      :failed_to_allocate => {}
    )

    lambda { @live_migrator.move(@test_machine1) }.should_not raise_error SystemExit

    expect(compute_node_client).to have_received(:enable_live_migration).with("source_host", "destination_host")
    expect(compute_node_client).to have_received(:create_storage).with("destination_host", [@test_machine1.to_spec])
    expect(compute_node_client).to have_received(:live_migrate_vm).with("source_host", "destination_host", @test_machine1.hostname)
    expect(compute_node_client).to have_received(:disable_live_migration).with("source_host", "destination_host")
  end
end
