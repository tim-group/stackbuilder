require 'set'

module InfraSST 
  class Environment
    attr_accessor :registry 
    attr_reader :name
    attr_accessor :stack_templates
    attr_accessor :domain

    def initialize(name, parent=nil)
      @name = name
      @parent = parent
      @domain = "dev.net.local"
      @stacks = {}
      @registry = {}
      @sub_environments = {}
    end

    def stack(name, &block)
      if (stack_templates[name])
        stack = stack_templates[name].call()
      else
        stack = Stack.new(name)
      end
      stack.instance_eval(&block) unless block.nil?
      @stacks[name] = stack
      return stack
    end

    def generate()
      @stacks.values.each do |stack|
        stack.generate(self)
      end
      @sub_environments.values.each do |env|
        env.generate()
      end
    end
   
    def collapse_registries
      registry = self.registry
      @sub_environments.values.each do |env| 
        registry = registry.merge(env.registry)
     end
      registry = registry.reject do |k,v| v.kind_of?(VirtualService) end
      return registry
    end
 
    def lookup(ident)
      raise "unable to find object with ident #{ident}" unless registry[ident]
      return registry[ident]
    end
 
    def env(name, &block)
      @sub_environments[name] = env = Environment.new(name, self)
      env.stack_templates = self.stack_templates
      env.instance_eval(&block)
      return env
    end

  end

  class MachineDef
    attr_accessor :domain
  end

  class Server  < MachineDef
    attr_reader :name
    attr_reader :server_type
    attr_reader :application_name
    attr_reader :environment_name
    attr_accessor :dependencies

    def initialize(name, application_name,environment_name, type)
      @name = name
      @application_name = application_name
      @environment_name = environment_name
      @server_type = type
    end

    def to_enc
      flattened_dependencies = {}
      dependencies.map do |dependency| 
        flattened_dependencies[dependency.name] = dependency.url 
      end if not dependencies.nil?
 
      return {
        :enc=>{
	  :classes=>{
            :base=>nil,
            self.server_type=>{
              :environment=>self.environment_name,
              :application=>self.application_name,
              :dependencies=>flattened_dependencies
            }
	  }
	}
      }
    end
  end

  class VirtualService
    attr_accessor :domain
    attr_reader :env
    attr_reader :name

    def initialize(name, env)
      @name = name
      @env = env
    end
 
    def url()
      return "#{env}-#{name}-vip.#{domain}"
    end
  end

  class LoadBalancer < MachineDef
    attr_reader :name
    def initialize(name)
      @name = name
    end
    def to_enc
      return {
        :enc=>{
	  :classes=>{
            :base=>nil,
            :loadbalancer=>nil
	  }
	}
      }
    end
  end

  class Stack
     attr_reader :name
    def initialize(name)
      @name = name
      @loadbalancers = []
      @definitions = []
    end
   
    def virtualservice(name, options={:type=>:appserver}, &block)
      @definitions << virtualservicedefinition = VirtualServiceDefinition.new(name,options)

      virtualservicedefinition.instance_eval(&block) if block != nil
      return virtualservicedefinition
    end

    def loadbalancer(name, &block)
      @definitions << loadbalancerdefinition = LoadBalancerDefinition.new(name)
      loadbalancerdefinition.instance_eval(&block) if block != nil
      return loadbalancerdefinition
    end

    def generate(env)
      @definitions.each do |definition|
        definition.generate(env)
      end
    end 
  end

  class LoadBalancerDefinition
    attr_reader :name
    def initialize(name)
      @name = name
      @times = 2
    end

    def generate(env)
      @times.times do |i|
        name = sprintf("%s-%s-%03d", env.name, self.name, i+1) 
        env.registry[name] = LoadBalancer.new(name)
      end
    end
  end


  class VirtualServiceDefinition
    attr_reader :name
    attr_accessor :times
    attr_reader :options
    attr_accessor :dependencies

    def initialize(name, options)
      @name = name
      @options = options
      @times = 2
    end
    
    def generate(env)
      env.registry[self.name] = VirtualService.new(self.name, env.name)
      env.registry[self.name].domain=env.domain
      @times.times do |i|
        appservername = sprintf("%s-%s-%03d", env.name, self.name, i+1) 
        appserver = env.registry[appservername] = Server.new(appservername,self.name, env.name, self.options[:type])

       if (not dependencies.nil?)
          resolved_dependencies = dependencies.map do |dependency| env.lookup(dependency) end
          appserver.dependencies = resolved_dependencies
        end
      end
    end
  end

  attr_accessor :stack_templates
  def self.extended(object)
    object.stack_templates = {}
  end

  def env(name,&block)
    env =  Environment.new(name) 
    env.stack_templates = self.stack_templates
    env.instance_eval(&block)
    return env
  end

  def stack(name, &block)
    stack_templates[name] = lambda {
      stack = Stack.new(name)
      stack.instance_eval(&block)
      stack 
    }
  end

end

describe "ENC::DSL" do

  it 'generates an entry for the full stack of boxes' do
    extend InfraSST
    env = env "blah" do
      stack "appx" do
        loadbalancer "lb"
        virtualservice "appx" 
        virtualservice "dbx"
      end
    end

    env.generate()

    Set.new(env.collapse_registries.keys).should eql(Set.new([
      "blah-lb-001",
      "blah-lb-002",
      "blah-appx-001",
      "blah-appx-002",
      "blah-dbx-001",
      "blah-dbx-002"
    ]))
  end

  it 'works with some services in different environments' do
    extend InfraSST
    env = env "a" do
      stack "infra" do 
        loadbalancer "lb" 
      end
      env "b" do 
        stack "appx" do
          virtualservice "appx", :type=>:appserver,:depends_on=>"dbx" 
          virtualservice "dbx", :type=>:dbserver
        end
      end
    end
    env.generate()
    Set.new(env.collapse_registries.keys).should eql(Set.new([
      "a-lb-001",
      "a-lb-002",
      "b-appx-001",
      "b-appx-002",
      "b-dbx-001",
      "b-dbx-002"
    ]))
 end

  it 'allows us to duplicate the same stack over multiple environments' do
    extend InfraSST
    stack "appx" do
      virtualservice "appx"
      virtualservice "dbx"
    end
 
    env = env "a" do
      stack "infra" do 
        loadbalancer "lb" 
      end
      env "b" do
        stack "appx"
      end
      env "c" do
        stack "appx"
      end
    end
    env.generate()

    Set.new(env.collapse_registries.keys).should eql(Set.new([
      "a-lb-001",
      "a-lb-002",
      "b-appx-001",
      "b-appx-002",
      "b-dbx-001",
      "b-dbx-002",
      "c-appx-001",
      "c-appx-002",
      "c-dbx-001",
      "c-dbx-002"   ]))

  end  

  it 'roles are reflected in the defined classes' do
    extend InfraSST
    stack "appx" do
      virtualservice "appx", :type=>:appserver
      virtualservice "dbx", :type=>:dbserver
    end
 
    env = env "a" do
      stack "infra" do 
        loadbalancer "lb" 
      end
      env "b" do
        stack "appx"
      end
      env "c" do
        stack "appx"
      end
    end
    env.generate()

    env.collapse_registries["a-lb-001"].to_enc.should eql({
      :enc=>{
      :classes=>{
        :base=>nil,
        :loadbalancer=>nil
      }}})

    env.collapse_registries["b-appx-001"].to_enc.should eql({
      :enc=>{
	:classes=>{
  	  :base=>nil,
          :appserver=>{
            :environment=>"b",
            :application=>"appx",
            :dependencies=>{}
	  }
      }}})

    env.collapse_registries["b-dbx-001"].to_enc.should eql({
      :enc=>{
        :classes=>{
          :base=>nil,
          :dbserver=>{
            :environment=>"b",
            :application=>"dbx",
            :dependencies=>{}
	  }
      }}})
  end
 
  it 'roles are reflected in the defined classes' do
    extend InfraSST
    stack "appx" do
      virtualservice "appx" 
      virtualservice "dbx"
    end
 
    env = env "a" do
      stack "infra" do 
        loadbalancer "lb" 
      end
      env "b" do
        stack "appx"
      end
      env "c" do
        stack "appx"
      end
    end
    env.generate()

    Set.new(env.collapse_registries.keys).should eql(Set.new([
      "a-lb-001",
      "a-lb-002",
      "b-appx-001",
      "b-appx-002",
      "b-dbx-001",
      "b-dbx-002",
      "c-appx-001",
      "c-appx-002",
      "c-dbx-001",
      "c-dbx-002"   ]))


  end

  it 'wires in the vip url of the service dependencies' do
    extend InfraSST
    env = env "a" do
      self.domain="dev.net.local"

      stack "all" do 
        loadbalancer "lb" 
        virtualservice "dbx"
        virtualservice "appx" do
          self.dependencies=["dbx"]
        end
      end
    end

    env.generate()
    env.collapse_registries["a-appx-001"].to_enc[:enc][:classes][:appserver][:dependencies].should eql({"dbx"=>"a-dbx-vip.dev.net.local"})
  end

  it 'puts domain names in as fqdn'

  it 'HA pairs are assigned to different zones' 
  def ignore
    extend InfraSST
     env = env "a" do
      stack "infra" do 
        loadbalancer "lb" 
      end
    end
    env.generate()
    env.collapse_registries["a-lb-001"].to_enc[:enc][:zone].should eql("primary.a")
    env.collapse_registries["a-lb-002"].to_enc[:enc][:zone].should eql("primary.b")
  end

  it 'crosssite db slaves should be marked with correct zone' do
  end
end
