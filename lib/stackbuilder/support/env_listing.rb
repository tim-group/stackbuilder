require 'stackbuilder/support/namespace'

class Support::EnvListing
  def initialize(terse = false)
    @terse = terse
  end

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

  def traverse(indent, is_last, thing, envs_only)
    case thing.type_of?
    when :environment
      name = thing.identity
      sub = thing.parent.nil? ? '' : '(sub)'
      type = "[0;35m#{thing.type_of?}#{sub}[0m"
    when :custom_service, :machine_set, :virtual_service
      type = "[0;36m#{thing.type_of?}[0m"
      name = thing.name
    when :machine_def
      type = "[0;32m#{thing.type_of?}[0m"
      name = thing.identity
    else
      type = "[0;36m#{thing.clazz}[0m"
      name = thing.name
    end

    ptr, space, char = case is_last
                       when nil then   [' * ', '',   '']   # root
                       when false then ['-> ', ' |', ' |'] # middle item
                       when true then  ['-> ', '  ', ' `'] # last item
    end

    printf("[0;33m%s[0m%s %s\n", indent + char + ptr, type, name)
    indent += space

    return unless thing.respond_to?(:children) || thing.respond_to?(:k8s_children)

    children = thing.children + thing.k8s_children
    children.select! { |m| m.clazz != 'machine' } if @terse
    children.select! { |m| m.respond_to?(:domain_suffix) } if envs_only

    last = children.count - 1
    children.each_with_index do |child, index|
      traverse(indent, index == last, child, envs_only)
    end
  end
end
