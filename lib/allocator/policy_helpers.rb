module StackBuilder::Allocator::PolicyHelpers
  def self.ram_stats_of(host)
    host_ram = Integer(host.ram)
    host_reserve_ram = 2097152 #2 GB
    if host_ram > 0
      allocated_ram = 0
      host.machines.each do |allocated_machine|
        allocated_ram = allocated_ram + Integer(allocated_machine[:ram])
      end
      available_ram = (host_ram - allocated_ram) - host_reserve_ram
      result = {
        :host_ram => host_ram,
        :host_reserve_ram => host_reserve_ram,
        :allocated_ram => allocated_ram,
        :available_ram => available_ram,
      }
    end
    result
  end

  def self.storage_stats_of(host)
    host.storage
  end

  def self.vm_stats_of(host)
    result = {
      :num_vms => host.machines.length
    }
    result
  end
end
