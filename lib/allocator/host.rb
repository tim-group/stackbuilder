require 'allocator/namespace'
require 'allocator/host_policies'

class StackBuilder::Allocator::Host
  attr_accessor :allocated_machines
  attr_accessor :provisionally_allocated_machines
  attr_accessor :allocation_disabled
  attr_reader :fqdn
  attr_reader :ram
  attr_reader :storage
  attr_reader :preference_functions
  attr_accessor :policies

  def initialize(fqdn, args = { :preference_functions => [], :policies => [], :ram => '0', :storage => {} })
    @provisionally_allocated_machines = []
    @fqdn = fqdn
    @allocated_machines = []
    @policies = args[:policies]
    @preference_functions = [] # args[:preference_functions]
    @ram = args[:ram]
    @storage = args[:storage]
    @allocation_disabled = args[:allocation_disabled] || false
  end

  def machines
    provisionally_allocated_machines + allocated_machines
  end

  def provisionally_allocate(machine_hash)
    @provisionally_allocated_machines << machine_hash
  end

  def add_policy(&block)
    @policies << block
  end

  def set_preference_functions(functions)
    @preference_functions = functions
  end

  def can_allocate(machine_hash)
    result = { :allocatable => true, :reasons => [] }
    relevant_policies(machine_hash[:fabric]).each do |policy|
      policy_result = policy.call(self, machine_hash)
      if (policy_result[:passed] != true)
        result[:allocatable] = false
        result[:reasons] << policy_result[:reason]
      end
    end
    result
  end

  # FIXME: Remove this once all machines have new config
  # XXX: Make sure if "all machines have new config" and remove this
  def relevant_policies(fabric)
    @policies.select do |policy|
      use_policy = true
      if fabric == "local"
        if RUBY_VERSION[0,3] == '1.8'
          use_policy = false if policy.to_s == StackBuilder::Allocator::HostPolicies.ha_group.to_s
        else
          use_policy = false if policy.to_s.gsub(/^(#<Proc:0x)[0-9a-f]+@/, '\1@') == StackBuilder::Allocator::HostPolicies.ha_group.to_s.gsub(/^(#<Proc:0x)[0-9a-f]+@/, '\1@')
        end
      elsif @storage.nil? || @storage == {}
        proc1 = StackBuilder::Allocator::HostPolicies.ensure_defined_storage_types_policy
        proc2 = StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy
        if RUBY_VERSION[0,3] == '1.8'
          if policy.to_s == proc1.to_s || policy.to_s == proc2.to_s
            use_policy = false
          end
        else
          if policy.to_s.gsub(/^(#<Proc:0x)[0-9a-f]+@/, '\1@') == proc1.to_s.gsub(/^(#<Proc:0x)[0-9a-f]+@/, '\1@') || policy.to_s.gsub(/^(#<Proc:0x)[0-9a-f]+@/, '\1@') == proc2.to_s.gsub(/^(#<Proc:0x)[0-9a-f]+@/, '\1@')
            use_policy = false
          end
        end
      end
      use_policy
    end
  end

  def preference(machine_hash)
    @preference_functions.map do |function|
      function.call(self)
    end
  end
end
