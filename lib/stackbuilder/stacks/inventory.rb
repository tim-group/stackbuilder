require 'English'

class Stacks::Inventory
  def self.from_dir(stack_dir)
    stack_dir = File.expand_path(stack_dir)
    stacks = Object.new
    stacks.extend Stacks::DSL
    files = Dir.glob("#{stack_dir}/*.rb").sort +
            Dir.glob("#{stack_dir}/stacks/*.rb").sort +
            Dir.glob("#{stack_dir}/envs/*.rb").sort
    files.each do |stack_file|
      begin
        stacks.instance_eval(IO.read(stack_file))
      rescue
        backtrace = $ERROR_POSITION.join("\n")
        raise "Unable to instance_eval #{stack_file}\n#{$ERROR_INFO}\n#{backtrace}"
      end
    end

    Stacks::Inventory.new(stacks)
  end

  def self.from(&block)
    stacks = Object.new
    stacks.extend Stacks::DSL
    stacks.instance_eval(&block)

    Stacks::Inventory.new(stacks)
  end

  def initialize(stacks)
    @stacks = stacks
  end

  def find(fqdn)
    @stacks.find(fqdn)
  end

  def find_by_hostname(fabric, hostname)
    @stacks.find_by_hostname(fabric, hostname)
  end

  def find_environment(name)
    @stacks.find_environment(name)
  end

  def environments
    @stacks.environments
  end
end
