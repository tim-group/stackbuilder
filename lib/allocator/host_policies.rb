require 'allocator/namespace'
require 'allocator/policy_helpers'

module StackBuilder::Allocator::HostPolicies
  def self.ha_group
    Proc.new do |host, machine_spec|
      result = { :passed => true }
      if machine_spec[:availability_group]
        host.machines.each do |allocated_machine|
          if allocated_machine[:availability_group] && machine_spec[:availability_group] == allocated_machine[:availability_group]
            result = { :passed => false, :reason => "Availability group violation (already running #{allocated_machine[:hostname]})" }
          end
        end
      end
      result
    end
  end

  def self.allocation_temporarily_disabled_policy
    Proc.new do |host, _machine|
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
          :reason => "Insufficient memory (required: #{machine[:ram]} KiB available: #{host_ram_stats[:available_ram]} KiB)"
        }
      end
      result
    end
  end

  def self.ensure_defined_storage_types_policy
    Proc.new do |host, machine|
      missing_storage_types = machine[:storage].inject([]) do |result, (_mount_point, values)|
        # FIXME: remove the rescue once all compute nodes have storage config
        host_storage_type = host.storage[values[:type]] rescue nil
        result << values[:type] if host_storage_type.nil?
        result
      end
      result = { :passed => true }
      # FIXME: unwrap from unless once all compute nodes have storage config
      unless host.storage.nil?
        if missing_storage_types.any?
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

  def self.check_storage_exists(_mount_point)
    false
  end

  def self.require_persistent_storage_to_exist_policy
    Proc.new do |host, machine|
      result = { :passed => true }

      persistent_storage_not_found = {}
      unless host.storage.nil?
        machine[:storage].each do |mount_point, attributes|
          persistent = attributes[:persistent]
          persistence_options = attributes[:persistence_options] rescue {}
          on_storage_not_found = persistence_options[:on_storage_not_found] rescue :raise_error
          if persistent
            case on_storage_not_found
            when :raise_error
              underscore_name = "#{machine[:hostname]}#{mount_point.to_s.gsub('/', '_').gsub(/_$/, '')}"
              type = attributes[:type]
              if host.storage.key?(type)
                unless host.storage[type][:existing_storage].include? underscore_name.to_sym
                  persistent_storage_not_found[type] = [] unless persistent_storage_not_found.include? type
                  persistent_storage_not_found[type] << underscore_name
                end
              else
                persistent_storage_not_found[type] = [] unless persistent_storage_not_found.include? type
                persistent_storage_not_found[type] << underscore_name
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
            :reason => "Persistent storage not present for type \"#{reasons.join(',')}\""
          }
        end

      end
      result
    end
  end

  def self.do_not_overallocate_disk_policy
    required_space_hash = {}
    Proc.new do |host, machine|
      machine[:storage].each do |_mount_point, values|
        required_space_hash[values[:type]] = 0
      end
      machine[:storage].each do |_mount_point, values|
        required_space_hash[values[:type]] += values[:size].to_f
      end
      storage_without_enough_space = required_space_hash.inject({}) do |result, (type, required_space)|
        host_storage_type = host.storage[type] rescue nil
        if host_storage_type.nil?
          result[type] = { :available_space => 0, :required_space => required_space }
        else
          available_space = KB_to_GB(host_storage_type[:free])
          if required_space > available_space
            result[type] = { :available_space => available_space, :required_space => required_space }
          end
        end
        result
      end
      result = { :passed => true }
      unless storage_without_enough_space.empty?
        sorted_keys = storage_without_enough_space.keys.sort
        required = sorted_keys.collect { |key| storage_without_enough_space[key][:required_space] }.join(',')
        available = sorted_keys.collect { |key| storage_without_enough_space[key][:available_space] }.join(',')
        result = {
          :passed => false,
          :reason => "Insufficient disk space (required: #{required}G available: #{available}G)"
        }
      end
      result
    end
  end

  private

  def self.KB_to_GB(value)
    ((value.to_f / (1024 * 1024) * 100).round / 100.0)
  end
end
