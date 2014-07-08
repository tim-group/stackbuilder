require 'allocator/namespace'

class StackBuilder::Allocator::Host
  attr_accessor :allocated_machines
  attr_accessor :provisionally_allocated_machines
  attr_reader :fqdn
  attr_reader :ram
  attr_reader :storage
  attr_reader :preference_functions
  attr_accessor :policies

  def initialize(fqdn, args = {:preference_functions=>[], :policies=>[], :ram=>'0', :storage=>{}})
    @provisionally_allocated_machines = []
    @fqdn = fqdn
    @allocated_machines = []
    @policies = args[:policies]
    @preference_functions = [] #args[:preference_functions]
    @ram = args[:ram]
    @storage = args[:storage]
  end

  def machines
    provisionally_allocated_machines + allocated_machines
  end

  def provisionally_allocate(machine)
    @provisionally_allocated_machines << machine
  end

  def add_policy(&block)
    @policies << block
  end

  def set_preference_functions(functions)
    @preference_functions = functions
  end

  def can_allocate(machine)
    result = { :allocatable => true, :reasons => []}

    relevant_policies.each do |policy|
      policy_result = policy.call(self, machine)
      if (policy_result[:passed] != true)
        result[:allocatable] = false
        result[:reasons] << policy_result[:reason]
      end
    end
    result
  end

  # FIXME: Remove this once all machines have new config
  def relevant_policies
    @policies.select do |policy|
      use_policy = true
      if @storage.nil?
        proc1 = StackBuilder::Allocator::HostPolicies.ensure_defined_storage_types_policy
        proc2 = StackBuilder::Allocator::HostPolicies.do_not_overallocate_disk_policy
        if policy.to_s == proc1.to_s or policy.to_s == proc2.to_s
          use_policy = false
        end
      end
      use_policy
    end
  end

  def preference(machine)
    @preference_functions.map do |function|
      function.call(self)
    end
  end
end
