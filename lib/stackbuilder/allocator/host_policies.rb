require 'stackbuilder/allocator/namespace'
require 'stackbuilder/allocator/policy_helpers'

module StackBuilder::Allocator::HostPolicies
  def self.ha_group
    Proc.new do |host, machine_spec|
      result = { :passed => true }
      next result if !machine_spec[:availability_group]

      host.machines.each do |allocated_machine|
        next if !allocated_machine[:availability_group] ||
                allocated_machine[:availability_group] != machine_spec[:availability_group]
        result = {
          :passed => false,
          :reason => "Availability group violation (already running #{allocated_machine[:hostname]})"
        }
      end
      result
    end
  end

  def self.allocation_temporarily_disabled_policy
    Proc.new do |host, _machine|
      if host.facts['allocation_disabled']
        reason = "Allocation disabled by #{host.facts['allocation_disabled_user']}, reason: #{host.facts['allocation_disabled_reason']}"
        { :passed => false, :reason => reason }
      else
        { :passed => true }
      end
    end
  end

  def self.do_not_overallocate_ram_policy
    helper = StackBuilder::Allocator::PolicyHelpers
    Proc.new do |host, machine|
      machine_ram = machine[:ram].to_i

      if machine_ram < 1024
        logger(Logger::FATAL) { "machine must require some ram: #{machine_ram} KiB" }
        exit 1
      end

      required_ram = machine_ram + helper.overhead_per_vm
      available_ram = helper.ram_stats_of(host)[:available_ram].to_i

      if available_ram >= required_ram
        { :passed => true }
      else
        {
          :passed => false,
          :reason => "Insufficient memory (required including overhead): #{required_ram} KiB. " \
                     "Available (includes reserve): #{available_ram} KiB"
        }
      end
    end
  end

  def self.ensure_defined_storage_types_policy
    Proc.new do |host, machine|
      missing_storage_types = machine[:storage].inject([]) do |result, (_mount_point, values)|
        host_storage_type = host.storage[values[:type]]
        result << values[:type] if host_storage_type.nil?
        result
      end

      if missing_storage_types.any?
        unique_missing_storage_types = Set.new(missing_storage_types).to_a
        {
          :passed => false,
          :reason => "Storage type not available (required: #{unique_missing_storage_types.join(',')}, " \
                      "available: #{host.storage.keys.sort.join(',')})"
        }
      else
        { :passed => true }
      end
    end
  end

  def self.ensure_mount_points_have_specified_storage_types_policy
    Proc.new do |host, machine|
      mount_points_with_unspecified_storage_type = machine[:storage].inject([]) do |result, (mount_point, values)|
        host_storage_type = host.storage[values[:type]]
        result << mount_point if host_storage_type.nil?
        result
      end

      if mount_points_with_unspecified_storage_type.any?
        unique_unspecified_mount_points = Set.new(mount_points_with_unspecified_storage_type).to_a
        {
          :passed => false,
          :reason => "Storage type not specified for mount points: #{unique_unspecified_mount_points.join(',')}"
        }
      else
        { :passed => true }
      end
    end
  end

  def self.check_storage_exists(_mount_point)
    false
  end

  def self.require_persistent_storage_to_exist_policy
    Proc.new do |host, machine|
      result = { :passed => true }

      persistent_storage_not_found = {}
      machine[:storage].each do |mount_point, attributes|
        persistent = attributes[:persistent]
        next if !persistent

        on_storage_not_found = attributes[:persistence_options][:on_storage_not_found] rescue 'raise_error'

        case on_storage_not_found
        when 'raise_error'
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
        when 'create_new'
          # Allow the storage to be created
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

      result
    end
  end

  def self.do_not_overallocate_disk_policy
    Proc.new do |host, machine|
      required_space_hash = {}
      machine[:storage].each do |_mount_point, values|
        required_space_hash[values[:type]] = 0
      end
      machine[:storage].each do |mount_point, values|
        lvm_in_lvm_size = values[:prepare][:options][:guest_lvm_pv_size] rescue false
        size = lvm_in_lvm_size ? lvm_in_lvm_size.to_f : values[:size].to_f

        type = values[:type]
        underscore_name = "#{machine[:hostname]}#{mount_point.to_s.gsub('/', '_').gsub(/_$/, '')}"
        # Deal with already existing storage (ie. persistent storage) by fudging
        # size (and therefore required_space) for this mount point to zero
        if host.storage.key?(type) &&
           host.storage[type].key?(:existing_storage) &&
           host.storage[type][:existing_storage].include?(underscore_name.to_sym)
          # FIXME: required space should really be any difference between persistent
          # size and what should be allocated if it weren't persistent
          size = 0.to_f
        end
        required_space_hash[values[:type]] += size
      end
      storage_without_enough_space = required_space_hash.inject({}) do |result, (type, required_space)|
        host_storage_type = host.storage[type] rescue nil
        if host_storage_type.nil?
          result[type] = { :available_space => 0, :required_space => required_space }
        else
          available_space = kb_to_gb(host_storage_type[:free])
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

  def self.spectre_patch_status_of_vm_must_match_spectre_patch_status_of_host_policy
    Proc.new do |host, machine|
      host_supplied_tags = host.facts['allocation_tags']

      is_vm_spectre_patched = !machine[:spectre_patches].nil? && machine[:spectre_patches]
      is_host_spectre_patched = !host_supplied_tags.nil? && host_supplied_tags.include?('spectre_patched')

      if is_vm_spectre_patched != is_host_spectre_patched
        { :passed => false, :reason => is_vm_spectre_patched ? "VM is spectre-patched but host is not" : "VM is not spectre-patched but host is" }
      else
        { :passed => true }
      end
    end
  end

  # Policy
  # If tag(s) don't exist = explode
  # If tag(s) don't exist but no capacity = explode
  #
  # Preference
  # If I dont have that tag -10
  # If I have the tag then 10
  #
  # Preference ordering by HP model (G6, G7, G9) etc.
  #
  def self.allocate_on_host_with_tags
    Proc.new do |host, machine|
      host_supplied_tags = host.facts['allocation_tags']
      vm_requested_tags = machine[:allocation_tags]
      tag_found = true
      #   Loop through all tags supplied by the VM
      if vm_requested_tags
        vm_requested_tags.each do |tag|
          # For each tag from the VM, check if its in the tag list of the KVM host
          tag_found = false if !host_supplied_tags.include?(tag)
        end
      end
      if tag_found == false
        { :passed => false, :reason => "Requested tags #{vm_requested_tags} not found in supported list #{host_supplied_tags}" }
      else
        { :passed => true }
      end
    end
  end

  private

  def self.kb_to_gb(value)
    ((value.to_f / (1024 * 1024) * 100).round / 100.0)
  end
end
