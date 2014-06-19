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

  host("e1-timcyclic-002.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::http_app' => {
        'port' => "8000",
        'environment' => 'e1',
        'application'  => 'TIM',
        'group' => 'blue',
        'dependencies' => [],
        'dependant_instances' => [],
      }})

    host.to_specs.should eql([
      {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"e1-timcyclic-002.mgmt.space.net.local",
          :prod=>"e1-timcyclic-002.space.net.local"},
        :availability_group=>"e1-timcyclic",
        :networks=>[:mgmt, :prod],
        :hostname=>"e1-timcyclic-002",
        :ram=>"14680064",
        :vcpus=>"8",
        :image_size=>'10G',
        :storage=>{'/'.to_sym => {:type=>"os", :size=>"10G"}},
        :domain=>"space.net.local"}])
  end
  host("e1-timcyclic-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::http_app' => {
        'port' => "8000",
        'environment' => 'e1',
        'application'  => 'TIM',
        'group' => 'blue',
        'dependencies' => [],
        'dependant_instances' => [],
      }})

    host.to_specs.should eql([
      {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"e1-timcyclic-001.mgmt.space.net.local",
          :prod=>"e1-timcyclic-001.space.net.local"},
        :availability_group=>"e1-timcyclic",
        :networks=>[:mgmt, :prod],
        :hostname=>"e1-timcyclic-001",
        :ram=>"14680064",
        :vcpus=>"8",
        :image_size=>'10G',
        :storage=>{'/'.to_sym => {:type=>"os", :size=>"10G"}},
        :domain=>"space.net.local"}])
  end
end
