require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/cmd'
require 'stackbuilder/support/subscription'
require 'stacks/test_framework'
require 'test_classes'
require 'spec_helper'

describe 'cmd' do
  before :each do
    @core_actions = double('core_actions')
    @dns = double('dns')
    @nagios = double('nagios')
    @subscription = double('subscription')
    @puppet = double('puppet')
    @app_deployer = double('app_deployer')
    @dns_resolver = double('dns_resolver')
    @hiera_provider = TestHieraProvider.new({})
    @cleaner = double('cleaner')
    @open3 = double('Open3')
    stub_const("Open3", @open3)
    @launch_action = double("launch_action")
    @return_status = double('return_status')
  end

  def cmd(factory, env_name, stack_selector)
    CMD.new(factory, @core_actions, @dns, @nagios, @subscription, @puppet, @app_deployer, @dns_resolver, @hiera_provider, @cleaner,
            env_name.nil? ? nil : factory.inventory.find_environment(env_name),
            stack_selector)
  end

  # using this instead of the rspec output() matcher to limit the number of times we have to run things.
  # If we used the output matcher the command needs to be run for the positive and negative assertions of a test,
  # which doubles the runtime of the tests.
  def capture_stdout(&block)
    out = StringIO.new
    old_stdout = $stdout
    $stdout = out

    block.call

    $stdout = old_stdout
    out.string
  end

  let(:factory) do
    eval_stacks do
      stack "mystack" do
        app_service "myappservice" do
          self.application = 'MyApplication'
          self.instances = 2
        end
        app_service "myrelatedappservice" do
          self.application = 'MyRelatedApplication'
          self.instances = 1
        end
      end
      stack "myotherstack" do
        app_service "myotherappservice" do
          self.application = 'MyOtherApplication'
        end
      end
      stack "myk8sstack" do
        app_service "myk8sappservice", :kubernetes => true do
          self.maintainers = [person('Testers')]
          self.description = 'Testing'

          self.application = 'MyK8sApplication'
          self.instances = 2
        end
        app_service "myrelatedk8sappservice", :kubernetes => true do
          self.maintainers = [person('Testers')]
          self.description = 'Testing'

          self.application = 'MyRelatedK8sApplication'
          self.instances = 1
        end
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "mystack"
        instantiate_stack "myk8sstack"
      end
      env 'e2', :primary_site => 'space' do
        instantiate_stack "myotherstack"
      end
    end
  end

  describe 'provision command' do
    describe 'for k8s' do
      it 'provisions a stack' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        myk8sappservice_machineset = have_attributes(:name => 'myk8sappservice')
        myrelatedk8sappservice_machineset = have_attributes(:name => 'myrelatedk8sappservice')

        cmd = cmd(factory, 'e1', 'myk8sstack')

        expect(@dns).to receive(:do_allocate_vips).with(myk8sappservice_machineset)
        expect(@puppet).to receive(:do_puppet_run_on_dependencies).with(myk8sappservice_machineset)

        expect(@dns).to receive(:do_allocate_vips).with(myrelatedk8sappservice_machineset)
        expect(@puppet).to receive(:do_puppet_run_on_dependencies).with(myrelatedk8sappservice_machineset)

        mco = double('mcollective client')
        expect(mco).to receive(:insert).with(any_args).and_return([]).twice

        expect(cmd).to receive(:mco_client).with('k8ssecret', :fabric => 'space').twice do |*_args, &block|
          block.call(mco)
        end

        expect(@open3).to receive(:capture3).
          with('kubectl',
               'apply',
               '--context',
               'space',
               '--prune',
               '-l',
               'stack=myk8sstack,machineset=myk8sappservice',
               '-f',
               '-',
               :stdin_data => match(/^---\s*$.*
                                     \bkind:\s*Service.*
                                     \bkind:\s*Deployment.*
                                     /mx)).
          and_return(['Some stdout output', 'Some stderr output', @return_status])
        expect(@return_status).to receive(:success?).and_return(true)

        expect(@open3).to receive(:capture3).
          with('kubectl',
               'apply',
               '--context',
               'space',
               '--prune',
               '-l',
               'stack=myk8sstack,machineset=myrelatedk8sappservice',
               '-f',
               '-',
               :stdin_data => match(/^---\s*$.*
                                     \bkind:\s*Service.*
                                     \bkind:\s*Deployment.*
                                     /mx)).
          and_return(['Some stdout output', 'Some stderr output', @return_status])
        expect(@return_status).to receive(:success?).and_return(true)

        cmd.provision nil
      end
    end

    describe 'for VMs' do
      def makes_calls_to_provision(machineset_matcher)
        successful_response = Subscription::WaitResponse.new([], [])

        expect(@core_actions).to receive(:get_action).with("launch").and_return(@launch_action)
        expect(@dns).to receive(:do_allocate_vips).with(machineset_matcher)
        expect(@dns).to receive(:do_allocate_ips).with(machineset_matcher)
        expect(@puppet).to receive(:do_puppet_run_on_dependencies).with(machineset_matcher)
        expect(@launch_action).to receive(:call).with(factory.services, machineset_matcher)
        expect(@puppet).to receive(:puppet_wait_for_autosign).with(machineset_matcher).and_return(successful_response)
        expect(@puppet).to receive(:puppet_wait_for_run_completion).with(machineset_matcher).and_return(successful_response)
        expect(@app_deployer).to receive(:deploy_applications).with(machineset_matcher)
        expect(@nagios).to receive(:nagios_schedule_uptime).with(machineset_matcher)
        expect(@nagios).to receive(:do_nagios_register_new).with(machineset_matcher)
      end

      it 'provisions a stack' do
        myappservice_machineset = have_attributes(:name => 'myappservice')
        myrelatedappservice_machineset = have_attributes(:name => 'myrelatedappservice')

        makes_calls_to_provision(myappservice_machineset)
        makes_calls_to_provision(myrelatedappservice_machineset)

        cmd = cmd(factory, 'e1', 'mystack')

        cmd.provision nil
      end

      it 'provisions a specific machineset' do
        machineset = have_attributes(:name => 'myappservice')
        makes_calls_to_provision(machineset)

        cmd = cmd(factory, 'e1', 'myappservice')

        cmd.provision nil
      end

      it 'provisions a specific VM' do
        the_thing = have_attributes(:mgmt_fqdn => 'e1-myappservice-001.mgmt.space.net.local')
        makes_calls_to_provision(the_thing)

        cmd = cmd(factory, 'e1', 'e1-myappservice-001.mgmt.space.net.local')

        cmd.provision nil
      end
    end
  end

  describe 'reprovision command' do
    describe 'for k8s' do
      it 'reprovisions a stack' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        cmd = cmd(factory, 'e1', 'myk8sstack')

        mco = double('mcollective client')
        expect(mco).to receive(:insert).with(any_args).and_return([]).twice

        expect(cmd).to receive(:mco_client).with('k8ssecret', :fabric => 'space').twice do |*_args, &block|
          block.call(mco)
        end

        expect(@open3).to receive(:capture3).
          with('kubectl',
               'apply',
               '--context',
               'space',
               '--prune',
               '-l',
               'stack=myk8sstack,machineset=myk8sappservice',
               '-f',
               '-',
               :stdin_data => match(/^---\s*$.*
                                     \bkind:\s*Service.*
                                     \bkind:\s*Deployment.*
                                     /mx)).
          and_return(['Some stdout output', 'Some stderr output', @return_status])
        expect(@return_status).to receive(:success?).and_return(true)

        expect(@open3).to receive(:capture3).
          with('kubectl',
               'apply',
               '--context',
               'space',
               '--prune',
               '-l',
               'stack=myk8sstack,machineset=myrelatedk8sappservice',
               '-f',
               '-',
               :stdin_data => match(/^---\s*$.*
                                     \bkind:\s*Service.*
                                     \bkind:\s*Deployment.*
                                     /mx)).
          and_return(['Some stdout output', 'Some stderr output', @return_status])
        expect(@return_status).to receive(:success?).and_return(true)

        cmd.reprovision nil
      end

      it 'reprovisions a machineset' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        cmd = cmd(factory, 'e1', 'myk8sappservice')

        mco = double('mcollective client')
        expect(mco).to receive(:insert).with(any_args).and_return([])

        expect(cmd).to receive(:mco_client).with('k8ssecret', :fabric => 'space') do |*_args, &block|
          block.call(mco)
        end

        expect(@open3).to receive(:capture3).
          with('kubectl',
               'apply',
               '--context',
               'space',
               '--prune',
               '-l',
               'stack=myk8sstack,machineset=myk8sappservice',
               '-f',
               '-',
               :stdin_data => match(/^---\s*$.*
                                     \bkind:\s*Service.*
                                     \bkind:\s*Deployment.*
                                     /mx)).
          and_return(['Some stdout output', 'Some stderr output', @return_status])
        expect(@return_status).to receive(:success?).and_return(true)

        cmd.reprovision nil
      end
    end

    describe 'for VMs' do
      def makes_calls_to_reprovision(thing_matcher)
        successful_response = Subscription::WaitResponse.new([], [])

        # Cleans
        expect(@nagios).to receive(:nagios_schedule_downtime).with(thing_matcher)
        expect(@cleaner).to receive(:clean_nodes).with(thing_matcher)
        expect(@puppet).to receive(:puppet_clean).with(thing_matcher)

        # Provisions
        expect(@core_actions).to receive(:get_action).with("launch").and_return(@launch_action)
        expect(@launch_action).to receive(:call).with(factory.services, thing_matcher)
        expect(@puppet).to receive(:puppet_wait_for_autosign).with(thing_matcher).and_return(successful_response)
        expect(@puppet).to receive(:puppet_wait_for_run_completion).with(thing_matcher).and_return(successful_response)
        expect(@app_deployer).to receive(:deploy_applications).with(thing_matcher)
        expect(@nagios).to receive(:nagios_schedule_uptime).with(thing_matcher)
      end

      it 'reprovisions a stack' do
        myappservice_machineset = have_attributes(:name => 'myappservice')
        myrelatedappservice_machineset = have_attributes(:name => 'myrelatedappservice')

        makes_calls_to_reprovision(myappservice_machineset)
        makes_calls_to_reprovision(myrelatedappservice_machineset)

        cmd = cmd(factory, 'e1', 'mystack')

        cmd.reprovision nil
      end

      it 'reprovisions a specific machineset' do
        machineset = have_attributes(:name => 'myappservice')
        makes_calls_to_reprovision(machineset)

        cmd = cmd(factory, 'e1', 'myappservice')

        cmd.reprovision nil
      end

      it 'reprovisions a specific VM' do
        the_thing = have_attributes(:mgmt_fqdn => 'e1-myappservice-001.mgmt.space.net.local')
        makes_calls_to_reprovision(the_thing)

        cmd = cmd(factory, 'e1', 'e1-myappservice-001.mgmt.space.net.local')

        cmd.reprovision nil
      end
    end
  end

  describe 'clean command' do
    describe 'for k8s' do
      it 'cleans a stack' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        cmd = cmd(factory, 'e1', 'myk8sstack')

        expect(@open3).to receive(:capture3).
          with('kubectl',
               'delete',
               include('deployment', 'configmap', 'service', 'networkpolicy'),
               '--context',
               'space',
               '-l',
               'stack=myk8sstack,machineset=myk8sappservice',
               '-n', 'e1').
          and_return(['Some stdout output', 'Some stderr output', @return_status])
        expect(@return_status).to receive(:success?).and_return(true)

        expect(@open3).to receive(:capture3).
          with('kubectl',
               'delete',
               include('deployment', 'configmap', 'service', 'networkpolicy'),
               '--context',
               'space',
               '-l',
               'stack=myk8sstack,machineset=myrelatedk8sappservice',
               '-n', 'e1').
          and_return(['Some stdout output', 'Some stderr output', @return_status])
        expect(@return_status).to receive(:success?).and_return(true)

        cmd.clean nil
      end

      it 'reprovisions a machineset' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        cmd = cmd(factory, 'e1', 'myk8sappservice')

        expect(@open3).to receive(:capture3).
          with('kubectl',
               'delete',
               include('deployment', 'configmap', 'service', 'networkpolicy'),
               '--context',
               'space',
               '-l',
               'stack=myk8sstack,machineset=myk8sappservice',
               '-n', 'e1').
          and_return(['Some stdout output', 'Some stderr output', @return_status])
        expect(@return_status).to receive(:success?).and_return(true)

        cmd.clean nil
      end
    end

    describe 'for VMs' do
      it 'cleans a stack' do
        myappservice_machineset = have_attributes(:name => 'myappservice')
        myrelatedappservice_machineset = have_attributes(:name => 'myrelatedappservice')

        cmd = cmd(factory, 'e1', 'mystack')

        expect(@nagios).to receive(:nagios_schedule_downtime).with(myappservice_machineset)
        expect(@cleaner).to receive(:clean_nodes).with(myappservice_machineset)
        expect(@puppet).to receive(:puppet_clean).with(myappservice_machineset)

        expect(@nagios).to receive(:nagios_schedule_downtime).with(myrelatedappservice_machineset)
        expect(@cleaner).to receive(:clean_nodes).with(myrelatedappservice_machineset)
        expect(@puppet).to receive(:puppet_clean).with(myrelatedappservice_machineset)

        cmd.clean nil
      end

      it 'cleans a specific machineset' do
        machineset = have_attributes(:name => 'myappservice')

        cmd = cmd(factory, 'e1', 'myappservice')

        expect(@nagios).to receive(:nagios_schedule_downtime).with(machineset)
        expect(@cleaner).to receive(:clean_nodes).with(machineset)
        expect(@puppet).to receive(:puppet_clean).with(machineset)

        cmd.clean nil
      end

      it 'cleans a specific VM' do
        machine = have_attributes(:mgmt_fqdn => 'e1-myappservice-001.mgmt.space.net.local')

        cmd = cmd(factory, 'e1', 'e1-myappservice-001.mgmt.space.net.local')

        expect(@nagios).to receive(:nagios_schedule_downtime).with(machine)
        expect(@cleaner).to receive(:clean_nodes).with(machine)
        expect(@puppet).to receive(:puppet_clean).with(machine)

        cmd.clean nil
      end
    end
  end

  describe 'compile command' do
    describe 'for VMs' do
      it 'prints enc and spec for everything' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        out = capture_stdout do
          cmd = cmd(factory, nil, nil)
          cmd.compile nil
        end

        expect(out).to match(/\be1-myappservice-001.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            \be1-myappservice-002.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            \be1-myrelatedappservice-001.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            \be2-myotherappservice-001.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            /mx)
      end

      it 'prints enc and spec for a stack' do
        out = capture_stdout do
          cmd = cmd(factory, 'e1', 'mystack')
          cmd.compile nil
        end

        expect(out).to match(/\be1-myappservice-001.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            \be1-myappservice-002.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            \be1-myrelatedappservice-001.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            /mx)

        expect(out).not_to match(/\be2-myotherappservice-001.mgmt.space.net.local:.*
                                \benc:.*
                                \bspec:.*
                                /mx)
      end

      it 'prints enc and spec for a specific machineset' do
        out = capture_stdout do
          cmd = cmd(factory, 'e1', 'myappservice')
          cmd.compile nil
        end

        expect(out).to match(/\be1-myappservice-001.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            \be1-myappservice-002.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            /mx)

        expect(out).not_to match(/\be2-myotherappservice-001.mgmt.space.net.local:
                                |
                                \be1-myrelatedappservice-001.mgmt.space.net.local:
                                /mx)
      end

      it 'prints enc and spec for a specific machine' do
        out = capture_stdout do
          cmd = cmd(factory, 'e1', 'e1-myappservice-001.mgmt.space.net.local')

          cmd.compile nil
        end

        expect(out).to match(/\be1-myappservice-001.mgmt.space.net.local:.*
                                            \benc:.*
                                            \bspec:.*
                                            /mx)

        expect(out).not_to match(/\be1-myappservice-002.mgmt.space.net.local:
                                                |
                                                \be1-myrelatedappservice-001.mgmt.space.net.local:
                                                |
                                                \be2-myotherappservice-001.mgmt.space.net.local:
                                                /mx)
      end
    end

    it 'fails if the name is not found' do
      cmd = cmd(factory, 'e1', 'notfound')

      expect { cmd.compile nil }.to raise_error('Entity not found')
    end

    it 'fails if more than one entity is found' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "dupedservice" do
            self.application = 'MyApplication'
          end
        end
        stack "myotherstack" do
          app_service "dupedservice" do
            self.application = 'MyOtherApplication'
          end
        end
        env 'e1', :primary_site => 'space' do
          instantiate_stack "mystack"
          instantiate_stack "myotherstack"
        end
      end

      cmd = cmd(factory, 'e1', 'dupedservice')

      expect { cmd.compile nil }.to raise_error('Too many entities found')
    end

    describe "for k8s" do
      let(:factory) do
        eval_stacks do
          stack "mystack" do
            app_service "myvmappservice" do
              self.application = 'MyApplication'
            end
            app_service "myk8sappservice", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyK8sApplication'
            end
          end
          stack "myotherstack" do
            app_service "myotherk8sappservice", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyOtherK8sApplication'
            end
          end
          env 'e1', :primary_site => 'space' do
            instantiate_stack "mystack"

            env 'childenv' do
              instantiate_stack "myotherstack"
            end
          end
        end
      end

      it 'outputs kubernetes machinesets after VMs' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        out = capture_stdout do
          cmd = cmd(factory, nil, nil)
          cmd.compile nil
        end

        expect(out).to match(/\be1-myvmappservice-001.mgmt.space.net.local:.*
                              \benc:.*
                              \bspec:.*
                              ^---\s*$.*
                              \bspace-childenv-myotherk8sappservice:.*
                              \bkind:.*
                              \bspace-e1-myk8sappservice:.*
                              \bkind:.*
                              /mx)
      end

      it 'outputs no kubernetes section if there are no kubernetes systems found' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "myvmappservice" do
              self.application = 'MyApplication'
            end
          end
          env 'e1', :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end

        out = capture_stdout do
          cmd = cmd(factory, nil, nil)
          cmd.compile nil
        end

        expect(out.scan(/---/).size).to eq 1
      end

      it 'prints k8s and VM definitions for a specific stack' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        out = capture_stdout do
          cmd = cmd(factory, 'e1', 'mystack')
          cmd.compile nil
        end

        expect(out).to match(/\be1-myvmappservice-001.mgmt.space.net.local:.*
                            \benc:.*
                            \bspec:.*
                            ^---\s*$.*\bspace-e1-myk8sappservice:.*
                            \bkind:.*
                            /mx)
      end

      it 'prints k8s definitions for a specific machineset' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        out = capture_stdout do
          cmd = cmd(factory, 'e1', 'myk8sappservice')
          cmd.compile nil
        end

        expect(out.scan(/---/).size).to eq 1
        expect(out).to match(/\bspace-e1-myk8sappservice:.*
                            \bkind:.*
                            /mx)
        expect(YAML.load(out)['space-e1-myk8sappservice'].map { |r| r['kind'] }).to include('Deployment', 'ConfigMap')
      end
    end
  end

  describe 'dependencies and dependents commands' do
    let(:factory) do
      eval_stacks do
        stack "mystack" do
          app_service "myappservice" do
            self.application = 'MyApplication'
            self.instances = 2
            depend_on 'myrelatedappservice'
            depend_on 'myk8sappservice'
          end
          app_service "myrelatedappservice" do
            self.application = 'MyRelatedApplication'
            self.instances = 1
          end
        end
        stack "myotherstack" do
          app_service "myotherappservice" do
            self.application = 'MyOtherApplication'
          end
        end
        stack "myk8sstack" do
          app_service "myk8sappservice", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'MyK8sApplication'
            self.instances = 2
          end
          app_service "myrelatedk8sappservice", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'MyRelatedK8sApplication'
            self.instances = 1
            depend_on 'myotherappservice', 'e2'
          end
        end
        env 'e1', :primary_site => 'space' do
          instantiate_stack "mystack"
          instantiate_stack "myk8sstack"
        end
        env 'e2', :primary_site => 'space' do
          instantiate_stack "myotherstack"
        end
      end
    end

    describe "dependencies" do
      it 'prints dependencies of an individual machine' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        out = YAML.load(capture_stdout do
          cmd = cmd(factory, 'e1', 'e1-myappservice-001.mgmt.space.net.local')
          cmd.dependencies nil
        end)

        expect(out).to contain_exactly('e1-myrelatedappservice-001.mgmt.space.net.local', 'e1-myk8sstack-myk8sappservice')
      end

      it 'prints dependencies of a k8s service' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        out = YAML.load(capture_stdout do
          cmd = cmd(factory, 'e1', 'myrelatedk8sappservice')
          cmd.dependencies nil
        end)

        expect(out).to contain_exactly('e2-myotherappservice-001.mgmt.space.net.local', 'e2-myotherappservice-002.mgmt.space.net.local')
      end
    end

    describe 'dependents' do
      it 'prints dependents of an individual machine' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        out = YAML.load(capture_stdout do
          cmd = cmd(factory, 'e1', 'e1-myrelatedappservice-001.mgmt.space.net.local')
          cmd.dependents nil
        end)

        expect(out).to contain_exactly('e1-myappservice-001.mgmt.space.net.local', 'e1-myappservice-002.mgmt.space.net.local')
      end

      it 'prints k8s dependents' do
        allow(@app_deployer).to receive(:query_cmdb_for).with(anything).and_return(:target_version => '0.0.0')
        allow(@dns_resolver).to receive(:lookup).with(anything)

        out = YAML.load(capture_stdout do
          cmd = cmd(factory, 'e2', 'e2-myotherappservice-001.mgmt.space.net.local')
          cmd.dependents nil
        end)

        expect(out).to contain_exactly('e1-myk8sstack-myrelatedk8sappservice')
      end
    end
  end
end
