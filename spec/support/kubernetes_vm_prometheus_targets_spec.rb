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
          depend_on 'myk8sappservice'

          each_machine do |machine|
            machine.ram = '3G'
            machine.vcpus = 3
            machine.template(:precise)
            machine.modify_storage('/' => { :size => '3G' })
          end
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
      stack "myotherosstack" do
        app_service "otheros" do
          self.application = 'MyApplication'
          self.instances = 1

          each_machine do |machine|
            machine.template(:trusty)
          end
        end
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "mystack"
        instantiate_stack "myk8sstack"
      end
      env 'e2', :primary_site => 'sun' do
        instantiate_stack "mystack"
        instantiate_stack "myk8sstack"
        instantiate_stack "myotherosstack"
      end
    end
  end

  describe 'stacks:kubernetes_vm_prometheus_targets' do
    it "generates_targets_for_stack" do
      vm_prom_targets = Support::KubernetesVmPrometheusTargets.new
      out = vm_prom_targets.generate(factory.inventory.environments.map(&:last), 'space')

      expect(out).to eq([])
    end
  end
end
