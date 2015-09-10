require 'stackbuilder/stacks/factory'

describe Stacks::MachineDef do
  it 'produces x.net.local for the prod network' do
    machinedef = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("env", { :primary_site => "st" }, nil, {}, {})
    machinedef.bind_to(env)
    expect(machinedef.prod_fqdn).to eql("env-test.st.net.local")
  end

  it 'should be destroyable by default' do
    machinedef = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("noenv", { :primary_site => "local" }, nil, {}, {})
    machinedef.bind_to(env)
    expect(machinedef.destroyable?).to eql true
    expect(machinedef.to_spec[:disallow_destroy]).to eql nil
  end

  it 'should allow destroyable to be overriden' do
    machinedef = Stacks::MachineDef.new("test")
    env = Stacks::Environment.new("noenv", { :primary_site => "local" }, nil, {}, {})
    machinedef.bind_to(env)
    machinedef.allow_destroy(false)
    expect(machinedef.destroyable?).to eql false
    expect(machinedef.to_spec[:disallow_destroy]).to eql true
  end

  it 'should allow environment to override destroyable' do
    machinedef = Stacks::MachineDef.new("test")
    env_opts = {
      :primary_site => "local",
      :every_machine_destroyable => true
    }
    env = Stacks::Environment.new("noenv", env_opts, nil, {}, {})
    machinedef.bind_to(env)
    machinedef.allow_destroy(false)
    expect(machinedef.destroyable?).to eql false
    expect(machinedef.to_spec[:disallow_destroy]).to eql nil
  end

  it 'should disable persistent if the environment does not support it' do
    machinedef = Stacks::MachineDef.new("test")
    machinedef.modify_storage('/'.to_sym         => { :persistent => true },
                              '/mnt/data'.to_sym => { :persistent => true })
    env_opts = {
      :primary_site                 => "local",
      :persistent_storage_supported => false
    }
    env = Stacks::Environment.new("noenv", env_opts, nil, {}, {})
    machinedef.bind_to(env)
    expect(machinedef.to_spec[:storage]['/'.to_sym][:persistent]).to eql false
    expect(machinedef.to_spec[:storage]['/mnt/data'.to_sym][:persistent]).to eql false
  end

  it 'populates routes in the enc if routes are added' do
    machinedef = Stacks::MachineDef.new("test")
    machinedef.add_route('mgmt_pg')
    env = Stacks::Environment.new("noenv", { :primary_site => "local" }, nil, {}, {})
    machinedef.bind_to(env)
    expect(machinedef.to_enc).to eql('routes' => { 'to' => ['mgmt_pg'] })
  end

  it 'allows cnames to be added' do
    machinedef = Stacks::MachineDef.new("test")
    machinedef.add_cname(:mgmt, 'foo')
    machinedef.add_cname(:mgmt, 'bar')
    machinedef.add_cname(:prod, 'baz')

    env = Stacks::Environment.new("env", { :primary_site => "ps" }, nil, {}, {})
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
end
