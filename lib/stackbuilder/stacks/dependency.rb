class Stacks::Dependency

  attr_reader :dependable_name
  attr_reader :service_name
  attr_reader :environment_name

  def initialize(dependable_name, service_name, environment_name=nil)
    @dependable_name = dependable_name
    @service_name = service_name
    @environment_name = environment_name
  end

end
