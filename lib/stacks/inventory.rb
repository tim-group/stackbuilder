require "English"

class Stacks::Inventory
  def initialize(stack_dir)
    @stacks = Object.new
    @stacks.extend Stacks::DSL
    Dir.glob("#{stack_dir}/*.rb").each do |stack_file|
      begin
        @stacks.instance_eval(IO.read(stack_file))
      rescue
        backtrace = $ERROR_POSITION.join("\n")
        raise "Unable to instance_eval #{stack_file}\n#{$ERROR_INFO}\n#{backtrace}"
      end
    end
  end

  def find(fqdn)
    @stacks.find(fqdn)
  end

  def find_by_hostname(hostname)
    @stacks.find_by_hostname(hostname)
  end

  def find_environment(name)
    @stacks.find_environment(name)
  end
end
