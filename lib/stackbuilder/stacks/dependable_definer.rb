require 'stackbuilder/stacks/namespace'

module Stacks::DependableDefiner

  attr_reader :dependables

  def define_dependable(class_name, **args)
    dep = class_name.new(args[:name])
    fail("Cannot redefine dependable named '#{dep.name}' on service '#{self.kind_of?(Stacks::MachineDef) ? mgmt_fqdn : @name}' in environment '#{environment.name}'") unless dependable_by_name(dep.name).empty?
    @dependables << dep
  end

  def init_dependable_definer
    @dependables = [] if @dependables.nil?
  end

  def dependable_by_name(name)
    @dependables.select do |dependable|
      dependable.name == name
    end
  end

  def dependables_to_hash
    merged_hash = {}
    @dependables.each do |dependable|
      merged_hash.merge! dependable.to_hash
    end
    merged_hash
  end

  private
  def self.extended(object)
    object.init_dependable_definer
  end

end
