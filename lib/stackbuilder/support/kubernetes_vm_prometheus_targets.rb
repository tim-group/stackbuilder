require 'stackbuilder/support/namespace'
require 'stackbuilder/support/unit_conversion'

class Support::KubernetesVmPrometheusTargets
  def generate(environments, site)
    crds = []
    environments.each do |env|
      env.accept do |thing|

        if thing.respond_to?(:mgmt_fqdn) &&
          thing.site == site &&
          thing.virtual_service.scrape_metrics
          crds << thing.name
        end
      end
    end

    crds
  end
end
