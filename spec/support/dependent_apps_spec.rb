require 'stackbuilder/support/dependent_apps'
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

def new_environment(name, options)
  Stacks::Environment.new(name, options, nil, {}, {}, Stacks::CalculatedDependenciesCache.new)
end

describe Support::DependentApps do
  describe_stack 'should do nothing if no apps depend on host' do
    given do
      stack 'intertwined_apps' do
        mysql_cluster 'the-mysql-db'
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "intertwined_apps"
      end
    end
    host('e1-the-mysql-db-001.mgmt.space.net.local') do |host|
      expect(Support::DependentApps.new(host.environment, host.virtual_service).unsafely_stop_commands).to be_empty
      expect(Support::DependentApps.new(host.environment, host.virtual_service).unsafely_start_commands).to be_empty
    end
  end

  describe_stack 'should stop or start all dependent apps' do
    given do
      stack 'intertwined_apps' do
        mysql_cluster 'the-mysql-db'

        standalone_app_service 'the-vm-app' do
          self.application = 'MyApp'
          self.groups = %w(purple)
          depend_on 'the-mysql-db', 'e1'
        end
        app_service 'the-k8s-app', :kubernetes => true do
          self.application = 'MyApp'
          self.groups = %w(yellow)
          depend_on 'the-mysql-db', 'e1'
        end

      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "intertwined_apps"
      end
    end

    host('e1-the-mysql-db-001.mgmt.space.net.local') do |host|
      stop_commands = Support::DependentApps.new(host.environment, host.virtual_service).unsafely_stop_commands
      expect(stop_commands).to eql([
        DependentAppKubectlCommand.new('the-k8s-app-yellow-app', 'e1', 'space'),
        DependentAppMcoCommand.new('e1', 'MyApp', 'purple', 'stop')
      ].to_set)

      start_commands = Support::DependentApps.new(host.environment, host.virtual_service).unsafely_start_commands
      expect(start_commands).to eql([
        DependentAppMcoCommand.new('e1', 'MyApp', 'purple', 'start'),
        DependentAppStacksApplyCommand.new('e1', 'the-k8s-app')
      ].to_set)
    end

    xhost('e2-the-mysql-db-001.mgmt.earth.net.local') do |host|
      expect(Support::DependentApps.new(host.environment, host.virtual_service).unsafely_stop_commands).to be_empty
      expect(Support::DependentApps.new(host.environment, host.virtual_service).unsafely_start_commands).to be_empty
    end
  end
end
