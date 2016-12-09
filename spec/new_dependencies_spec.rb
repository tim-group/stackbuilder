require 'stackbuilder/stacks/environment'
#require 'stackbuilder/stacks/factory'
require 'stackbuilder/stacks/dependable'
require 'stackbuilder/stacks/dependency'
require 'stacks/test_framework'

describe_stack 'a service can define a depenable' do
  given do
    stack 'standard' do
      standard_service 'test' do
        define_dependable Stacks::Dependable, :name => 'test service dep'
        self.instances = 1
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test-001.mgmt.lon.net.local') do |host|
    expect(host.virtual_service.dependable_by_name('test service dep')).to be_a_kind_of(Stacks::Dependable)
  end
end

describe_stack 'a machine can define a depenable' do
  given do
    stack 'standard' do
      standard_service 'test' do
        self.instances = 1
        each_machine do |machine|
          machine.define_dependable Stacks::Dependable, :name => 'test machine dep'
        end
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test-001.mgmt.lon.net.local') do |host|
    expect(host.dependable_by_name('test machine dep')).to be_a_kind_of Stacks::Dependable
  end
end

describe_stack 'a machine registers a dependency' do
  given do
    stack 'standard' do
      standard_service 'test2' do
        self.instances = 1
        each_machine do |machine|
          machine.depends_on_new 'test machine dep', 'test1'
        end
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(1)
    dep = host.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('test1')
    expect(dep.environment_name).to eq('e1')
  end
end

describe_stack 'a service registers a dependency' do
  given do
    stack 'standard' do
      standard_service 'test2' do
        self.instances = 1
        depends_on_new 'test service dep', 'test1'
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.virtual_service.dependencies.size).to be(1)
    dep = host.virtual_service.dependencies.first
    expect(dep.dependable_name).to eq('test service dep')
    expect(dep.service_name).to eq('test1')
    expect(dep.environment_name).to eq('e1')
  end
end

describe_stack 'a machine registers a dependency thats successfully validated against another machines dependable' do
  given do
    stack 'standard' do
      standard_service 'test1' do
        self.instances = 1
        each_machine do |machine|
          machine.define_dependable Stacks::Dependable, :name => 'test machine dep'
        end
      end

      standard_service 'test2' do
        self.instances = 1
        each_machine do |machine|
          machine.depends_on_new 'test machine dep', 'test1'
        end
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(1)
    dep = host.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('test1')
    expect(dep.environment_name).to eq('e1')
  end

  all_hosts do |host|
    host.resolve_dependencies if host.kind_of? Stacks::Dependent
  end
end

describe_stack 'a machine causes an error trying to register a dependency thats not resolved because the other service does not exist' do
  given do
    stack 'standard' do
      standard_service 'test2' do
        self.instances = 1
        each_machine do |machine|
          machine.depends_on_new 'test machine dep', 'test1'
        end
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(1)
    dep = host.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('test1')
    expect(dep.environment_name).to eq('e1')
  end

  all_hosts do |host|
    expect {
      host.resolve_dependencies if host.kind_of? Stacks::Dependent
    }.to raise_error 'Unable to find service test1 in environment e1'
  end
end
