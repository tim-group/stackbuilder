require 'allocator/namespace'
require 'allocator/policy_helpers'

module StackBuilder::Allocator::HostPolicies

  def self.ha_group()
    Proc.new do |host, machine_spec|
      result = { :passed => true }
      if machine_spec[:availability_group]
        host.machines.each do |allocated_machine|
          if allocated_machine[:availability_group] and machine_spec[:availability_group] == allocated_machine[:availability_group]
            result = { :passed => false, :reason => "already running #{allocated_machine[:hostname]}, which is in same availability group" }
          end
        end
      end
      result
    end
  end

  def self.do_not_overallocated_ram_policy
    helper = StackBuilder::Allocator::PolicyHelpers
    Proc.new do |host, machine|
      result = { :passed => true }
      host_ram_stats = helper.ram_stats_of(host)
      if host_ram_stats[:available_ram] < Integer(machine[:ram])
        result = {
          :passed => false,
          :reason => "unable to fulfil ram requirement of #{machine[:ram]} because only #{host_ram_stats[:available_ram]} is available. Memory stats: #{host_ram_stats[:allocated_ram]+host_ram_stats[:host_reserve_ram]}/#{host_ram_stats[:host_ram]}"
        }
      end
      result
    end
  end

  def self.ensure_defined_storage_types_policy
    Proc.new do |host, machine|
      missing_storage_types = machine[:storage].inject([]) do |result, (mount_point, values)|
        host_storage_type = host.storage[values[:type]]
        result << host_storage_type if host_storage_type.nil?
        result
      end
      result = { :passed => true }
      if (missing_storage_types.any?)
        result = {
            :passed => false,
            :reason => "unable to fulfil storage requirement for types #{missing_storage_types.join(',')}. Storage types available are #{host.storage.keys.sort.join(',')}"
        }
      end
      pp result
      result
    end
  end
  def self.do_not_overallocate_disk_policy
    Proc.new do |host, machine|
      storage_without_enough_space = machine[:storage].inject({}) do |result, (mount_point, values)|
        machine_storage_type = values[:type]
        host_storage_type = host.storage[machine_storage_type]
        available_space = host_storage_type[:free].to_f
        required_space = values[:size].to_f
        if (required_space > available_space)
          result[machine_storage_type] = {:available_space => available_space, :required_space => required_space}
        end
        result
      end
      result = { :passed => true }
      if (!storage_without_enough_space.empty?)
        sorted_keys = storage_without_enough_space.keys.sort
        result = {
            :passed => false,
            :reason => "unable to fulfil storage requirement for types #{sorted_keys.join(',')}.
                        Not enough disk space available. Required: #{sorted_keys.collect{|key| storage_without_enough_space[key][:required_space]}.join(',') }G -
                        Available: #{sorted_keys.collect{|key| storage_without_enough_space[key][:available_space]}.join(',')}G"
        }
      end
      pp result
      
      result


    end
  end
#   def self.do_not_overallocate_disk_policy2
#     Proc.new do |host, machine|
#       result = { :passed => true }
#       missing_storage_types = []
#       storage_without_enough_space = {}
#       pp machine[:storage]
#       machine[:storage].keys.each do |mount_point|
#         type = machine[:storage][mount_point][:type]
#         host_storage_type = host.storage[type]
#         puts "host storage type:"
#         pp host_storage_type
#         if host_storage_type.nil?
#           missing_storage_types << type
#         end
#
#         available_space = host_storage_type[:free].to_f
#         required_space = machine[:storage][mount_point][:size].to_f
#         puts "#{type} - Available - #{available_space} - Required #{required_space}"
#         if (required_space > available_space)
#           storage_without_enough_space[:type] = {:available_space => available_space, :required_space => required_space}
#         end
#       end
#
#       if missing_storage_types != []
#         result = {
#           :passed => false,
#           :reason => "unable to fulfil storage requirement for types #{missing_storage_types.join(',')}. Storage types available are #{host.storage.keys.sort.join(',')}"
#         }
#         pp result
#       end
#
#       if storage_without_enough_space != {}
#         result = {
#           :passed => false,
#           :reason => "unable to fulfil storage requirement for types #{storage_without_enough_space.keys.sort.join(',')}.
# Not enough disk space available. Required: #{storage_without_enough_space.keys.sort.collect{|key| storage_without_enough_space[key][:required_space]}.join(',') }G -
# Available: #{storage_without_enough_space.keys.sort.collect{|key| storage_without_enough_space[key][:available_space]}.join(',')}G"
#         }
#       end
#
#       pp result
#       result
#     end
#   end
end
