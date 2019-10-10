require 'stackbuilder/stacks/namespace'
require 'spec_helper'

describe Stacks::KubernetesResourceBundle do
  it 'uploads the secrets using mcollective' do
    return_status = double('return_status')
    open3 = double('Open3')
    stub_const("Open3", open3)
    allow(open3).to receive(:capture3).with(any_args).and_return(['stdout', 'stderr', return_status])
    allow(return_status).to receive(:success?).and_return(true)
    client = double('mco client')

    r = Stacks::KubernetesResourceBundle.new('site',
                                             'test_env',
                                             'stack',
                                             'ms',
                                             { 'app.kubernetes.io/name' => 'testapp' },
                                             [],
                                             { 'secret/data' => 'secret_data' },
                                             'environment' => 'test_env')

    stdout = <<EOF
clientVersion:
  major: "1"
  minor: "16"
serverVersion:
  major: "1"
  minor: "16"
EOF
    allow(open3).to receive(:capture3).with('kubectl', 'version', '--context', 'site', '-o', 'yaml').and_return([stdout, 'stderr', return_status])

    expect(client).to receive(:insert).with(:namespace => 'test_env',
                                            :context => 'site',
                                            :secret_resource => 'testapp-secret',
                                            :labels => {
                                              'app.kubernetes.io/name' => 'testapp',
                                              'app.kubernetes.io/managed-by' => 'mco-secretagent'
                                            },
                                            :keys => ['secret/data'],
                                            :scope => { 'environment' => 'test_env' }).and_return([])

    r.apply_and_prune(client)
  end

  it 'fails when kubectl is not up to date' do
    return_status = double('return_status')
    open3 = double('Open3')
    stub_const("Open3", open3)
    stdout = <<EOF
clientVersion:
  major: "1"
  minor: "15"
serverVersion:
  major: "1"
  minor: "16"
EOF
    allow(open3).to receive(:capture3).with(any_args).and_return([stdout, 'stderr', return_status])
    allow(return_status).to receive(:success?).and_return(true)
    client = double('mco client')

    allow(client).to receive(:insert).with(:namespace => 'test_env',
                                           :context => 'site',
                                           :secret_resource => 'testapp-secret',
                                           :labels => {
                                             'app.kubernetes.io/name' => 'testapp',
                                             'app.kubernetes.io/managed-by' => 'mco-secretagent'
                                           },
                                           :keys => ['secret/data'],
                                           :scope => { 'environment' => 'test_env' }).and_return([])

    r = Stacks::KubernetesResourceBundle.new('site',
                                             'test_env',
                                             'stack',
                                             'ms',
                                             { 'app.kubernetes.io/name' => 'testapp' },
                                             [],
                                             { 'secret/data' => 'secret_data' },
                                             'environment' => 'test_env')

    expect { r.apply_and_prune(client) }.to raise_error('Your kubectl version is out of date. Please update to at least version 1.16')
  end

  it 'fails when applying a resource type that is not in the prune whitelist' do
    return_status = double('return_status')
    open3 = double('Open3')
    stub_const("Open3", open3)
    stdout = <<EOF
clientVersion:
  major: "1"
  minor: "16"
serverVersion:
  major: "1"
  minor: "16"
EOF
    allow(open3).to receive(:capture3).with(any_args).and_return([stdout, 'stderr', return_status])
    allow(return_status).to receive(:success?).and_return(true)
    client = double('mco client')

    allow(client).to receive(:insert).with(:namespace => 'test_env',
                                           :context => 'site',
                                           :secret_resource => 'testapp-secret',
                                           :labels => {
                                             'app.kubernetes.io/name' => 'testapp',
                                             'app.kubernetes.io/managed-by' => 'mco-secretagent'
                                           },
                                           :keys => ['secret/data'],
                                           :scope => { 'environment' => 'test_env' }).and_return([])

    r = Stacks::KubernetesResourceBundle.new('site',
                                             'test_env',
                                             'stack',
                                             'ms',
                                             { 'app.kubernetes.io/name' => 'testapp' },
                                             [{
                                               'kind' => 'ThisIsANewResourceKind',
                                               'apiVersion' => 'v1'
                                             }],
                                             { 'secret/data' => 'secret_data' },
                                             'environment' => 'test_env')

    expect { r.apply_and_prune(client) }.
      to raise_error('Found new resource type(s) (/v1/ThisIsANewResourceKind) that is not in the prune whitelist. Please add it.')
  end

  it 'does not fail when kubectl is up to date' do
    return_status = double('return_status')
    open3 = double('Open3')
    stub_const("Open3", open3)
    stdout = <<EOF
clientVersion:
  major: "1"
  minor: "16"
serverVersion:
  major: "1"
  minor: "16"
EOF
    allow(open3).to receive(:capture3).with(any_args).and_return([stdout, 'stderr', return_status])
    allow(return_status).to receive(:success?).and_return(true)
    client = double('mco client')

    allow(client).to receive(:insert).with(:namespace => 'test_env',
                                           :context => 'site',
                                           :secret_resource => 'testapp-secret',
                                           :labels => {
                                             'app.kubernetes.io/name' => 'testapp',
                                             'app.kubernetes.io/managed-by' => 'mco-secretagent'
                                           },
                                           :keys => ['secret/data'],
                                           :scope => { 'environment' => 'test_env' }).and_return([])

    r = Stacks::KubernetesResourceBundle.new('site',
                                             'test_env',
                                             'stack',
                                             'ms',
                                             { 'app.kubernetes.io/name' => 'testapp' },
                                             [],
                                             { 'secret/data' => 'secret_data' },
                                             'environment' => 'test_env')

    expect { r.apply_and_prune(client) }.not_to raise_error
  end
end
