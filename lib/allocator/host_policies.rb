require 'allocator/namespace'
require 'allocator/policy_helpers'

module StackBuilder::Allocator::HostPolicies

  def self.ha_group()
    Proc.new do |host, machine_spec|
      result = { :passed => true }
      if machine_spec[:availability_group]
        host.machines.each do |allocated_machine|
          if allocated_machine[:availability_group] and machine_spec[:availability_group] == allocated_machine[:availability_group]
            result = { :passed => false, :reason => "Availability group violation (already running #{allocated_machine[:hostname]})" }
          end
        end
      end
      result
    end
  end

  def self.allocation_temporarily_disabled_policy
    Proc.new do |host, machine|
      result = { :passed => true }
      result = { :passed => false, :reason => "Allocation disabled" } if host.allocation_disabled
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
          :reason => "Insufficient memory (required: #{machine[:ram]} available: #{host_ram_stats[:available_ram]})"
        }
      end
      result
    end
  end

  def self.ensure_defined_storage_types_policy
    Proc.new do |host, machine|
      missing_storage_types = machine[:storage].inject([]) do |result, (mount_point, values)|
        # FIXME: remove the rescue once all compute nodes have storage config
        host_storage_type = host.storage[values[:type]] rescue nil
        result << values[:type] if host_storage_type.nil?
        result
      end
      result = { :passed => true }
      # FIXME: unwrap from unless once all compute nodes have storage config
      unless host.storage.nil?
        if (missing_storage_types.any?)
          unique_missing_storage_types = Set.new(missing_storage_types).to_a
          result = {
              :passed => false,
              :reason => "Storage type not available (required: #{unique_missing_storage_types.join(',')} available: #{host.storage.keys.sort.join(',')})"
          }
        end
      end
      result
    end
  end

  def self.check_storage_exists(mount_point)
    false
  end

  def self.require_persistent_storage_to_exist_policy
    Proc.new do |host, machine|
      result = { :passed => true }

      persistent_storage_not_found = {}
      if !host.storage.nil?
        machine[:storage].each do |mount_point, attributes|
          persistent = attributes[:persistent]
          persistence_options = attributes[:persistence_options]
          if persistent
            case persistence_options[:on_storage_not_found]
            when :raise_error
              underscore_name = "#{machine[:hostname]}#{mount_point.to_s.gsub('/','_').gsub(/_$/, '')}"
              type = attributes[:type]
              unless host.storage.has_key?(type)
                persistent_storage_not_found[type] = [] unless persistent_storage_not_found.include? type
                persistent_storage_not_found[type] << underscore_name
              else
                unless host.storage[type][:existing_storage].include? underscore_name.to_sym
                  persistent_storage_not_found[type] = [] unless persistent_storage_not_found.include? type
                  persistent_storage_not_found[type] << underscore_name
                end
              end
            when :create_new
              # Allow the storage to be created
            end
          end
        end
        reasons = persistent_storage_not_found.keys.map do |type|
          "#{type}: #{persistent_storage_not_found[type].join(',')}"
        end
        unless persistent_storage_not_found.empty?
          result = {
            :passed => false,
            :reason => "Persistent storage not present for type #{reasons.join(',')}"
          }
        end

      end
      result
    end
  end

  def self.do_not_overallocate_disk_policy
    Proc.new do |host, machine|
      storage_without_enough_space = machine[:storage].inject({}) do |result, (mount_point, values)|
        machine_storage_type = values[:type]
        host_storage_type = host.storage[machine_storage_type] rescue nil
        required_space = values[:size].to_f
        unless host_storage_type.nil?
          available_space = host_storage_type[:free].to_f
          if (required_space > available_space)
            result[machine_storage_type] = {:available_space => available_space, :required_space => required_space}
          end
        else
          result[machine_storage_type] = {:available_space => 0, :required_space => required_space}
        end
        result
      end
      result = { :passed => true }
      if (!storage_without_enough_space.empty?)
        sorted_keys = storage_without_enough_space.keys.sort
        result = {
            :passed => false,
            :reason => "Insufficient disk space (required: #{sorted_keys.collect{|key| storage_without_enough_space[key][:required_space]}.join(',') }G available: #{sorted_keys.collect{|key| storage_without_enough_space[key][:available_space]}.join(',')}G)"
        }
      end
      result


    end
  end
end
