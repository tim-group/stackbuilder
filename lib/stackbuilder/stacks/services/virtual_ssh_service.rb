require 'stackbuilder/stacks/namespace'

module Stacks::Services::VirtualSshService
  def to_loadbalancer_config(location, fabric)
    grouped_realservers = realservers(location).group_by do |_|
      'blue'
    end

    realservers = Hash[grouped_realservers.map do |group, grealservers|
      grealserver_fqdns = grealservers.map(&:prod_fqdn).sort
      [group, grealserver_fqdns]
    end]

    {
      vip_fqdn(:prod, fabric) => {
        'type'              => 'ssh',
        'ports'             => '22',
        'realservers'       => realservers,
      }
    }
  end
end
