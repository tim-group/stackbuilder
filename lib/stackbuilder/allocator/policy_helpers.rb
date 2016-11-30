module StackBuilder::Allocator::PolicyHelpers
  def self.ram_stats_of(host)
    host_ram = host.ram.to_f
    host_reserve_ram = 2_097_152 # 2 GB
    if host_ram > 0
      allocated_ram = 0
      host.machines.each do |allocated_machine|
        allocated_ram = (allocated_ram + allocated_machine[:ram].to_f)
      end
      available_ram = ((host_ram - allocated_ram) - host_reserve_ram)
      result = {
        :host_ram => host_ram,
        :host_reserve_ram => host_reserve_ram,
        :allocated_ram => allocated_ram,
        :available_ram => available_ram
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
