require 'stacks/environment'

describe Stacks::VirtualService do

  subject do
    env = Stacks::Environment.new("env", {:primary_site=>"mars"}, {})
    subject = Stacks::VirtualAppService.new("myvs")
    subject.bind_to(env)
    subject
  end

  it 'generates specs to ask for vip addresses' do
    subject.to_vip_spec.should eql(
      {
        :hostname => "env-myvs",
        :fabric => "mars",
        :networks => [:prod],
        :qualified_hostnames => {:prod => "env-myvs-vip.mars.net.local"}
      }
    )
  end

  it 'if we enable nat then we should get a front-vip as well' do
    subject.enable_nat
    subject.to_vip_spec.should eql(
      {
        :hostname => "env-myvs",
        :fabric => "mars",
        :networks => [:prod, :front],
        :qualified_hostnames => {:prod => "env-myvs-vip.mars.net.local", :front => "env-myvs-vip.front.mars.net.local"}
      }
    )
  end
end
