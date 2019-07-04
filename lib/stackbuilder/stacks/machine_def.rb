require 'stackbuilder/support/owner_fact'
require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/services/traits/namespace'

class Stacks::MachineDef
  include Stacks::Services::Traits::LogstashReceiverDependent

  attr_reader :domain
  attr_reader :environment
  attr_reader :fabric
  attr_reader :hostname
  attr_reader :base_hostname
  attr_reader :virtual_service
  attr_reader :location
  attr_reader :ram
  attr_reader :lsbdistcodename
  attr_accessor :index
  attr_accessor :availability_group
  attr_accessor :fabric
  attr_accessor :networks
  attr_accessor :storage
  attr_accessor :vcpus
  attr_accessor :allocation_tags
  attr_accessor :machine_allocation_tags
  attr_accessor :destroyable
  attr_accessor :role
  attr_accessor :site
  attr_accessor :monitoring
  attr_accessor :monitoring_in_enc
  attr_accessor :monitoring_options
  attr_accessor :maintainer
  attr_accessor :spectre_patches

  def initialize(virtual_service, base_hostname, environment, site, role = nil)
    @virtual_service = virtual_service
    @base_hostname = base_hostname
    @networks = [:mgmt, :prod]
    @site = site
    @role = role
    @location = environment.translate_site_symbol(site)
    @availability_group = nil
    @ram = "2097152"
    @vcpus = 1
    @storage = {
      '/'.to_sym =>  {
        :type        => 'os',
        :size        => '5G',
        :prepare     => {
          :method => 'image',
          :options => {
            :path => '/var/local/images/ubuntu-trusty.img'
          }
        }
      }
    }
    @maintainer = nil
    @monitoring = true
    @monitoring_options = {
      'nagios_host_template'    => 'non-prod-host',
      'nagios_service_template' => 'non-prod-service'
    }
    @monitoring = @virtual_service.monitoring if @virtual_service.respond_to?(:monitoring)
    @monitoring_options = @virtual_service.monitoring_options if @virtual_service.respond_to?(:monitoring_options)
    @monitoring_in_enc = false # temporary feature flag
    @monitoring_in_enc = @virtual_service.monitoring_in_enc if @virtual_service.respond_to?(:monitoring_in_enc)
    @spectre_patches = nil

    @destroyable = true
    @dont_start = false
    @routes = []
    @included_classes = {}
    @added_cnames = {}
    @allocation_tags = []
    @lsbdistcodename = 'trusty'
    validate_name
  end

  def validate_name
    return if /^[-a-zA-Z0-9]+$/.match(@base_hostname)
    fail "illegal hostname: \"#{@base_hostname}\". hostnames can only contain letters, digits and hyphens"
  end

  def validate_storage
    @storage.each do |mount, values|
      [:type, :size].each do |attribute|
        fail "Mount point #{mount} on #{hostname} must specify a #{attribute.to_sym} attribute. #{@storage}" unless values.key?(attribute)
      end
    end
  end

  def include_class(class_name, class_hash = {})
    @included_classes[class_name] = class_hash
  end

  def add_cname(network = :mgmt, cname = "")
    @added_cnames[network] = [] if @added_cnames[network].nil?
    @added_cnames[network] = @added_cnames[network].push(cname)
  end

  def use_trusty
    fail "\n#{@environment.name}-#{@base_hostname}:\n  machine.use_trusty is no longer used.\n  Please use machine.template(:trusty) instead.\n"
  end

  def template(lsbdistcodename)
    fail "Unknown template #{lsbdistcodename}" unless [:trusty, :precise, :bionic].include? lsbdistcodename
    @lsbdistcodename = lsbdistcodename.to_s
    case lsbdistcodename
    when :precise
      @storage[:/][:prepare][:options][:path] = "/var/local/images/gold-#{@lsbdistcodename}/generic.img"
    else
      @storage[:/][:prepare][:options][:path] = "/var/local/images/ubuntu-#{@lsbdistcodename}.img"
    end
  end

  def needs_signing?
    true
  end

  def destroyable?
    @destroyable
  end

  def needs_poll_signing?
    true
  end

  def allow_destroy(destroyable = true)
    @destroyable = destroyable
  end

  def bind_to(environment)
    @environment = environment
    @fabric = environment.options[@location]
    case @fabric
    when 'local'
      @hostname  = "#{@environment.name}-#{@base_hostname}-#{OwnerFact.owner_fact}"
    else
      @hostname = "#{@environment.name}-#{@base_hostname}"
    end
    @domain = environment.domain(@fabric)
    @routes.concat(@environment.routes[@fabric]) unless @environment.routes.nil? || !@environment.routes.key?(@fabric)

    @allocation_tags = @environment.allocation_tags[@fabric] if !@environment.allocation_tags.nil? &&
                                                                @environment.allocation_tags.key?(fabric) &&
                                                                !@environment.allocation_tags[$fabric].nil?
  end

  def accept(&block)
    block.call(self)
  end

  def flatten
    [self]
  end

  def name
    hostname
  end

  def modify_storage(storage_modifications)
    storage_modifications.each do |mount_point, values|
      if @storage[mount_point.to_sym].nil?
        @storage[mount_point.to_sym] = values
      else
        @storage[mount_point.to_sym] = recurse_merge(@storage[mount_point.to_sym], values)
      end
    end
  end

  def ram=(value)
    str = value.to_s
    @ram = str.end_with?('G') ? (str.chomp('G').to_i * 1024 * 1024).to_s : str
  end

  def add_network(net)
    @networks << net unless @networks.include? net
  end

  def remove_network(net)
    @networks.delete net
  end

  def recurse_merge(a, b)
    a.merge(b) do |_, x, y|
      (x.is_a?(Hash) && y.is_a?(Hash)) ? recurse_merge(x, y) : y
    end
  end

  def recurse_merge!(a, b)
    a.merge!(b) do |_, x, y|
      (x.is_a?(Hash) && y.is_a?(Hash)) ? recurse_merge(x, y) : y
    end
  end

  def add_route(route_name)
    @routes << route_name unless @routes.include? route_name
  end

  def remove_route(route_name)
    @routes.delete route_name
  end

  def dont_start
    @dont_start = true
  end

  def to_spec
    validate_storage
    @destroyable = true if environment.every_machine_destroyable?

    spec = {
      :hostname                => @hostname,
      :domain                  => @domain,
      :fabric                  => @fabric,
      :logicalenv              => @environment.name,
      :availability_group      => availability_group,
      :networks                => @networks,
      :qualified_hostnames     => Hash[@networks.map { |network| [network, qualified_hostname(network)] }]
    }

    spec[:disallow_destroy] = true unless @destroyable
    spec[:ram] = ram unless ram.nil?
    spec[:vcpus] = vcpus unless vcpus.nil?
    spec[:storage] = @environment.options[:create_persistent_storage] ? turn_on_persistent_storage_creation(storage) : storage
    spec[:dont_start] = true if @dont_start
    spec[:cnames] = Hash[@added_cnames.map { |n, cnames| [n, Hash[cnames.map { |c| [c, qualified_hostname(n)] }]] }]
    spec[:allocation_tags] = @allocation_tags

    spec[:spectre_patches] = @spectre_patches if @spectre_patches

    spec
  end

  def turn_on_persistent_storage_creation(storage)
    Hash[storage.map do |mount_point, values|
      if values[:persistent]
        [mount_point, values.merge(:persistence_options => { :on_storage_not_found => 'create_new' })]
      else
        [mount_point, values]
      end
    end]
  end

  # XXX DEPRECATED for flatten / accept interface, remove me!
  def to_specs
    [to_spec]
  end

  def type_of?
    :machine_def
  end

  def identity
    mgmt_fqdn.to_sym
  end

  def to_enc
    enc = { 'server' => nil }

    if @spectre_patches
      enc['server'] = {
        'spectre_patches' => @spectre_patches
      }
    end

    enc.merge!(filebeat_profile_enc)

    if @monitoring_in_enc
      enc['monitoring'] = {
        'checks'     => @monitoring,
        'options'    => @monitoring_options
      }
      enc['monitoring']['maintainer'] = @maintainer unless @maintainer.nil?
    end
    enc.merge! @included_classes unless @included_classes.nil?
    enc.merge! @virtual_service.included_classes if @virtual_service && @virtual_service.respond_to?(:included_classes)
    unless @routes.empty?
      enc['routes'] = {
        'to' => @routes
      }
    end
    enc
  end

  def qualified_hostname(network)
    fail "no such network '#{network}'" unless @networks.include?(network)
    if network.eql?(:prod)
      return "#{@hostname}.#{@domain}"
    else
      return "#{@hostname}.#{network}.#{@domain}"
    end
  end

  def prod_fqdn
    qualified_hostname(:prod)
  end

  def mgmt_fqdn
    qualified_hostname(:mgmt)
  end

  def clazz
    "machine"
  end

  def dependency_nodes
    virtual_service.virtual_services_that_i_depend_on.map(&:children).flatten
  end

  def should_prepare_dependency?
    true
  end

  def to_k8s(app_deployer)
    app_name = @virtual_service.application.downcase

    [{
      'apiVersion' => 'apps/v1',
      'kind' => 'Deployment',
      'metadata' => {
        'name' => app_name
      },
      'spec' => {
        'selector' => {
          'matchLabels' => {
            'app' => app_name
          }
        },
        'strategy' => {
          'type' => 'RollingUpdate',
          'rollingUpdate' => { # these settings allow one instance to be taken down and no extras to be created, this replicates orc
            'maxUnavailable' => 1,
            'maxSurge' => 0
          }
        },
        'replicas' => @virtual_service.instances,
        'template' => {
          'metadata' => {
            'labels' => {
              'app' => app_name
            }
          },
          'spec' => {
            'containers' => [{
              'image' => "repo.net.local:8080/#{app_name}:#{app_deployer.query_cmdb_for(:application => @virtual_service.application,
                                                                                        :environment => @environment.name,
                                                                                        :group => @group)[:target_version]}",
              'name' => app_name,
              'args' => [
                'java',
                '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5000',
                '-jar /app/app.jar',
                'config.properties'
              ],
              'ports' => [{
                'containerPort' => 8000,
                'name' => app_name
              }],
              'volumeMounts' => [{
                'name' => 'config-volume',
                'mountPath' => '/app/config.properties',
                'subPath' => 'config.properties'
              }],
              'readinessProbe' => {
                'periodSeconds' => 2,
                'httpGet' => {
                  'path' => '/info/health',
                  'port' => 8000
                }
              }
            }],
            'volumes' => [{
              'name' => 'config-volume',
              'configMap' => {
                'name' => app_name + '-config'
              }
            }]
          }
        }
      }
    },
     {
       'apiVersion' => 'v1',
       'kind' => 'Service',
       'metadata' => {
         'name' => app_name
       },
       'spec' => {
         'type' => 'LoadBalancer',
         'selector' => {
           'app' => app_name
         },
         'ports' => [{
           'name' => 'app',
           'protocol' => 'TCP',
           'port' => 8000,
           'targetPort' => 8000
         }]
       }
     },
     {
       'apiVersion' => 'v1',
       'kind' => 'ConfigMap',
       'metadata' => {
         'name' => app_name + '-config'
       },
       'data' => {
         'config.properties' => <<EOC
port=8000
log.directory=/var/log/#{@virtual_service.application}/#{@environment.name}-#{@virtual_service.application}-#{@group}
log.tags=["env:#{@environment.name}", "app:#{@virtual_service.application}", "instance:#{@group}"]

graphite.enabled=true
graphite.host=#{@site}-mon-001.mgmt.#{@site}.net.local
graphite.port=2013
graphite.prefix=#{app_name}.k8s_#{@environment.name}_#{@site}
graphite.period=10
EOC
       }
     }]
  end
end
