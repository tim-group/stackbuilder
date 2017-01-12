require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'jenkins' do
  given do
    stack 'jenkins' do
      cislave 'jenkinsslave' do
        each_machine do |machine|
          machine.vcpus = '8'
          machine.modify_storage('/'.to_sym => { :size => '10G' })
          machine.ram = '8000'
        end
      end

      cislave 'jenkinsslavewithlabels' do
        each_machine do |machine|
          machine.node_labels = %w(first_label second_label)
        end
      end

      cislave 'jenkinsslave-with-matrix-exclusion' do
        each_machine do |machine|
          machine.allow_matrix_host = false
        end
      end
    end

    env 'e1', :primary_site => 'space' do
      instantiate_stack 'jenkins'
    end
  end

  host('e1-jenkinsslave-002.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::cinode']).to eql('node_labels' => '', 'allow_matrix_host' => nil)
  end

  host('e1-jenkinsslave-002.mgmt.space.net.local') do |host|
    expect(host.to_spec[:networks]).to eql([:mgmt])
  end

  host('e1-jenkinsslavewithlabels-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::cinode']['node_labels']).to eql('first_label second_label')
  end

  host('e1-jenkinsslave-with-matrix-exclusion-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::cinode']['allow_matrix_host']).to eql(false)
  end
end
