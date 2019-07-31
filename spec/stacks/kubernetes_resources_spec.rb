require 'stackbuilder/stacks/namespace'
require 'spec_helper'

describe Stacks::KubernetesResources do
  it 'uploads the secrets using mcollective' do
    return_status = double('return_status')
    open3 = double('Open3')
    stub_const("Open3", open3)
    allow(open3).to receive(:capture3).with(any_args).and_return(['stdout', 'stderr', return_status])
    allow(return_status).to receive(:success?).and_return(true)
    client = double('mco client')

    r = Stacks::KubernetesResources.new('site',
                                        'test_env',
                                        'stack',
                                        'ms',
                                        { 'app.kubernetes.io/name' => 'testapp' },
                                        [],
                                        { 'secret/data' => 'secret_data' },
                                        'environment' => 'test_env')

    expect(client).to receive(:insert).with(:namespace => 'test_env',
                                            :context => 'site',
                                            :secret_resource => 'testapp-secret',
                                            :labels => { 'app.kubernetes.io/name' => 'testapp' },
                                            :keys => ['secret/data'],
                                            :scope => { 'environment' => 'test_env' }).and_return([])

    r.apply_and_prune(client)
  end
end
