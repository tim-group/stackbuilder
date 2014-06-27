require 'stacks/test_framework'

describe_stack 'tim' do
  given do
    stack 'tim' do
      standalone_appserver 'timcyclic' do
        self.application = 'TIM'
        self.instances = environment.options[:tim_instances] || 1
        each_machine do |machine|
          machine.ram = '14680064'
          machine.vcpus = '8'
          machine.image_size = '10G'
        end
      end
    end
    env "e1", { :primary_site=>"space", :tim_instances=>2 } do
      instantiate_stack "tim"
    end
  end

  host("e1-timcyclic-001.mgmt.space.net.local") do |host|
     host.should_not eql nil
  end
  host("e1-timcyclic-002.mgmt.space.net.local") do |host|
     host.should_not eql nil
  end

end
