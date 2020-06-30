require 'stackbuilder/stacks/factory'
require 'test_classes'
require 'spec_helper'

describe 'kubernetes' do
  describe 'custom_services' do
    describe 'service_in_kubernetes method' do
      it 'will use the calling method name in its fail output' do
        expect do
          eval_stacks do
            stack "mystack" do
              base_service "x", :kubernetes => { 'e1' => true }
            end
            env "e2", :primary_site => 'space' do
              instantiate_stack "mystack"
            end
          end
        end.to raise_error 'base_service \'x\' does not specify kubernetes property for environment \'e2\'. ' \
          'If any environments are specified then all environments where the stack is instantiated must be specified.'
      end
    end
  end
end
