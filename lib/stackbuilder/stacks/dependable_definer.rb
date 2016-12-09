require 'stackbuilder/stacks/namespace'

module Stacks::DependableDefiner

  attr_reader :dependables

  def define_dependable(class_name, **args)
    dep = class_name.new(args[:name])
    fail("Cannot redefine dependable named '#{dep.name}'") unless @dependables[dep.name].nil?
    @dependables[dep.name] = dep
  end

  def dependable_by_name(name)
    @dependables[name]
  end

  def init_dependable_definer
    @dependables = {} if @dependables.nil?
  end

  private
  def self.extended(object)
    object.init_dependable_definer
  end
end
