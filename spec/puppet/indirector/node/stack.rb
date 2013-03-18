# this is a test stack file for the benefit of stacks_spec.rb

stack "ststack" do
  virtual_appserver "stapp" do
    self.application='JavaHttpRef'
  end
end

env 'te', :primary_site => 'local', :secondary_site => 'local' do
  instantiate_stack 'ststack'
end
