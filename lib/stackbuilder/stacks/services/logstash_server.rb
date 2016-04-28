require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::LogstashServer < Stacks::MachineDef
  attr_accessor :role

  def initialize(base_hostname, _i, logstash_cluster, role, location)
    super(base_hostname, [:mgmt, :prod], location)

    @logstash_cluster = logstash_cluster
    @role = role
    @version = '2.2.0'
    @location = location
  end

  def stackname
    @logstash_cluster.name
  end

  def role?(role)
    @role == role
  end

  def to_enc
    enc = super()

    elastic_vip = @logstash_cluster.vip_i_depend_on_for_clazz('elasticsearchcluster', @location) if role?(:indexer)
    rabbitmq_vip = @logstash_cluster.vip_i_depend_on_for_clazz('rabbitmqcluster', @location)

    enc.merge!("role::logstash::#{@role}" => {
                 'version'      => @version,
                 'rabbitmq_vip' => rabbitmq_vip,
                 'elastic_vip'  => elastic_vip
               })
    enc
  end
end
