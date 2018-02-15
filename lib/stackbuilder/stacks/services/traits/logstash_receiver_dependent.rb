module Stacks::Services::Traits::LogstashReceiverDependent
  def logstash_receiver_hosts
    return [] if !@virtual_service.is_a? Stacks::Dependencies

    @virtual_service.virtual_services_that_i_depend_on.select do |service|
      service.is_a?(Stacks::Services::LogstashReceiverCluster)
    end.map(&:children).flatten.select do |machine|
      machine.site == @site
    end.map(&:mgmt_fqdn).sort.uniq
  end

  def filebeat_profile_enc
    hosts = logstash_receiver_hosts

    if !hosts.nil? && !hosts.empty?
      {
        'profiles::filebeat' => {
          'logstash_receiver_hosts' => hosts
        }
      }
    else
      {}
    end
  end
end
