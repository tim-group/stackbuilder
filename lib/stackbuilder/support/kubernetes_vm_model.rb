require 'stackbuilder/support/namespace'
require 'stackbuilder/support/unit_conversion'

class Support::KubernetesVmModel
  def generate(environments, site)
    rules = []
    crd = {
      'apiVersion' => 'monitoring.coreos.com/v1',
      'kind' => 'PrometheusRule',
      'metadata' => {
        'name' => 'stacks-model-rules',
        'namespace' => 'monitoring',
        'labels' => {
          'app.kubernetes.io/managed-by' => 'stacks',
          'prometheus' => 'main',
          'role' => 'alert-rules'
        }
      },
      'spec' => {
        'groups' => [{
          'name' => 'stacks.rules',
          'rules' => rules
        }]
      }
    }

    environments.each do |env|
      env.accept do |thing|
        if thing.respond_to?(:mgmt_fqdn) && thing.site == site
          server = thing.mgmt_fqdn.gsub('.', '_')
          rules << {
            'record' => 'stacks:vm_info',
            'expr' => 'vector(1)',
            'labels' => {
              'environment' => thing.environment.name,
              'stack' => thing.virtual_service.name,
              'server' => server,
              'fqdn' => thing.mgmt_fqdn,
              'os' => thing.lsbdistcodename.to_s
            }
          }
          rules << {
            'record' => 'stacks:vm_ram',
            'expr' => "vector(#{Support::UnitConversion.data_to_unit(thing.ram + 'K', 'B')})",
            'labels' => {
              'environment' => thing.environment.name,
              'stack' => thing.virtual_service.name,
              'server' => server,
              'fqdn' => thing.mgmt_fqdn
            }
          }
          rules << {
            'record' => 'stacks:vm_vcpus',
            'expr' => "vector(#{thing.vcpus})",
            'labels' => {
              'environment' => thing.environment.name,
              'stack' => thing.virtual_service.name,
              'server' => server,
              'fqdn' => thing.mgmt_fqdn
            }
          }
          thing.storage.each do |path, info|
            rules << {
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
        end
      end
    end

    crd
  end
end
