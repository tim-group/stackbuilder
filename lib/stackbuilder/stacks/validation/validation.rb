class Stacks::Validation
end

class Stacks::Validation::Validation
  def initialize
    @passed = false
  end

  def validate(_stacks)
    fail('This function should be overridden in a sub class')
  end

  def failed?
    !@passed
  end

  def passed?
    @passed
  end

  def failure_output
    fail('This function should be overridden in a sub class')
  end
end
