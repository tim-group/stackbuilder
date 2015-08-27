module CMDLs
  def ls(_argv)
    machine_def = $options[:stack] ? check_and_get_stack : $environment
    traverse('', nil, machine_def)
  end

  def lsenv(_argv)
    @lsenv = true
    root = Class.new do
      attr_reader :children

      def initialize
        @children = $environment.environments.map { |x| x[1] }
      end

      def name
        'root'
      end

      def clazz
        'root'
      end
    end.new

    traverse('', nil, root)
  end

  private

  def traverse(indent, is_last, machine_def)
    case machine_def.clazz
    when 'container'
      if machine_def.respond_to?(:domain_suffix) # environment
        name = machine_def.name
        type = machine_def.parent == nil ? '[0;35mE[0m' : '[0;35me[0m'
      else
        type = '[0;36mC[0m'
        name = machine_def.name
      end
    when 'machine'
      type = '[0;32mm[0m'
      name = machine_def.mgmt_fqdn
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
    children.select! { |m| m.respond_to?(:domain_suffix) } if @lsenv

    last = children.count - 1
    children.each_with_index do |child, index|
      traverse(indent, index == last, child)
    end
  end
end
