require 'English'
require 'stackbuilder/stacks/validation/no_duplicate_short_names'

class Stacks::Inventory
  def self.from_dir(stack_dir)
    stacks = prepare_inventory_from_dir(stack_dir)
    Stacks::Inventory.new(stacks)
  end

  def self.from(&block)
    stacks = prepare_inventory_from(&block)
    Stacks::Inventory.new(stacks)
  end

  def initialize(stacks, validators = [
    Stacks::Validation::NoDuplicateShortName
  ])
    validation_output = Stacks::Validator.validate(stacks, validators)
    fail(validation_output) unless validation_output.empty?
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

  def find_sited_environment(environment_name, site_name)
    @stacks.find_sited_environment(environment_name, site_name)
  end

  def environments
    @stacks.environments
  end

  def fqdn_list
    @stacks.fqdn_list
  end

  def self.prepare_inventory_from_dir(stack_dir)
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
    stacks
  end

  def self.prepare_inventory_from(&block)
    stacks = Object.new
    stacks.extend Stacks::DSL
    stacks.instance_eval(&block)
    stacks
  end
end
