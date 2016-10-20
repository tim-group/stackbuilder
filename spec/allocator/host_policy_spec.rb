require 'stackbuilder/allocator/host_policies'
require 'stackbuilder/stacks/factory'

describe StackBuilder::Allocator::HostPolicies do
  def test_env_with_refstack
    [{
      :hostname => "refapp1",
      :availability_group => "refapp"
    }, {
      :hostname => "refapp2",
      :availability_group => "refapp"
    }]
  end

  it 'allows allocations that have no machine of the same group to the same host' do
    env = test_env_with_refstack
    machines = env.flatten
    h1 = StackBuilder::Allocator::Host.new("h1")
    expect(StackBuilder::Allocator::HostPolicies.ha_group.call(h1, machines[1])[:passed]).to eql(true)
  end

  it 'rejects allocations that allocate >1 machine of the same group to the same host' do
    env = test_env_with_refstack
    machines = env.flatten
    h1 = StackBuilder::Allocator::Host.new("h1")
    h1.allocated_machines << machines[0]
    expect(StackBuilder::Allocator::HostPolicies.ha_group.call(h1, machines[1])[:passed]).to eql(false)
  end

  it 'allows allocation if the availability group is unset' do
    machine = {
      :hostname => "host1",
      :availability_group => nil
    }

    running_machine = {
      :hostname => "host2",
      :availability_group => nil
    }

    h1 = StackBuilder::Allocator::Host.new("h1")
    h1.allocated_machines << running_machine
    expect(StackBuilder::Allocator::HostPolicies.ha_group.call(h1, machine)[:passed]).to eql(true)
  end

  it 'allows allocations where the host ram is sufficient' do
    candidate_machine = {
      :hostname => "candidate_machine",
      :ram => 2_097_152
    }

    provisionally_allocated_machine = {
      :hostname => "provisionally_allocated_machine",
      :ram => 2_097_152
    }

    existing_machine = {
      :hostname => "existing machine",
      :ram => 2_097_152
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :ram => '8388608') # 8GB
    h1.allocated_machines << existing_machine
    h1.provisionally_allocated_machines << provisionally_allocated_machine

    expect(StackBuilder::Allocator::HostPolicies.do_not_overallocate_ram_policy.call(h1, candidate_machine)[:passed]).
      to eql(true)
  end

  it 'rejects allocations where the host ram is insufficient due to host reserve' do
    candidate_machine = {
      :hostname => "candidate_machine",
      :ram => 2_097_152
    }

    provisionally_allocated_machine = {
      :hostname => "provisionally_allocated_machine",
      :ram => 2_097_152
    }

    existing_machine = {
      :hostname => "existing machine",
      :ram => 2_097_152
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :ram => '8388607') # 1 byte under 8GB
    h1.allocated_machines << existing_machine
    h1.provisionally_allocated_machines << provisionally_allocated_machine

    expect(StackBuilder::Allocator::HostPolicies.do_not_overallocate_ram_policy.call(h1, candidate_machine)[:passed]).
      to eql(false)
  end

  it 'rejects allocations where the host ram is insufficient' do
    candidate_machine = {
      :hostname => "candidate_machine",
      :ram => 2_097_152
    }

    provisionally_allocated_machine = {
      :hostname => "provisionally_allocated_machine",
      :ram => 2_097_152
    }

    existing_machine = {
      :hostname => "existing machine",
      :ram => 2_097_152
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :ram => '4194304') # 4GB
    h1.allocated_machines << existing_machine
    h1.provisionally_allocated_machines << provisionally_allocated_machine

    expect(StackBuilder::Allocator::HostPolicies.do_not_overallocate_ram_policy.call(h1, candidate_machine)[:passed]).
      to eql(false)
  end

  it 'rejects allocations where the host provisioning has been disabled' do
    candidate_machine = {
      :hostname => "candidate_machine",
      :ram => 2_097_152
    }

    provisionally_allocated_machine = {
      :hostname => "provisionally_allocated_machine",
      :ram => 2_097_152
    }

    existing_machine = {
      :hostname => "existing machine",
      :ram => 2_097_152
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :ram => '4194304', :facts => { 'allocation_disabled' => true }) # 4GB
    h1.allocated_machines << existing_machine
    h1.provisionally_allocated_machines << provisionally_allocated_machine

    expect(StackBuilder::Allocator::HostPolicies.allocation_temporarily_disabled_policy.
      call(h1, candidate_machine)[:passed]).to eql(false)
  end

  it 'rejects allocations where the host has no defined storage types' do
    machine = { :storage => { :mount_point => { :type => "something" } } }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => {})
    expect(StackBuilder::Allocator::HostPolicies.ensure_defined_storage_types_policy.call(h1, machine)[:passed]).
      to eql(false)
  end

  it 'accepts allocations where the host has no defined storage types' do
    machine = { :storage => { :mount_point => { :type => "LVS" } } }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => { "LVS" => { "some_key" => "value" } })
    expect(StackBuilder::Allocator::HostPolicies.ensure_defined_storage_types_policy.call(h1, machine)[:passed]).
      to eql(true)
  end

  it 'accept allocations where the hosts persistent storage does exist on this computenode' do
    machine = {
      :hostname => 'test-db-001',
      :storage => {
        "/var/lib/mysql/".to_sym => {
          :type => "data",
          :size => "1G",
          :persistent => true,
          :persistence_options => { :on_storage_not_found => 'raise_error' }
        }
      }
    }
    host_storage = {
      'os' => {
        :existing_storage => {}
      },
      'data' => {
        :existing_storage => { 'test-db-001_var_lib_mysql'.to_sym => 1.00 }
      }
    }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => host_storage)
    expect(StackBuilder::Allocator::HostPolicies.require_persistent_storage_to_exist_policy.call(h1, machine)[:passed]).
      to eql(true)
  end

  it 'rejects allocations where the hosts persistent storage does not exist on this computenode' do
    machine = {
      :hostname => 'test-db-001',
      :storage => {
        "/var/lib/mysql/".to_sym => {
          :type => "data",
          :size => "1G",
          :persistent => true,
          :persistence_options => { :on_storage_not_found => 'raise_error' }
        }
      }
    }
    host_storage = {
      :os => {
        :existing_storage => {}
      },
      :data => {
        :existing_storage => {}
      }
    }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => host_storage)
    expect(StackBuilder::Allocator::HostPolicies.require_persistent_storage_to_exist_policy.call(h1, machine)[:passed]).
      to eql(false)
  end

  it 'rejects overallocated disks' do
    machine = { :storage => { :mount_point => { :type => "LVS", :size => "5G" } } }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => { "LVS" => { :free => "2000000" } })

    expect(StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy.call(h1, machine)[:passed]).
      to eql(false)
  end

  it 'rejects overallocated disks for same type' do
    machine = {
      :storage => {
        '/foo'.to_sym      => { :type => 'data', :size => "10G" },
        '/mnt/data'.to_sym => { :type => 'data', :size => "10G" }
      }
    }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => { "data" => { :free => "15000000" } })
    expect(StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy.call(h1, machine)[:passed]).
      to eql(false)
  end

  it 'accepts disk space it can allocate' do
    machine = { :storage => { :mount_point => { :type => "LVS", :size => "2G" } } }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => { "LVS" => { :free => "5000000" } })

    expect(StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy.call(h1, machine)[:passed]).
      to eql(true)
  end

  it 'accepts lvm_in_block_device disk space it can allocate' do
    # FIXME: If ever we check size has to be less than guest_lvm_pv_size this test will need fixing!
    machine = { :storage => { :mount_point => {
      :type => "LVS",
      :size => "20G",
      :prepare => {
        :options => {
          :guest_lvm_pv_size => '4G'
        }
      }
    } } }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => { "LVS" => { :free => "5000000" } })

    expect(StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy.call(h1, machine)[:passed]).
      to eql(true)
  end

  it 'accepts the disk space allocation if persistent storage already exists' do
    machine = {
      :hostname => 'test-db-001',
      :storage => {
        "/var/lib/mysql/".to_sym => {
          :type => "data",
          :size => "1G",
          :persistent => true,
          :persistence_options => { :on_storage_not_found => 'raise_error' }
        }
      }
    }
    host1_storage = {
      'os' => {
        :existing_storage => {}
      },
      'data' => {
        :existing_storage => {}
      }
    }
    host2_storage = {
      'os' => {
        :existing_storage => {}
      },
      'data' => {
        :existing_storage => {
          'test-db-001_var_lib_mysql'.to_sym => {}
        }
      }
    }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => host1_storage)
    h2 = StackBuilder::Allocator::Host.new("h2", :storage => host2_storage)
    expect(StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy.call(h1, machine)[:passed]).
      to eql(false)
    expect(StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy.call(h2, machine)[:passed]).
      to eql(true)
  end

  it 'accepts hosts with correct allocation tag' do
    machine = {
      :hostname        => 'test-db-001',
      :allocation_tags => %w(tag1)
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :facts => { 'allocation_tags' => %w(tag1 tag2) })
    h2 = StackBuilder::Allocator::Host.new("h2", :facts => { 'allocation_tags' => %w(tag1) })
    expect(StackBuilder::Allocator::HostPolicies.allocate_on_host_with_tags.call(h1, machine)[:passed]).to eql(true)
    expect(StackBuilder::Allocator::HostPolicies.allocate_on_host_with_tags.call(h2, machine)[:passed]).to eql(true)
  end

  it 'accepts hosts with multiple correct allocation tags' do
    machine = {
      :hostname        => 'test-db-001',
      :allocation_tags => %w(tag1 tag2)
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :facts => { 'allocation_tags' => %w(tag1 tag2) })
    h2 = StackBuilder::Allocator::Host.new("h2", :facts => { 'allocation_tags' => %w(tag1) })
    expect(StackBuilder::Allocator::HostPolicies.allocate_on_host_with_tags.call(h1, machine)[:passed]).to eql(true)
    expect(StackBuilder::Allocator::HostPolicies.allocate_on_host_with_tags.call(h2, machine)[:passed]).to eql(false)
  end

  it 'rejects hosts with the wrong allocation tag' do
    machine = {
      :hostname        => 'test-db-001',
      :allocation_tags => %w(tag1)
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :facts => { 'allocation_tags' => %w(tag2) })
    h2 = StackBuilder::Allocator::Host.new("h2", :facts => { 'allocation_tags' => %w(tag3) })
    expect(StackBuilder::Allocator::HostPolicies.allocate_on_host_with_tags.call(h1, machine)[:passed]).to eql(false)
    expect(StackBuilder::Allocator::HostPolicies.allocate_on_host_with_tags.call(h2, machine)[:passed]).to eql(false)
  end

  it 'accepts any hosts when no allocation tag is set' do
    machine = {
      :hostname => 'test-db-001'
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :facts => { 'allocation_tags' => %w(tag2) })
    h2 = StackBuilder::Allocator::Host.new("h2", :facts => { 'allocation_tags' => %w(tag3) })
    expect(StackBuilder::Allocator::HostPolicies.allocate_on_host_with_tags.call(h1, machine)[:passed]).to eql(true)
    expect(StackBuilder::Allocator::HostPolicies.allocate_on_host_with_tags.call(h2, machine)[:passed]).to eql(true)
  end
end
