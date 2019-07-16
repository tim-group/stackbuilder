require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/cmd'
require 'stacks/test_framework'

describe 'cmd' do
  before :each do
    @core_actions = double('core_actions')
    @dns = double('dns')
    @nagios = double('nagios')
    @subscription = double('subscription')
    @puppet = double('puppet')
    @app_deployer = double('app_deployer')
  end

  def eval_stacks(&block)
    Stacks::Factory.new(Stacks::Inventory.from(&block))
  end

  def cmd(factory, env_name, stack_selector)
    CMD.new(factory, @core_actions, @dns, @nagios, @subscription, @puppet, @app_deployer,
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
      env 'e1', :primary_site => 'space' do
        instantiate_stack "mystack"
      end
      env 'e2', :primary_site => 'space' do
        instantiate_stack "myotherstack"
      end
    end
  end

  describe 'provision' do
    describe 'VMs' do
      it 'provisions a stack' do
        stack = have_attributes(:name => 'mystack')
        successful_response = Subscription::WaitResponse.new([], [])

        cmd = cmd(factory, 'e1', 'mystack')

        expect(@dns).to receive(:do_allocate_vips).with(stack)
        expect(@dns).to receive(:do_allocate_ips).with(stack)
        expect(@puppet).to receive(:do_puppet_run_on_dependencies).with(stack)

        launch_action = double("launch_action")
        expect(@core_actions).to receive(:get_action).with("launch").and_return(launch_action)
        expect(launch_action).to receive(:call).with(factory.services, stack)
        expect(@puppet).to receive(:puppet_wait_for_autosign).with(stack).and_return(successful_response)
        expect(@puppet).to receive(:puppet_wait_for_run_completion).with(stack).and_return(successful_response)
        expect(@app_deployer).to receive(:deploy_applications).with(stack)
        expect(@nagios).to receive(:nagios_schedule_uptime).with(stack)
        expect(@nagios).to receive(:do_nagios_register_new).with(stack)

        cmd.provision nil
      end

      it 'provisions a specific machineset' do
        machineset = have_attributes(:name => 'myappservice')
        successful_response = Subscription::WaitResponse.new([], [])

        cmd = cmd(factory, 'e1', 'myappservice')

        expect(@dns).to receive(:do_allocate_vips).with(machineset)
        expect(@dns).to receive(:do_allocate_ips).with(machineset)
        expect(@puppet).to receive(:do_puppet_run_on_dependencies).with(machineset)

        launch_action = double("launch_action")
        expect(@core_actions).to receive(:get_action).with("launch").and_return(launch_action)
        expect(launch_action).to receive(:call).with(factory.services, machineset)
        expect(@puppet).to receive(:puppet_wait_for_autosign).with(machineset).and_return(successful_response)
        expect(@puppet).to receive(:puppet_wait_for_run_completion).with(machineset).and_return(successful_response)
        expect(@app_deployer).to receive(:deploy_applications).with(machineset)
        expect(@nagios).to receive(:nagios_schedule_uptime).with(machineset)
        expect(@nagios).to receive(:do_nagios_register_new).with(machineset)

        cmd.provision nil
      end

      it 'provisions a specific VM' do
        the_thing = have_attributes(:mgmt_fqdn => 'e1-myappservice-001.mgmt.space.net.local')
        successful_response = Subscription::WaitResponse.new([], [])

        cmd = cmd(factory, 'e1', 'e1-myappservice-001.mgmt.space.net.local')

        expect(@dns).to receive(:do_allocate_vips).with(the_thing)
        expect(@dns).to receive(:do_allocate_ips).with(the_thing)
        expect(@puppet).to receive(:do_puppet_run_on_dependencies).with(the_thing)

        launch_action = double("launch_action")
        expect(@core_actions).to receive(:get_action).with("launch").and_return(launch_action)
        expect(launch_action).to receive(:call).with(factory.services, the_thing)
        expect(@puppet).to receive(:puppet_wait_for_autosign).with(the_thing).and_return(successful_response)
        expect(@puppet).to receive(:puppet_wait_for_run_completion).with(the_thing).and_return(successful_response)
        expect(@app_deployer).to receive(:deploy_applications).with(the_thing)
        expect(@nagios).to receive(:nagios_schedule_uptime).with(the_thing)
        expect(@nagios).to receive(:do_nagios_register_new).with(the_thing)

        cmd.provision nil
      end
    end
  end

  describe 'compile' do
    describe 'VMs' do
      it 'prints enc and spec for everything' do
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

    describe "k8s" do
      let(:factory) do
        eval_stacks do
          stack "mystack" do
            app_service "myvmappservice" do
              self.application = 'MyApplication'
            end
            app_service "myk8sappservice", :kubernetes => true do
              self.application = 'MyK8sApplication'
            end
          end
          stack "myotherstack" do
            app_service "myotherk8sappservice", :kubernetes => true do
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
        out = capture_stdout do
          cmd = cmd(factory, 'e1', 'myk8sappservice')
          cmd.compile nil
        end

        expect(out.scan(/---/).size).to eq 1
        expect(out).to match(/\bspace-e1-myk8sappservice:.*
                            \bkind:.*
                            /mx)
      end

      it 'raises an error for a specific machine in a k8s machineset' do
        cmd = cmd(factory, 'e1', 'e1-myk8sappservice-001.mgmt.space.net.local')

        expect { cmd.compile nil }.to raise_error(/Cannot compile a single host for kubernetes/)
      end
    end
  end
end
