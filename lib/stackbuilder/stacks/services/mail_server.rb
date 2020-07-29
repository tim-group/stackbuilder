require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'
require 'resolv'

class Stacks::Services::MailServer < Stacks::MachineDef
  attr_reader :virtual_service

  def to_enc
    enc = super()
    vip_fqdns = @virtual_service.vip_networks.map do |vip_network|
      if [:front].include? vip_network
        nil
      else
        @virtual_service.vip_fqdn(vip_network, @fabric)
      end
    end

    vip_fqdns.compact!
    enc.merge!('role::mail_server2' => {
                 'allowed_hosts'       => @virtual_service.allowed_hosts,
                 'vip_fqdns'           => vip_fqdns,
                 'vip_networks'        => @virtual_service.vip_networks.map(&:to_s),
                 'dependant_instances' =>
                   @virtual_service.dependant_load_balancer_fqdns(location, @virtual_service.vip_networks),
                 'participation_dependant_instances' =>
                   @virtual_service.dependant_load_balancer_fqdns(location, @virtual_service.vip_networks)
               },
               'server' => {
                 'postfix' => false
               })
    enc['server']['spectre_patches'] = @spectre_patches if @spectre_patches

    add_dependant_kubernetes_things enc

    enc
  end

  private

  def add_dependant_kubernetes_things(enc)
    dependant_app_services = @virtual_service.virtual_services_that_depend_on_me.select do |machine_set|
      machine_set.is_a? Stacks::Services::SharedAppLikeThing
    end

    return unless dependant_app_services.any?(&:kubernetes)
    enc['role::mail_server2']['allow_kubernetes_clusters'] = dependant_app_services.select(&:kubernetes).map { |vs| vs.environment.options[location] }.uniq
  end
end
