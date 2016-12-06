require 'stackbuilder/stacks/factory'

describe Stacks::MachineDef do
  def new_environment(name, options)
    Stacks::Environment.new(name, options, nil, {}, {}, Stacks::CalculatedDependenciesCache.new)
  end

  it 'produces x.net.local for the prod network' do
    machinedef = Stacks::MachineDef.new('test')
    env = new_environment('env', :primary_site => 'st')
    machinedef.bind_to(env)
    expect(machinedef.prod_fqdn).to eql('env-test.st.net.local')
  end

  it 'should be destroyable by default' do
    machinedef = Stacks::MachineDef.new('test')
    env = new_environment('noenv', :primary_site => 'local')
    machinedef.bind_to(env)
    expect(machinedef.destroyable?).to eql true
    expect(machinedef.to_spec[:disallow_destroy]).to eql nil
  end

  it 'should allow destroyable to be overriden' do
    machinedef = Stacks::MachineDef.new('test')
    env = new_environment('noenv', :primary_site => 'local')
    machinedef.bind_to(env)
    machinedef.allow_destroy(false)
    expect(machinedef.destroyable?).to eql false
    expect(machinedef.to_spec[:disallow_destroy]).to eql true
  end

  it 'should allow environment to override destroyable' do
    machinedef = Stacks::MachineDef.new('test')
    env_opts = {
      :primary_site => 'local',
      :every_machine_destroyable => true
    }
    env = new_environment('noenv', env_opts)
    machinedef.bind_to(env)
    machinedef.allow_destroy(false)
    expect(machinedef.destroyable?).to eql false
    expect(machinedef.to_spec[:disallow_destroy]).to eql nil
  end

  it 'populates routes in the enc if routes are added' do
    machinedef = Stacks::MachineDef.new('test')
    machinedef.add_route('mgmt_pg')
    env = new_environment('noenv', :primary_site => 'local')
    machinedef.bind_to(env)
    expect(machinedef.to_enc['routes']['to']).to include 'mgmt_pg'
  end

  it 'allows cnames to be added' do
    machinedef = Stacks::MachineDef.new('test')
    machinedef.add_cname(:mgmt, 'foo')
    machinedef.add_cname(:mgmt, 'bar')
    machinedef.add_cname(:prod, 'baz')

    env = new_environment('env', :primary_site => 'ps')
    machinedef.bind_to(env)

    expect(machinedef.to_specs.shift[:cnames]).to eql(
      :mgmt => {
        'foo' => 'env-test.mgmt.ps.net.local',
        'bar' => 'env-test.mgmt.ps.net.local'
      },
      :prod => {
        'baz' => 'env-test.ps.net.local'
      }
    )
  end

  it 'should support adding routes to a machine' do
    machinedef = Stacks::MachineDef.new('test')
    env = new_environment('env', :primary_site => 'oy')
    env.add_route('oy', 'mgmt_foo')
    machinedef.bind_to(env)
    expect(machinedef.to_enc['routes']['to'].size).to eql(1)
    expect(machinedef.to_enc['routes']['to']).to include('mgmt_foo')
  end

  it 'should validate storage' do
    env = new_environment('foo', :primary_site => 'oy')
    machinedef = Stacks::MachineDef.new('test')
    storage_without_type = {
      '/home'.to_sym => { :size => '100G' }
    }
    machinedef.bind_to(env)
    machinedef.modify_storage(storage_without_type)
    expect { machinedef.to_spec }.to raise_error(RuntimeError, /Mount point \/home on foo-test must specify a type attribute/)

    machinedef = Stacks::MachineDef.new('test')
    storage_without_type = {
      '/home'.to_sym => { :type => 'os' }
    }
    machinedef.bind_to(env)
    machinedef.modify_storage(storage_without_type)
    expect { machinedef.to_spec }.to raise_error(RuntimeError, /Mount point \/home on foo-test must specify a size attribute/)
  end

  it 'should configure gold image and allocation tag when instructed to use trusty' do
    machinedef = Stacks::MachineDef.new('test')
    machinedef.use_trusty

    env = new_environment('noenv', :primary_site => 'st')
    env.set_allocation_tags('st', %w(trusty precise))
    machinedef.bind_to(env)

    expect(machinedef.to_spec[:storage][:/][:prepare][:options][:path]).to include('ubuntu-trusty')
  end
end
