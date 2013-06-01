require 'stacks/hosts/namespace'

class Host
  attr_accessor :allocated_machines
  attr_accessor :provisionally_allocated_machines
  attr_reader :fqdn
  attr_reader :preference_functions

  def initialize(fqdn, args = {:preference_functions=>[]})
    @provisionally_allocated_machines = []
    @fqdn = fqdn
    @allocated_machines = []
    @policies = []
    @preference_functions = [] #args[:preference_functions]
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
    @policies.each do |policy|
      return false unless policy.call(self, machine)
    end
    return true
  end

  def preference(machine)
    @preference_functions.map do |function|
      function.call(self)
    end
  end
end