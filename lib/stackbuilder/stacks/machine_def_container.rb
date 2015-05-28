require 'stacks/namespace'

module Stacks::MachineDefContainer
  attr_reader :definitions
  attr_reader :environment

  def children
    # pretend we have a sorted dictionary
    @definitions.sort.map { |_k, v| v }
  end

  def accept(&block)
    block.call(self)
    children.each do |child|
      child.accept(&block)
    end
  end

  def flatten
    list = []
    accept do |m|
      list << m if m.respond_to?(:to_spec)
    end
    list
  end

  def bind_to(environment)
    @environment = environment
    children.each do |child|
      child.bind_to(environment)
    end
  end

  def clazz
    "container"
  end

  def to_specs
    children.map(&:to_specs).flatten
  end

  def [](key)
    @definitions[key]
  end
end
