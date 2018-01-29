module StackBuilder::Allocator::PolicyHelpers
  def self.overhead_per_vm
    142_000
  end

  def self.ram_stats_of(host)
    overhead_daemons = 190_880
    overhead_adhoc = 1_048_576

    total = host.ram.to_f
    if total > 0
      used = host.machines.inject(0) { |total, machine| total + machine[:ram].to_f }
      overhead = (host.machines.size * overhead_per_vm) + overhead_adhoc + overhead_daemons
      result = {
        :host_ram         => total,
        :host_reserve_ram => overhead,
        :allocated_ram    => used + overhead,
        :available_ram    => total - (used + overhead),
        :unit             => 'KiB'
      }
    end
    result
  end

  def self.storage_stats_of(host)
    host.storage
  end

  def self.vm_stats_of(host)
    result = {
      :vms => host.machines.length
    }
    result
  end

  def self.allocation_tags_of(host)
    return { :tags => host.facts['allocation_tags'].join(" ") } if host.facts.key?('allocation_tags')
    { :tags => '' }
  end

  def self.allocation_status_of(host)
    return { :status => 'Disabled' } if host.facts.key?('allocation_disabled') && host.facts['allocation_disabled']
    { :status => 'Enabled' }
  end

  def self.vcpu_usage(host)
    host_vcpu = host.facts['processorcount'].to_i
    host_reserve_vcpu = 0
    if host_vcpu > 0
      allocated_vcpu = 0
      host.machines.each do |allocated_machine|
        allocated_vcpu = (allocated_vcpu + allocated_machine[:vcpus].to_i)
      end
      available_vcpu = ((host_vcpu - allocated_vcpu) - host_reserve_vcpu)
      result = {
        :host_vcpu => host_vcpu,
        :host_reserve_vcpu => host_reserve_vcpu,
        :allocated_vcpu => allocated_vcpu,
        :available_vcpu => available_vcpu
      }
    end
    result
  end
end
