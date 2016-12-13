require 'stackbuilder/stacks/environment'
#require 'stackbuilder/stacks/factory'
require 'stackbuilder/stacks/dependable'
require 'stackbuilder/stacks/dependency'
require 'stacks/test_framework'

describe_stack 'a machine_set can define a depenable' do
  given do
    stack 'standard' do
      standard_service 'test' do
        define_dependable Stacks::Dependable, :name => 'test machine_set dep'
        self.instances = 1
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  machine_set('test') do |machine_set|
    expect(machine_set.dependables.length).to be(1)
    dependable = machine_set.dependables.first
    expect(dependable).to be_a_kind_of(Stacks::Dependable)
    expect(dependable.name).to eq('test machine_set dep')
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
    expect(host.dependables.length).to be(1)
    dependable = host.dependables.first
    expect(dependable).to be_a_kind_of(Stacks::Dependable)
    expect(dependable.name).to eq('test machine dep')
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

describe_stack 'a machine_set registers a dependency' do
  given do
    stack 'standard' do
      standard_service 'test2' do
        self.instances = 1
        depends_on_new 'test machine_set dep', 'test1'
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.virtual_service.dependencies.size).to be(1)
    dep = host.virtual_service.dependencies.first
    expect(dep.dependable_name).to eq('test machine_set dep')
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
          machine.depends_on_new 'test machine dep', 'e1-test1-001.mgmt.lon.net.local'
        end
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test1-001.mgmt.lon.net.local') do |host|
    expect(host.dependables.length).to be(1)
    dependable = host.dependables.first
    expect(dependable).to be_a_kind_of(Stacks::Dependable)
    expect(dependable.name).to eq('test machine dep')
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(1)
    dep = host.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
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
    expect {
      host.resolve_dependencies
    }.to raise_error "Unable to resolve dependency: Cannot find service 'test1' in environment 'e1' for dependable 'test machine dep' required by service 'e1-test2-001.mgmt.lon.net.local' in environment 'e1'"
  end
end

describe_stack 'a machine causes an error trying to register a dependency thats not resolved because the other service does not have the dependable defined' do
  given do
    stack 'standard' do
      standard_service 'test1' do
        self.instances = 1
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

  host('e1-test1-001.mgmt.lon.net.local') do |host|
    expect(host.dependables.length).to be(0)
    host.resolve_dependencies
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(1)
    dep = host.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('test1')
    expect(dep.environment_name).to eq('e1')
    expect {
      host.resolve_dependencies
    }.to raise_error "Unable to resolve dependency: Cannot find dependable 'test machine dep' on service 'test1' in environment 'e1' required by service 'e1-test2-001.mgmt.lon.net.local' in environment 'e1'"
  end
end

describe_stack 'an error is raised if a machine registers a dependency that already exists' do
  given do
    stack 'standard' do
      standard_service 'test1' do
        self.instances = 1
        define_dependable Stacks::Dependable, :name => 'test machine dep'
      end
      standard_service 'test2' do
        self.instances = 1
        each_machine do |machine|
          machine.depends_on_new 'test machine dep', 'test1'
          machine.depends_on_new 'test machine dep', 'test1'
        end
      end
    end

    env 'e1', :primary_site => 'lon' do
        instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect {
      host.resolve_dependencies
    }.to raise_error "Duplicate dependency: e1-test2-001.mgmt.lon.net.local has dependency 'test machine dep' on service 'test1' in environment 'e1' defined more than once"
  end
end

describe_stack 'a machine_set registers a dependency thats successfully validated against another machine_set dependable' do
  given do
    stack 'standard' do
      standard_service 'test1' do
        self.instances = 1
        define_dependable Stacks::Dependable, :name => 'test machine dep'
      end

      standard_service 'test2' do
        self.instances = 1
        depends_on_new 'test machine dep', 'test1'
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(0)
#    dep = host.dependencies.first
#    expect(dep.dependable_name).to eq('test machine dep')
#    expect(dep.service_name).to eq('test1')
#    expect(dep.environment_name).to eq('e1')
  end

  machine_set('test2') do |machine_set|
    expect(machine_set.dependencies.size).to be(1)
    dep = machine_set.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('test1')
    expect(dep.environment_name).to eq('e1')
  end

  all_hosts do |host|
    host.resolve_dependencies if host.kind_of? Stacks::Dependent
  end
end

describe_stack 'a machine registers a dependency thats successfully validated against another machine_set dependable' do
  given do
    stack 'standard' do
      standard_service 'test1' do
        self.instances = 1
        define_dependable Stacks::Dependable, :name => 'test machine dep'
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

describe_stack 'a machine_set registers a dependency thats successfully validated against another machines dependable' do
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
        depends_on_new 'test machine dep', 'e1-test1-001.mgmt.lon.net.local'
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(0)
#    dep = host.dependencies.first
#    expect(dep.dependable_name).to eq('test machine dep')
#    expect(dep.service_name).to eq('test1')
#    expect(dep.environment_name).to eq('e1')
  end

  machine_set('test2') do |machine_set|
    expect(machine_set.dependencies.size).to be(1)
    dep = machine_set.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
    expect(dep.environment_name).to eq('e1')
  end

  all_hosts do |host|
    host.resolve_dependencies if host.kind_of? Stacks::Dependent
  end
end

describe_stack 'a machine_set registers a dependency thats successfully validated against another machine_set dependable, the associated machine also has the correct dependencies available in its associated machine_set' do
  given do
    stack 'standard' do
      standard_service 'test1' do
        self.instances = 1
        define_dependable Stacks::Dependable, :name => 'test machine dep'
      end

      standard_service 'test2' do
        self.instances = 1
        depends_on_new 'test machine dep', 'test1'
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(0)
    expect(host.virtual_service.dependencies.size).to be(1)
    dep = host.virtual_service.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('test1')
    expect(dep.environment_name).to eq('e1')
  end

  machine_set('test2') do |machine_set|
    expect(machine_set.dependencies.size).to be(1)
    dep = machine_set.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('test1')
    expect(dep.environment_name).to eq('e1')
  end

  all_hosts do |host|
    host.resolve_dependencies if host.kind_of? Stacks::Dependent
  end
end

describe_stack 'a machine_set registers a dependency thats successfully validated against a machines dependable, the machine associated with the original machine_set also has the correct dependencies available from the machine_set' do
  given do
    stack 'standard' do
      standard_service 'test1' do
        self.instances = 1
        each_machine do |machine|
          define_dependable Stacks::Dependable, :name => 'test machine dep'
        end
      end

      standard_service 'test2' do
        self.instances = 1
        depends_on_new 'test machine dep', 'e1-test1-001.mgmt.lon.net.local'
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(0)
    expect(host.virtual_service.dependencies.size).to be(1)
    dep = host.virtual_service.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
    expect(dep.environment_name).to eq('e1')
  end

  machine_set('test2') do |machine_set|
    expect(machine_set.dependencies.size).to be(1)
    dep = machine_set.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
    expect(dep.environment_name).to eq('e1')
  end

  all_hosts do |host|
    host.resolve_dependencies if host.kind_of? Stacks::Dependent
  end
end

describe_stack 'an error is raised if both a machine set and an associated machine try to depend on the same dependency' do
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
        depends_on_new 'test machine dep', 'e1-test1-001.mgmt.lon.net.local'
        each_machine do |machine|
          machine.depends_on_new 'test machine dep', 'e1-test1-001.mgmt.lon.net.local'
        end
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  machine_set('test2') do |machine_set|
    expect(machine_set.dependencies.size).to be(1)
    dep = machine_set.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
    expect(dep.environment_name).to eq('e1')
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(1)
    dep = host.virtual_service.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
    expect(dep.environment_name).to eq('e1')
    expect(host.virtual_service.dependencies.size).to be(1)
    dep = host.virtual_service.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
    expect(dep.environment_name).to eq('e1')
    expect {
      host.resolve_dependencies
    }.to raise_error "Duplicate dependency: e1-test2-001.mgmt.lon.net.local has dependency 'test machine dep' on service 'e1-test1-001.mgmt.lon.net.local' in environment 'e1' that is also defined by machine_set test2"
  end
end

describe_stack 'an error is raised if both a machine and its associated machine_set try to depend on the same dependency' do
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
        depends_on_new 'test machine dep', 'e1-test1-001.mgmt.lon.net.local'
        each_machine do |machine|
          machine.depends_on_new 'test machine dep', 'e1-test1-001.mgmt.lon.net.local'
        end
      end
    end

    env 'e1', :primary_site => 'lon' do
      instantiate_stack 'standard'
    end
  end

  machine_set('test2') do |machine_set|
    expect(machine_set.dependencies.size).to be(1)
    dep = machine_set.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
    expect(dep.environment_name).to eq('e1')
    expect {
      machine_set.resolve_dependencies
    }.to raise_error "Duplicate dependency: test2 has dependency 'test machine dep' on service 'e1-test1-001.mgmt.lon.net.local' in environment 'e1' that is also defined by one of its associated machines 'e1-test2-001.mgmt.lon.net.local'"
  end

  host('e1-test2-001.mgmt.lon.net.local') do |host|
    expect(host.dependencies.size).to be(1)
    dep = host.virtual_service.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
    expect(dep.environment_name).to eq('e1')
    expect(host.virtual_service.dependencies.size).to be(1)
    dep = host.virtual_service.dependencies.first
    expect(dep.dependable_name).to eq('test machine dep')
    expect(dep.service_name).to eq('e1-test1-001.mgmt.lon.net.local')
    expect(dep.environment_name).to eq('e1')
    expect {
      host.resolve_dependencies
    }.to raise_error "Duplicate dependency: e1-test2-001.mgmt.lon.net.local has dependency 'test machine dep' on service 'e1-test1-001.mgmt.lon.net.local' in environment 'e1' that is also defined by machine_set test2"
  end
end
