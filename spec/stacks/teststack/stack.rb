# this is a test stack file for the benefit of stacks_spec.rb

stack "ststack" do
  app_service "stapp" do
    self.application = 'JavaHttpRef'
  end
end

env 'te', :primary_site => 'space', :secondary_site => 'space' do
  instantiate_stack 'ststack'
end
