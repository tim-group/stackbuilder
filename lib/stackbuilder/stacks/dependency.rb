class Stacks::Dependency

  attr_reader :dependable_name
  attr_reader :service_name
  attr_reader :environment_name

  def initialize(dependable_name, service_name, environment_name=nil)
    @dependable_name = dependable_name
    @service_name = service_name
    @environment_name = environment_name
  end

  def ==(dep)
    return false unless @dependable_name == dep.dependable_name
    return false unless @service_name == dep.service_name
    return false unless @environment_name == dep.environment_name
    true
  end

  def to_hash
    {
      @dependable_name => {
        :service_name => @service_name,
        :environment_name => @environment_name
      }
    }
  end
end
