require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/puppet'
require 'spec_helper'

describe Support::Puppet do
  let(:factory) do
    eval_stacks do
      stack "app" do
        mysql_cluster "db" do
          self.database_name = 'my_application'
        end
        app_service "server" do
          self.application = 'MyApplication'
          self.instances = 1
          depend_on 'db'
        end
      end
      env 'e1', :primary_site => 'space', :secondary_site => 'earth' do
        instantiate_stack "app"
      end
    end
  end

  let(:puppet) do
    puppet = Support::Puppet.new(nil)
    puppet.singleton_class.class_eval do
      attr_reader :file_contents
      def system(*args)
        @file_contents = File.read(args.last)
      end
    end

    puppet
  end

  it 'runs puppet on all of the dependencies of a service' do
    server = factory.inventory.find_environment('e1').find_stacks('e1-server-001.mgmt.space.net.local').first

    puppet.do_puppet_run_on_dependencies(server)

    expect(puppet.file_contents.split("\n")).to contain_exactly(
      'e1-db-master-001.mgmt.space.net.local',
      'e1-db-slave-001.mgmt.space.net.local',
      'e1-db-backup-001.mgmt.earth.net.local')
  end

  it 'runs puppet on all of the dependencies within a service' do
    server = factory.inventory.find_environment('e1').find_stacks('e1-db-slave-001.mgmt.space.net.local').first

    puppet.do_puppet_run_on_dependencies(server)

    expect(puppet.file_contents.split("\n")).to contain_exactly(
      'e1-db-master-001.mgmt.space.net.local',
      'e1-db-backup-001.mgmt.earth.net.local')
  end
end
