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
end
