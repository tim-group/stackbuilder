require 'stackbuilder/stacks/factory'

describe Stacks::MachineDef do
  def new_environment(name, options)
    Stacks::Environment.new(name, options, nil, {}, {}, Stacks::CalculatedDependenciesCache.new)
  end

  it 'produces x.net.local for the prod network' do
    env = new_environment('env', :primary_site => 'st')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'st')
    machinedef.bind_to(env)
    expect(machinedef.prod_fqdn).to eql('env-test.st.net.local')
  end

  it 'should be destroyable by default' do
    env = new_environment('noenv', :primary_site => 'local')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'local')
    machinedef.bind_to(env)
    expect(machinedef.destroyable?).to eql true
    expect(machinedef.to_spec[:disallow_destroy]).to eql nil
  end

  it 'should allow destroyable to be overriden' do
    env = new_environment('noenv', :primary_site => 'local')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'local')
    machinedef.bind_to(env)
    machinedef.allow_destroy(false)
    expect(machinedef.destroyable?).to eql false
    expect(machinedef.to_spec[:disallow_destroy]).to eql true
  end

  it 'should allow environment to override destroyable' do
    env_opts = {
      :primary_site => 'local',
      :every_machine_destroyable => true
    }
    env = new_environment('noenv', env_opts)
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'local')
    machinedef.bind_to(env)
    machinedef.allow_destroy(false)
    expect(machinedef.destroyable?).to eql false
    expect(machinedef.to_spec[:disallow_destroy]).to eql nil
  end

  it 'populates routes in the enc if routes are added' do
    env = new_environment('noenv', :primary_site => 'local')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'local')
    machinedef.add_route('mgmt_pg')
    machinedef.bind_to(env)
    expect(machinedef.to_enc['routes']['to']).to include 'mgmt_pg'
  end

  it 'allows cnames to be added' do
    env = new_environment('env', :primary_site => 'ps')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'ps')
    machinedef.add_cname(:mgmt, 'foo')
    machinedef.add_cname(:mgmt, 'bar')
    machinedef.add_cname(:prod, 'baz')
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
    env = new_environment('env', :primary_site => 'oy')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'oy')
    env.add_route('oy', 'mgmt_foo')
    machinedef.bind_to(env)
    expect(machinedef.to_enc['routes']['to'].size).to eql(1)
    expect(machinedef.to_enc['routes']['to']).to include('mgmt_foo')
  end

  it 'should validate storage' do
    env = new_environment('foo', :primary_site => 'oy')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'oy')
    storage_without_type = {
      '/home'.to_sym => { :size => '100G' }
    }
    machinedef.bind_to(env)
    machinedef.modify_storage(storage_without_type)
    expect { machinedef.to_spec }.to raise_error(RuntimeError, /Mount point \/home on foo-test must specify a type attribute/)

    machinedef = Stacks::MachineDef.new(self, 'test', env, 'oy')
    storage_without_type = {
      '/home'.to_sym => { :type => 'os' }
    }
    machinedef.bind_to(env)
    machinedef.modify_storage(storage_without_type)
    expect { machinedef.to_spec }.to raise_error(RuntimeError, /Mount point \/home on foo-test must specify a size attribute/)
  end

  it 'should configure gold image and allocation tag when instructed to use trusty - old way' do
    env = new_environment('noenv', :primary_site => 'st')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'st')
    machinedef.bind_to(env)
    expect { machinedef.use_trusty }.to raise_error(RuntimeError, /machine.use_trusty is no longer used/)
  end

  it 'should configure gold image and allocation tag when instructed to use trusty' do
    env = new_environment('noenv', :primary_site => 'st')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'st')
    machinedef.template(:trusty)
    machinedef.bind_to(env)
    expect(machinedef.to_spec[:storage][:/][:prepare][:options][:path]).to eql('/var/local/images/ubuntu-trusty.img')
  end

  it 'should configure gold image and allocation tag when instructed to use ubuntu_precise' do
    env = new_environment('noenv', :primary_site => 'st')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'st')
    machinedef.template(:precise)
    machinedef.bind_to(env)
    expect(machinedef.to_spec[:storage][:/][:prepare][:options][:path]).to include('gold-precise/generic.img')
    expect(machinedef.to_spec[:storage][:/][:prepare][:options][:path]).to eql('/var/local/images/gold-precise/generic.img')
  end

  it 'should turn on persistent storage allocation when the environment requests it' do
    env = new_environment('noenv', :primary_site => 'st', :create_persistent_storage => true)
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'st')
    machinedef.template(:precise)
    machinedef.modify_storage(
      '/mnt/data' => {
        :persistent => true,
        :type => 'data',
        :size => '1G' })
    machinedef.bind_to(env)
    expect(machinedef.to_spec[:storage]['/mnt/data'.to_sym][:persistence_options][:on_storage_not_found]).to eql('create_new')

    expect(machinedef.to_spec[:storage]['/'.to_sym][:persistence_options]).to be(nil)
  end

  it 'should turn on persistent storage allocation when requested' do
    env = new_environment('noenv', :primary_site => 'st', :create_persistent_storage => false)
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'st')
    machinedef.template(:precise)
    machinedef.modify_storage(
        '/mnt/data' => {
            :persistent => true,
            :type => 'data',
            :size => '1G' })
    machinedef.bind_to(env)
    expect(machinedef.to_spec(true)[:storage]['/mnt/data'.to_sym][:persistence_options][:on_storage_not_found]).to eql('create_new')

    expect(machinedef.to_spec(true)[:storage]['/'.to_sym][:persistence_options]).to be(nil)
  end

  it 'should allow monitoring to be configured' do
    env = new_environment('noenv', :primary_site => 'st')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'st')
    machinedef.monitoring_in_enc = true
    machinedef.monitoring = false
    machinedef.bind_to(env)
    expect(machinedef.to_enc).to have_key('monitoring')
    expect(machinedef.to_enc['monitoring']).to have_key('checks')
    expect(machinedef.to_enc['monitoring']['checks']).to eql(false)
    expect(machinedef.to_enc['monitoring']).to have_key('options')
    expect(machinedef.to_enc['monitoring']['options']).to have_key('nagios_host_template')
    expect(machinedef.to_enc['monitoring']['options']['nagios_host_template']).to eql('non-prod-host')
    expect(machinedef.to_enc['monitoring']['options']).to have_key('nagios_service_template')
    expect(machinedef.to_enc['monitoring']['options']['nagios_service_template']).to eql('non-prod-service')
  end

  it 'should allow monitoring to be configured' do
    env = new_environment('noenv', :primary_site => 'st')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'st')
    machinedef.monitoring_in_enc = true
    machinedef.maintainer = 'datalibre'
    machinedef.bind_to(env)
    expect(machinedef.to_enc).to have_key('monitoring')
    expect(machinedef.to_enc['monitoring']).to have_key('maintainer')
    expect(machinedef.to_enc['monitoring']['maintainer']).to eql('datalibre')
  end

  it 'should allow ram to be specified in GiB' do
    env = new_environment('env', :primary_site => 'st')
    machinedef = Stacks::MachineDef.new(self, 'test', env, 'st')
    machinedef.bind_to(env)

    machinedef.ram = "13423"
    expect(machinedef.ram).to eql('13423')

    machinedef.ram = '10G'
    expect(machinedef.ram).to eql('10485760')
  end
end
