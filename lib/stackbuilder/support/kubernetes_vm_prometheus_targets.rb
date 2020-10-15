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
              'name' => get_name(thing),
              'namespace' => 'vm-metrics',
              'labels' => {
                'app.kubernetes.io/managed-by' => 'stacks',
                'app.kubernetes.io/component' => 'vm_metrics_target',
                'app' => thing.virtual_service.application,
                'group' => thing.group,
                'environment' => thing.environment.name
              }
            },
            'spec' => {
              'type' => 'ExternalName',
              'externalName' => "vm-metrics-#{thing.prod_fqdn}",
              'ports' => [{
                'name' => 'metrics',
                'port' => 8001,
                'targetPort' => 8001
              }]
            }
          }
          crds << {
            'apiVersion' => 'v1',
            'kind' => 'Endpoints',
            'metadata' => {
              'name' => get_name(thing),
              'namespace' => 'vm-metrics',
              'labels' => {
                'app.kubernetes.io/managed-by' => 'stacks',
                'app.kubernetes.io/component' => 'vm_metrics_target'
              }
            },
            'subsets' => [{
              'addresses' => [{ 'ip' => "#{get_ip(thing)}" }],
              'ports' => [{
                'name' => 'metrics',
                'port' => 8001,
                'protocol' => 'TCP'
              }]
            }]
          }
        end
      end
    end
    crds
  end

  def get_name(thing)
    prefix = 'metrics-'
    name = thing.hostname
    if name.length > 63 - prefix.length
      name = "#{thing.environment.name}-#{thing.virtual_service.short_name}-#{sprintf('%03d', thing.index)}"
    end
    "#{prefix}#{name}"
  end

  def get_ip(thing)
    thing.fabric == 'lon' ? @dns_resolver.lookup(thing.mgmt_fqdn) : @dns_resolver.lookup(thing.prod_fqdn)
  end
end
