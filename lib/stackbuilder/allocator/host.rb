require 'stackbuilder/allocator/namespace'
require 'stackbuilder/allocator/host_policies'

class StackBuilder::Allocator::Host
  attr_accessor :allocated_machines
  attr_accessor :allocation_disabled
  attr_accessor :domains # set externally
  attr_accessor :policies
  attr_accessor :preference_functions
  attr_accessor :provisionally_allocated_machines
  attr_reader :fqdn
  attr_reader :ram
  attr_reader :storage

  def initialize(fqdn, args = { :preference_functions => [], :policies => [], :ram => '0', :storage => {} })
    @allocated_machines = []
    @allocation_disabled = args[:allocation_disabled] || false
    @domains = Hash
    @fqdn = fqdn
    @policies = args[:policies]
    @preference_functions = [] # args[:preference_functions]
    @provisionally_allocated_machines = []
    @ram = args[:ram]
    @storage = args[:storage]
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

  def relevant_policies(fabric)
    @policies.select do |policy|
      use_policy = true
      if fabric == "local"
        if RUBY_VERSION[0, 3] == '1.8'
          use_policy = false if policy.to_s == StackBuilder::Allocator::HostPolicies.ha_group.to_s
        else
          if policy.to_s.gsub(/^(#<Proc:0x)[0-9a-f]+@/, '\1@') ==
             StackBuilder::Allocator::HostPolicies.ha_group.to_s.gsub(/^(#<Proc:0x)[0-9a-f]+@/, '\1@')
            use_policy = false
          end
        end
      end
      use_policy
    end
  end

  def preference(_machine_hash)
    @preference_functions.map do |function|
      function.call(self)
    end
  end
end
