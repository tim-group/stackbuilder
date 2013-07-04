stack 'ref' do
  virtual_proxyserver 'refproxy' do
    vhost('refapp') do
    end
    enable_nat
  end
  virtual_appserver 'refapp' do
    self.application = 'JavaHttpRef'
  end
end

stack 'merc' do
  virtual_appserver 'mercapp' do
    self.application = 'Merc'
    self.ram = "6291456"
    self.ports = [8000]
    self.port_map[8000] = 80
    enable_nat
  end
end

stack 'rabbit' do
  virtual_rabbitmqserver do
    # FIXME - this should be default in virtual_rabbitmqserver
    self.ports = [5672]
  end
end

stack 'tfunds' do
  virtual_proxyserver 'tfundsproxy' do
    vhost('tfundsapp') do
      pass "/resources" => "blondin"
    end
    enable_nat
  end

  virtual_appserver 'blondin' do
    self.groups = ['blue', 'green']
    self.application = 'Blondin'
  end

  virtual_appserver 'tfundsapp' do
    self.groups = ['blue']
    self.application = 'tfunds'
    self.ports = [8443]
    self.port_map[8443] = 8443
    enable_nat
  end
  standalone_appserver 'tfundscyclic' do
    self.groups = ['grey']
    self.application = 'tfunds'
    self.ports = [8443]
    self.instances = 1
  end
end

stack 'ideasfx' do
  virtual_proxyserver 'ideasfxproxy' do
    vhost('ideasfxapp', :server_name => 'ideasfx-latest.timgroup.com') do
    end
    enable_nat
  end
  virtual_appserver 'ideasfxapp' do
    self.application = 'ideasfx'
  end
end

stack 'loadbalancer' do
  loadbalancer
end

stack 'sftp' do
  virtual_sftpserver 'sftp' do
    enable_nat
  end
end

stack 'fabric' do
  natserver
end

stack 'jenkins' do
  ci_slave
end

# where we have more than one loadbalancer in a location, virtual_router_id is
# necessary, sorry.. otherwise keepalived doesnt work

env 'st', :primary_site=>'st', :secondary_site=>'bs' do
  instantiate_stack 'loadbalancer'
  instantiate_stack 'fabric'
  instantiate_stack 'jenkins'

  env 'staging', :primary_site=>'st', :secondary_site=>'bs', :lb_virtual_router_id=>130 do
    instantiate_stack 'loadbalancer'
    instantiate_stack 'tfunds'
    instantiate_stack 'merc'
    instantiate_stack 'rabbit'
  end

  env 'ci', :primary_site=>'st', :secondary_site=>'bs', :lb_virtual_router_id=>151 do
    instantiate_stack 'loadbalancer'
    instantiate_stack 'ref'
  end

  env 'rp', :primary_site=>'st', :secondary_site=>'st', :lb_virtual_router_id=>200 do
    instantiate_stack 'loadbalancer'
    instantiate_stack 'ref'
    #instantiate_stack 'tfunds'
  end

  env 'gr', :primary_site=>'st', :secondary_site=>'st', :lb_virtual_router_id=>202 do
  end

  env 'de',
    :primary_site=>'st',
    :secondary_site=>'st',
    :lb_virtual_router_id=>201,
    :nat_front_virtual_router_id=>222,
    :nat_prod_virtual_router_id=>225   do
    instantiate_stack 'loadbalancer'
    instantiate_stack 'tfunds'
    end

  env 'lneva',
    :primary_site=>'st',
    :secondary_site=>'st',
    :lb_virtual_router_id=>205 do
    instantiate_stack 'loadbalancer'
    instantiate_stack 'ref'
    end

  env 'wtaj', :primary_site=>'st', :secondary_site=>'bs', :lb_virtual_router_id=>206 do
    instantiate_stack 'loadbalancer'
    instantiate_stack 'ref'
  end

  env 'ag', :primary_site=>'st', :secondary_site=>'st', :lb_virtual_router_id=>207 do
    instantiate_stack 'loadbalancer'
    instantiate_stack 'ref'
  end
end
env 'shared', :primary_site=>'oy', :secondary_site=>'oy' do
  instantiate_stack 'fabric'

  env 'latest',
    'ideasfxproxy.vhost.ideasfxapp.server_name'=>'ideasfx-latest.timgroup.com' do
    instantiate_stack 'loadbalancer'
    instantiate_stack 'ideasfx'
    #      instantiate_stack 'fabric'
    instantiate_stack 'sftp'
    instantiate_stack 'tfunds'
    # instantiate_stack 'merc'
    instantiate_stack 'rabbit'
    end

  env 'mirror', :lb_virtual_router_id=>21 do
    instantiate_stack 'loadbalancer'
    instantiate_stack 'tfunds'
  end
end

env 'production',
  :primary_site=>'pg',
  :secondary_site=>'oy',
  'ideasfxproxy.vhost.ideasfxapp.server_name' => 'ideasfx.timgroup.com' do
  instantiate_stack 'loadbalancer'
  instantiate_stack 'ideasfx'
  instantiate_stack 'tfunds'
  instantiate_stack 'fabric'
  instantiate_stack 'sftp'
  instantiate_stack 'rabbit'
  end
env 'pro', :primary_site=>'pg', :secondary_site=>'oy' do
  instantiate_stack 'ref'
end

env 'dev',:primary_site=>'local', :secondary_site=>'local' do
  instantiate_stack 'loadbalancer'
  instantiate_stack 'ref'
  instantiate_stack 'tfunds'
end
