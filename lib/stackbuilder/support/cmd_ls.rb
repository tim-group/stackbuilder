module CMDLs
  require 'stackbuilder/support/cmd'

  def self.ls
    machine_def = $options[:stack] ? Opt.stack : $environment
    traverse('', nil, machine_def)
  end

  private

  def self.traverse(indent, is_last, machine_def)
    case machine_def.clazz
    when 'container'
      if machine_def.respond_to?(:domain_suffix) # environment
        type = '[0;35mE[0m'
        name = machine_def.name
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

    last = children.count - 1
    children.each_with_index do |child, index|
      traverse(indent, index == last, child)
    end
  end
end
