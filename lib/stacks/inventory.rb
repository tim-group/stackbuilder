class Stacks::Inventory

  def initialize(stack_dir)
    @stacks = Object.new
    @stacks.extend Stacks::DSL
    Dir.glob("#{stack_dir}/*.rb").each do |stack_file|
      begin
        @stacks.instance_eval(IO.read("#{stack_dir}/#{stack_file}"), "#{stack_dir}/#{stack_file}")
      rescue
        backtrace = $@.join("\n")
        raise "Unable to instance_eval #{stack_file}\n#{$!}\n#{backtrace}"
      end
    end
  end

  def find(fqdn)
    return @stacks.find(fqdn)
  end

  def find_by_hostname(hostname)
    return @stacks.find_by_hostname(hostname)
  end

  def find_environment(name)
    return @stacks.find_environment(name)
  end

end
