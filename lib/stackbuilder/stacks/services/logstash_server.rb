require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::LogstashServer < Stacks::MachineDef
  attr_accessor :role

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @version = '2.2.0'
  end

  def stackname
    @virtual_service.name
  end

  def role?(role)
    @role == role
  end

  def to_enc
    enc = super()

    elastic_vip = @virtual_service.vip_i_depend_on_for_clazz('elasticsearchcluster', @location) if role?(:indexer)
    rabbitmq_vip = @virtual_service.vip_i_depend_on_for_clazz('rabbitmqcluster', @location)

    enc.merge!("role::logstash::#{@role}" => {
                 'version'      => @version,
                 'rabbitmq_vip' => rabbitmq_vip,
                 'elastic_vip'  => elastic_vip
               })
    enc
  end
end
