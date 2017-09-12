module Stacks::Services::KafkaCluster
  attr_accessor :primary_instances
  attr_accessor :secondary_instances
  attr_accessor :name

  def configure
    @name = ''
  end

  def config_params(_dependent, fabric)
    config_params = {
      "kafka.#{@name}.cluster" => all_servers(fabric).join(',')
    }
    config_params
  end

  def all_servers(fabric)
    children.select { |server| server.fabric == fabric }.inject([]) do |prod_fqdns, server|
      prod_fqdns << server.prod_fqdn
      prod_fqdns.sort
    end
  end
end
