require 'stackbuilder/stacks/factory'
require 'test_classes'

describe 'environment' do
  describe 'short_name' do
    it 'should default to the first three characters of the environment name' do
      factory = eval_stacks do
        env "production", :primary_site => 'space' do
        end
      end
      env = factory.inventory.find_environment('production')
      expect(env.short_name).to eql('pro')
    end

    it 'should default to the first characters of a name shorter than three characters and pad with underscores' do
      factory = eval_stacks do
        env "e1", :primary_site => 'space' do
        end
      end
      env = factory.inventory.find_environment('e1')
      expect(env.short_name).to eql('e1_')
    end

    it 'should allow the short name to be changed from the default' do
      factory = eval_stacks do
        env "production", :primary_site => 'space' do
          set_short_name 'abc'
        end
      end
      env = factory.inventory.find_environment('production')
      expect(env.short_name).to eql('abc')
    end

    it 'should raise an error if you try to set a short name thats not the correct length' do
      expect do
        eval_stacks do
          env "e1", :primary_site => 'space' do
            set_short_name 'e1'
          end
        end
      end.to raise_error('The short name of an environment must be three characters. You tried to set_short_name of environment \'e1\' to \'e1\'')
      expect do
        eval_stacks do
          env "production", :primary_site => 'space' do
            set_short_name 'prod'
          end
        end
      end.to raise_error('The short name of an environment must be three characters. You tried to set_short_name of environment \'production\' to \'prod\'')
    end
  end
end
