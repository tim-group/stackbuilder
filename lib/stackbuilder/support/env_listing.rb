require 'stackbuilder/support/namespace'

class Support::EnvListing
  def ls(target, envs_only = false)
    root = target.instance_of?(Array) ? FakeLsRoot.new(target) : target
    traverse('', nil, root, envs_only)
  end

  private

  class FakeLsRoot
    attr_reader :children
    attr_reader :name
    attr_reader :clazz

    def initialize(children)
      @children = children
      @name = 'root'
      @clazz = 'root'
    end

    def type_of?
      @clazz
    end
  end

  def traverse(indent, is_last, machine_def, envs_only)
    case machine_def.type_of?
    when :environment
      name = machine_def.identity
      sub = machine_def.parent.nil? ? '' : '(sub)'
      type = "[0;35m#{machine_def.type_of?}#{sub}[0m"
    when :custom_service, :machine_set, :virtual_service
      type = "[0;36m#{machine_def.type_of?}[0m"
      name = machine_def.name
    when :machine_def
      type = "[0;32m#{machine_def.type_of?}[0m"
      name = machine_def.identity
    else
      type = "[0;36m#{machine_def.clazz}[0m"
      name = machine_def.name
    end

    ptr, space, char = case is_last
                       when nil then   [' * ', '',   '']   # root
                       when false then ['-> ', ' |', ' |'] # middle item
                       when true then  ['-> ', '  ', ' `'] # last item
    end

    printf("[0;33m%s[0m%s %s\n", indent + char + ptr, type, name)
    indent += space

    return unless machine_def.respond_to?(:children)

    children = machine_def.children
    children.select! { |m| m.clazz != 'machine' } if $options[:terse]
    children.select! { |m| m.respond_to?(:domain_suffix) } if envs_only

    last = children.count - 1
    children.each_with_index do |child, index|
      traverse(indent, index == last, child, envs_only)
    end
  end
end
