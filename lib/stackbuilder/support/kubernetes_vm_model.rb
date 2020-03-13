require 'stackbuilder/support/namespace'
require 'stackbuilder/support/unit_conversion'

class Support::KubernetesVmModel
  def initialize(size)
    @size = size
  end

  def generate(environments, site)
    crds = []
    crd, groups = new_crd(crds.size + 1)
    crds << crd
    count = 0

    environments.each do |env|
      env.accept do |thing|
        if thing.respond_to?(:mgmt_fqdn) && thing.site == site
          if count >= @size
            count = 0
            crd, groups = new_crd(crds.size + 1)
            crds << crd
          end
          count += 1

          server = thing.mgmt_fqdn.gsub('.', '_')
          groups << {
            'name' => server,
            'rules' => [
              {
                'record' => 'stacks:vm_info',
                'expr' => 'vector(1)',
                'labels' => {
                  'environment' => thing.environment.name,
                  'stack' => thing.virtual_service.name,
                  'server' => server,
                  'fqdn' => thing.mgmt_fqdn,
                  'os' => thing.lsbdistcodename.to_s
                }
              }, {
                'record' => 'stacks:vm_ram',
                'expr' => "vector(#{Support::UnitConversion.data_to_unit(thing.ram + 'K', 'B')})",
                'labels' => {
                  'environment' => thing.environment.name,
                  'stack' => thing.virtual_service.name,
                  'server' => server,
                  'fqdn' => thing.mgmt_fqdn
                }
              }, {
                'record' => 'stacks:vm_vcpus',
                'expr' => "vector(#{thing.vcpus})",
                'labels' => {
                  'environment' => thing.environment.name,
                  'stack' => thing.virtual_service.name,
                  'server' => server,
                  'fqdn' => thing.mgmt_fqdn
                }
              }] + thing.storage.map do |path, info|
                {
                  'record' => 'stacks:vm_storage',
                  'expr' => "vector(#{Support::UnitConversion.data_to_unit(info[:size], 'B')})",
                  'labels' => {
                    'environment' => thing.environment.name,
                    'stack' => thing.virtual_service.name,
                    'server' => server,
                    'fqdn' => thing.mgmt_fqdn,
                    'type' => info[:type],
                    'mount' => path.to_s
                  }
                }
              end
          }
        end
      end
    end

    crds
  end

  private

  def new_crd(number)
    groups = []
    [
      {
        'apiVersion' => 'monitoring.coreos.com/v1',
        'kind' => 'PrometheusRule',
        'metadata' => {
          'name' => "stacks-model-rules-part-#{number}",
          'namespace' => 'production',
          'labels' => {
            'app.kubernetes.io/component' => 'stacks-model',
            'prometheus' => 'main',
            'role' => 'alert-rules'
          }
        },
        'spec' => {
          'groups' => groups
        }
      },
      groups
    ]
  end
end
