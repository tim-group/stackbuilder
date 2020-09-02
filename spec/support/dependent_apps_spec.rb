require 'stackbuilder/support/dependent_apps'
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

def new_environment(name, options)
  Stacks::Environment.new(name, options, nil, {}, {}, Stacks::CalculatedDependenciesCache.new)
end

def make_dependent_apps(host)
  Support::DependentApps.new(host.environment, host.virtual_service)
end

describe Support::DependentApps do
  describe_stack 'should stop or start all dependent apps' do
    given do
      stack 'databases' do
        mysql_cluster 'the-mysql-db'
        mysql_cluster 'mysql-db-no-dependencies'
      end
      stack 'dependent_apps' do
        standalone_app_service 'the-vm-app' do
          self.application = 'MyApp'
          self.groups = %w(purple)
          depend_on 'the-mysql-db'
        end

        app_service 'the-k8s-app', :kubernetes => true do
          self.application = 'MyApp'
          self.groups = %w(yellow)
          depend_on 'the-mysql-db'
        end

        standard_service 'not-an-app' do
          depend_on 'the-mysql-db'
        end
      end

      env 'e1', :primary_site => 'space' do
        instantiate_stack "databases"
        instantiate_stack "dependent_apps"
      end
      env 'e2', :primary_site => 'earth' do
        instantiate_stack "databases"
      end
    end

    host('e1-the-mysql-db-001.mgmt.space.net.local') do |host|
      dependent_apps = make_dependent_apps(host)

      expect(dependent_apps.unsafely_stop_commands).to eql([
        DependentAppKubectlCommand.new('the-k8s-app-yellow-app', 'e1', 'space'),
        DependentAppMcoCommand.new('e1', 'MyApp', 'purple', 'stop')
      ].to_set)

      expect(dependent_apps.unsafely_start_commands).to eql([
        DependentAppMcoCommand.new('e1', 'MyApp', 'purple', 'start'),
        DependentAppStacksApplyCommand.new('e1', 'the-k8s-app')
      ].to_set)
    end

    host('e2-the-mysql-db-001.mgmt.earth.net.local') do |host|
      dependent_apps = make_dependent_apps(host)
      expect(dependent_apps.unsafely_stop_commands).to be_empty
      expect(dependent_apps.unsafely_start_commands).to be_empty
    end

    host('e1-mysql-db-no-dependencies-001.mgmt.space.net.local') do |host|
      dependent_apps = make_dependent_apps(host)
      expect(dependent_apps.unsafely_stop_commands).to be_empty
      expect(dependent_apps.unsafely_start_commands).to be_empty
    end
  end

  it 'constructs system call to stop service via mco' do
    expect(DependentAppMcoCommand.new('e1', 'MyApp', 'purple', 'stop').executable).
      to eql('mco service e1-MyApp-purple stop -F logicalenv=e1 -F application=MyApp -F group=purple')
  end

  it 'constructs system call to start service via mco' do
    expect(DependentAppMcoCommand.new('e1', 'MyApp', 'purple', 'start').executable).
      to eql('mco service e1-MyApp-purple start -F logicalenv=e1 -F application=MyApp -F group=purple')
  end

  it 'constructs system call to scale down a k8s deployment to zero replicas' do
    expect(DependentAppKubectlCommand.new('the-k8s-app-yellow-app', 'e1', 'earth').executable).
      to eql('kubectl --context=earth -n e1 scale deploy the-k8s-app-yellow-app --replicas=0')
  end
end
