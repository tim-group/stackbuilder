require 'allocator/hosts'
require 'allocator/host_policies'

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
    StackBuilder::Allocator::HostPolicies.ha_group().call(h1, machines[1])[:passed].should eql(true)
  end

  it 'rejects allocations that allocate >1 machine of the same group to the same host' do
    env = test_env_with_refstack
    machines = env.flatten
    h1 = StackBuilder::Allocator::Host.new("h1")
    h1.allocated_machines << machines[0]
    StackBuilder::Allocator::HostPolicies.ha_group().call(h1, machines[1])[:passed].should eql(false)
  end

  it 'allows allocation if the availability group is unset' do
    machine = double
    running_machine = double

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
    StackBuilder::Allocator::HostPolicies.ha_group().call(h1, machine)[:passed].should eql(true)
  end

  it 'allows allocations where the host ram is sufficient' do
    candidate_machine = {
      :hostname => "candidate_machine",
      :ram => 2097152
    }

    provisionally_allocated_machine = {
      :hostname => "provisionally_allocated_machine",
      :ram => 2097152
    }

    existing_machine = {
      :hostname => "existing machine",
      :ram => 2097152
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :ram => '8388608') # 8GB
    h1.allocated_machines << existing_machine
    h1.provisionally_allocated_machines << provisionally_allocated_machine

    StackBuilder::Allocator::HostPolicies.do_not_overallocated_ram_policy().call(h1, candidate_machine)[:passed].should eql(true)
  end

  it 'rejects allocations where the host ram is insufficient due to host reserve' do
    candidate_machine = {
      :hostname => "candidate_machine",
      :ram => 2097152
    }

    provisionally_allocated_machine = {
      :hostname => "provisionally_allocated_machine",
      :ram => 2097152
    }

    existing_machine = {
      :hostname => "existing machine",
      :ram => 2097152
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :ram => '8388607') # 1 byte under 8GB
    h1.allocated_machines << existing_machine
    h1.provisionally_allocated_machines << provisionally_allocated_machine

    StackBuilder::Allocator::HostPolicies.do_not_overallocated_ram_policy().call(h1, candidate_machine)[:passed].should eql(false)
  end

  it 'rejects allocations where the host ram is insufficient' do
    candidate_machine = {
      :hostname => "candidate_machine",
      :ram => 2097152
    }

    provisionally_allocated_machine = {
      :hostname => "provisionally_allocated_machine",
      :ram => 2097152
    }

    existing_machine = {
      :hostname => "existing machine",
      :ram => 2097152
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :ram => '4194304') # 4GB
    h1.allocated_machines << existing_machine
    h1.provisionally_allocated_machines << provisionally_allocated_machine

    StackBuilder::Allocator::HostPolicies.do_not_overallocated_ram_policy().call(h1, candidate_machine)[:passed].should eql(false)
  end

  it 'rejects allocations where the host provisioning has been disabled' do
    candidate_machine = {
      :hostname => "candidate_machine",
      :ram => 2097152
    }

    provisionally_allocated_machine = {
      :hostname => "provisionally_allocated_machine",
      :ram => 2097152
    }

    existing_machine = {
      :hostname => "existing machine",
      :ram => 2097152
    }

    h1 = StackBuilder::Allocator::Host.new("h1", :ram => '4194304', :allocation_disabled => true) # 4GB
    h1.allocated_machines << existing_machine
    h1.provisionally_allocated_machines << provisionally_allocated_machine

    StackBuilder::Allocator::HostPolicies.allocation_temporarily_disabled_policy().call(h1, candidate_machine)[:passed].should eql(false)
  end

  it 'rejects allocations where the host has no defined storage types' do
    machine = { :storage => { :mount_point => { :type => "something" } } }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => {})
    StackBuilder::Allocator::HostPolicies.ensure_defined_storage_types_policy().call(h1, machine)[:passed].should eql(false)
  end

  it 'accepts allocations where the host has no defined storage types' do
    machine = { :storage => { :mount_point => { :type => "LVS" } } }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => { "LVS" => { "some_key" => "value" } })
    StackBuilder::Allocator::HostPolicies.ensure_defined_storage_types_policy().call(h1, machine)[:passed].should eql(true)
  end

  it 'accept allocations where the hosts persistant storage does exist on this computenode' do
    machine = {
      :hostname => 'test-db-001',
      :storage => {
        "/var/lib/mysql/".to_sym => {
          :type => "data",
          :size => "1G",
          :persistent => true,
          :persistence_options => { :on_storage_not_found => :raise_error }
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
    StackBuilder::Allocator::HostPolicies.require_persistent_storage_to_exist_policy().call(h1, machine)[:passed].should eql(true)
  end

  it 'rejects allocations where the hosts persistant storage does not exist on this computenode' do
    machine = {
      :hostname => 'test-db-001',
      :storage => {
        "/var/lib/mysql/".to_sym => {
          :type => "data",
          :size => "1G",
          :persistent => true,
          :persistence_options => { :on_storage_not_found => :raise_error }
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
    StackBuilder::Allocator::HostPolicies.require_persistent_storage_to_exist_policy().call(h1, machine)[:passed].should eql(false)
  end

  it 'rejects overallocated disks' do
    machine = { :storage => { :mount_point => { :type => "LVS", :size => "5G" } } }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => { "LVS" => { :free => "2000000" } })

    StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy().call(h1, machine)[:passed].should eql(false)
  end

  it 'rejects overallocated disks for same type' do
    machine = {
      :storage => {
        '/foo'.to_sym      => { :type => 'data', :size => "10G" },
        '/mnt/data'.to_sym => { :type => 'data', :size => "10G" }
      }
    }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => { "data" => { :free => "15000000" } })
    StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy().call(h1, machine)[:passed].should eql(false)
  end

  it 'accepts disk space it can allocate' do
    machine = { :storage => { :mount_point => { :type => "LVS", :size => "2G" } } }
    h1 = StackBuilder::Allocator::Host.new("h1", :storage => { "LVS" => { :free => "5000000" } })

    StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy().call(h1, machine)[:passed].should eql(true)
  end
end
