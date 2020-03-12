require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/kubernetes_vm_model'
require 'spec_helper'

describe Support::KubernetesVmModel do
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
            machine.modify_storage({ '/' => { :size => '3G' }})
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

  describe 'stacks:vm_info' do
    it "records a metric for each VM in the site" do
      vm_model = Support::KubernetesVmModel.new()
      out = vm_model.generate(factory.inventory.environments.map(&:last), 'space')

      # underscores so that this can be joined with another metric
      # (uptime_uptime) that uses underscores. Not ideal, but this shouldn't
      # be a major use case
      expect(out['spec']['groups'].first['rules'].select { |r| r['record'] == 'stacks:vm_info' }.map { |r| r['labels']['server'] }).to contain_exactly('e1-myappservice-001_mgmt_space_net_local', 'e1-myappservice-002_mgmt_space_net_local')
    end

    it "labels the metrics with the OS that the VM has" do
      vm_model = Support::KubernetesVmModel.new()
      out = vm_model.generate(factory.inventory.environments.map(&:last), 'sun')

      expect(out['spec']['groups'].first['rules'].select { |r| r['record'] == 'stacks:vm_info' }.map { |r| r['labels']['os'] }).to contain_exactly('trusty', 'precise', 'precise')
    end
  end

  describe 'stacks:vm_ram' do
    it "records the RAM in bytes" do
      vm_model = Support::KubernetesVmModel.new()
      out = vm_model.generate(factory.inventory.environments.map(&:last), 'space')

      expect(out['spec']['groups'].first['rules'].select { |r| r['record'] == 'stacks:vm_ram' }.map { |r| r['expr'] }).to contain_exactly('vector(3221225472.0)', 'vector(3221225472.0)')
    end
  end

  describe 'stacks:vm_vcpus' do
    it "records the number of virtual CPUs" do
      vm_model = Support::KubernetesVmModel.new()
      out = vm_model.generate(factory.inventory.environments.map(&:last), 'space')

      expect(out['spec']['groups'].first['rules'].select { |r| r['record'] == 'stacks:vm_vcpus' }.map { |r| r['expr'] }).to contain_exactly('vector(3)', 'vector(3)')
    end
  end

  describe 'stacks:vm_storage' do
    it "records the mounted storage space" do
      vm_model = Support::KubernetesVmModel.new()
      out = vm_model.generate(factory.inventory.environments.map(&:last), 'space')

      expect(out['spec']['groups'].first['rules'].select { |r| r['record'] == 'stacks:vm_storage' }.map { |r| r['expr'] }).to contain_exactly('vector(3221225472.0)', 'vector(3221225472.0)')
    end
  end
end
