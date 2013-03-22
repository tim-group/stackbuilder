class Stacks::Inventory

  def initialize(stack_dir)
    stack_file = "#{stack_dir}/stack.rb"
    raise "no stack.rb found in #{stack_dir}" unless File.exist? stack_file

    @stacks = Object.new
    @stacks.extend Stacks::DSL
    @stacks.instance_eval(IO.read(stack_file), stack_file)
  end

  def find(hostname)
    return @stacks.find(hostname)
  end

end
