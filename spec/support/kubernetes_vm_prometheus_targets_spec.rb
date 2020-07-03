require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/kubernetes_vm_prometheus_targets'
require 'spec_helper'

describe Support::KubernetesVmPrometheusTargets do
  let(:factory) do
    eval_stacks do
      stack "mystack" do
        app_service "myappservice" do
          self.application = 'MyApplication'
          self.instances = 2
          self.scrape_metrics = true
        end
      end
      stack "myk8sstack" do
        app_service "myk8sappservice", :kubernetes => true do
          self.maintainers = [person('Testers')]
          self.description = 'Testing'

          self.application = 'MyK8sApplication'
          self.instances = 2
        end
      end
      stack "mysql_stack" do
        mysql_cluster "db" do
          self.database_name = 'my_application'
        end
      end
      stack "no_scrape_app_stack" do
        app_service "noscrape" do
          self.application = 'MyApplication'
          self.instances = 1
          self.scrape_metrics = false
        end
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "mystack"
        instantiate_stack "myk8sstack"
      end
    end
  end

  describe 'stacks:kubernetes_vm_prometheus_targets' do
    it "ignores_stacks_without_scrape_metrics" do
      vm_prom_targets = Support::KubernetesVmPrometheusTargets.new
      out = vm_prom_targets.generate(factory.inventory.environments.map(&:last), 'space')

      expect(out.map { |crd| crd['metadata']['name'] }).to match_array([
        "metrics-e1-myappservice-001",
        "metrics-e1-myappservice-002"
      ])
    end
  end
end
