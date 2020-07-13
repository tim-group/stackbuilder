require 'stackbuilder/support/namespace'
require 'stackbuilder/support/unit_conversion'

class Support::KubernetesVmPrometheusTargets
  def initialize(dns_resolver)
    @dns_resolver = dns_resolver
  end

  def generate(environments, site)
    crds = []
    environments.each do |env|
      env.accept do |thing|
        if thing.respond_to?(:mgmt_fqdn) &&
           thing.site == site &&
           (thing.virtual_service.is_a? Stacks::Services::AppService) &&
           thing.virtual_service.scrape_metrics
          crds << {
            'apiVersion' => 'v1',
            'kind' => 'Service',
            'metadata' => {
              'name' => "metrics-#{thing.hostname}",
              'namespace' => 'vm-metrics',
              'labels' => {
                'app.kubernetes.io/managed-by' => 'stacks',
                'app.kubernetes.io/component' => 'vm_metrics_target',
                'app' => thing.virtual_service.application,
                'group' => thing.group,
                'server' => thing.hostname,
                'site' => thing.site,
                'environment' => thing.environment.name
              }
            },
            'spec' => {
              'type' => 'ExternalName',
              'externalName' => "vm-metrics-#{thing.prod_fqdn}",
              'ports' => [{
                'name' => 'metrics',
                'port' => 8000,
                'targetPort' => 8000
              }]
            }
          }
          crds << {
            'apiVersion' => 'v1',
            'kind' => 'Endpoints',
            'metadata' => {
              'name' => "metrics-#{thing.hostname}",
              'namespace' => 'vm-metrics',
              'labels' => {
                'app.kubernetes.io/managed-by' => 'stacks',
                'app.kubernetes.io/component' => 'vm_metrics_target'
              }
            },
            'subsets' => [{
              'addresses' => [{ 'ip' => "#{@dns_resolver.lookup(thing.prod_fqdn)}" }],
              'ports' => [{
                'name' => 'metrics',
                'port' => 8000,
                'protocol' => 'TCP'
              }]
            }]
          }
        end
      end
    end
    crds
  end
end
