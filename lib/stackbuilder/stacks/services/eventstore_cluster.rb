module Stacks::Services::EventStoreCluster
  attr_accessor :primary_instances
  attr_accessor :secondary_instances
  attr_accessor :eventstore_name

  def configure
    @eventstore_name = ''
  end

  def config_params(_dependent, fabric)
    config_params = {
      "eventstore.#{@eventstore_name}.cluster"           => all_servers(fabric).join(','),
      "eventstore.#{@eventstore_name}.username"           => 'admin',
      "eventstore.#{@eventstore_name}.password"           => 'changeit'
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
