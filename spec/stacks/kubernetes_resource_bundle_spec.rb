require 'stackbuilder/stacks/namespace'
require 'spec_helper'

describe Stacks::KubernetesResourceBundle do
  def allow_version_check_to_succeed(open3, site)
    return_status = double('return_status')
    stdout = <<EOF
clientVersion:
  major: "1"
  minor: "16"
serverVersion:
  major: "1"
  minor: "16"
EOF
    allow(open3).to receive(:capture3).with('kubectl', 'version', '--context', site, '-o', 'yaml').and_return([stdout, 'stderr', return_status])
    allow(return_status).to receive(:success?).and_return(true)
  end

  it 'uploads the secrets using mcollective' do
    open3 = double('Open3')
    stub_const("Open3", open3)
    return_status = double('return_status')
    allow(open3).to receive(:capture3).with(any_args).and_return(['stdout', 'stderr', return_status])
    allow(return_status).to receive(:success?).and_return(true)
    client = double('mco client')

    r = Stacks::KubernetesResourceBundle.new('site',
                                             'test_env',
                                             { 'app.kubernetes.io/name' => 'testapp',
                                               'stack' => 'stack',
                                               'machineset' => 'ms' },
                                             [],
                                             { 'secret/data' => 'secret_data' },
                                             { 'environment' => 'test_env' },
                                             'foo')

    allow_version_check_to_succeed(open3, 'site')

    expect(client).to receive(:insert).with(:namespace => 'test_env',
                                            :context => 'site',
                                            :secret_resource => 'foo',
                                            :labels => {
                                              'app.kubernetes.io/name' => 'testapp',
                                              'app.kubernetes.io/managed-by' => 'mco-secretagent',
                                              'stack' => 'stack',
                                              'machineset' => 'ms'
                                            },
                                            :keys => ['secret/data'],
                                            :scope => { 'environment' => 'test_env' }).and_return([])

    r.apply_and_prune(client)
  end

  it 'fails when kubectl is not up to date' do
    open3 = double('Open3')
    stub_const("Open3", open3)
    return_status = double('return_status')
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
                                           :secret_resource => 'foo',
                                           :labels => {
                                             'app.kubernetes.io/name' => 'testapp',
                                             'app.kubernetes.io/managed-by' => 'mco-secretagent',
                                             'stack' => 'stack',
                                             'machineset' => 'ms'
                                           },
                                           :keys => ['secret/data'],
                                           :scope => { 'environment' => 'test_env' }).and_return([])

    r = Stacks::KubernetesResourceBundle.new('site',
                                             'test_env',
                                             { 'app.kubernetes.io/name' => 'testapp',
                                               'stack' => 'stack',
                                               'machineset' => 'ms' },
                                             [],
                                             { 'secret/data' => 'secret_data' },
                                             { 'environment' => 'test_env' },
                                             'foo')

    expect { r.apply_and_prune(client) }.to raise_error('Your kubectl version is out of date. Please update to at least version 1.16')
  end

  it 'fails when applying a resource type that is not in the prune whitelist' do
    open3 = double('Open3')
    stub_const("Open3", open3)
    allow_version_check_to_succeed(open3, 'site')
    client = double('mco client')

    allow(client).to receive(:insert).with(:namespace => 'test_env',
                                           :context => 'site',
                                           :secret_resource => 'foo',
                                           :labels => {
                                             'app.kubernetes.io/name' => 'testapp',
                                             'app.kubernetes.io/managed-by' => 'mco-secretagent',
                                             'stack' => 'stack',
                                             'machineset' => 'ms'
                                           },
                                           :keys => ['secret/data'],
                                           :scope => { 'environment' => 'test_env' }).and_return([])

    r = Stacks::KubernetesResourceBundle.new('site',
                                             'test_env',
                                             { 'app.kubernetes.io/name' => 'testapp',
                                               'stack' => 'stack',
                                               'machineset' => 'ms' },
                                             [{
                                               'kind' => 'ThisIsANewResourceKind',
                                               'apiVersion' => 'v1'
                                             }],
                                             { 'secret/data' => 'secret_data' },
                                             { 'environment' => 'test_env' },
                                             'foo')

    expect { r.apply_and_prune(client) }.
      to raise_error('Found new resource type(s) (/v1/ThisIsANewResourceKind) that is not in the prune whitelist. Please add it.')
  end

  it 'does not fail when kubectl is up to date' do
    open3 = double('Open3')
    stub_const("Open3", open3)
    client = double('mco client')

    return_status = double('return_status')
    allow(open3).to receive(:capture3).with(any_args).and_return(['stdout', 'stderr', return_status])
    allow(return_status).to receive(:success?).and_return(true)
    allow_version_check_to_succeed(open3, 'site')

    allow(client).to receive(:insert).with(:namespace => 'test_env',
                                           :context => 'site',
                                           :secret_resource => 'foo',
                                           :labels => {
                                             'app.kubernetes.io/name' => 'testapp',
                                             'app.kubernetes.io/managed-by' => 'mco-secretagent',
                                             'stack' => 'stack',
                                             'machineset' => 'ms'
                                           },
                                           :keys => ['secret/data'],
                                           :scope => { 'environment' => 'test_env' }).and_return([])

    r = Stacks::KubernetesResourceBundle.new('site',
                                             'test_env',
                                             { 'app.kubernetes.io/name' => 'testapp',
                                               'stack' => 'stack',
                                               'machineset' => 'ms' },
                                             [],
                                             { 'secret/data' => 'secret_data' },
                                             { 'environment' => 'test_env' },
                                             'foo')

    expect { r.apply_and_prune(client) }.not_to raise_error
  end

  describe 'deployment checker' do
    it 'fails if the deployed version is different from the current version' do
      open3 = double('Open3')
      stub_const("Open3", open3)
      allow_version_check_to_succeed(open3, 'site')
      return_status = double('return_status')
      allow(return_status).to receive(:success?).and_return(true)

      r = Stacks::KubernetesResourceBundle.new(
        'site',
        'test_env',
        {
          'app.kubernetes.io/name' => 'testapp',
          'stack' => 'stack',
          'machineset' => 'ms',
          'app.kubernetes.io/version' => '0.0.1'
        },
        [
          {
            'kind' => 'Deployment',
            'metadata' => {
              'name' => 'test-deployment',
              'labels' => {
                'app.kubernetes.io/version' => '1.2.3',
                'app.kubernetes.io/component' => 'app_service'
              }
            }
          }
        ],
        { 'secret/data' => 'secret_data' },
        { 'environment' => 'test_env' },
        'foo'
      )

      stdout = '0.0.2'
      allow(open3).to receive(:capture3).with('kubectl', 'get',
                                              '--context', 'site',
                                              '--namespace', 'test_env',
                                              'deployments.app', 'test-deployment',
                                              '-o', 'jsonpath={.metadata.labels.app\.kubernetes\.io/version}').
        and_return([stdout, 'stderr', return_status])

      expect { r.check_deployment_version }.to raise_error('Deployment version unexpected: checking deployment of 1.2.3 but found version 0.0.2 deployed')
    end

    it 'will succeed if deployment version is correct' do
      return_status = double('return_status')
      open3 = double('Open3')
      stub_const("Open3", open3)
      allow_version_check_to_succeed(open3, 'site')

      expect(open3).to receive(:capture3).with('kubectl', 'get',
                                               '--context', 'site',
                                               '--namespace', 'test_env',
                                               'deployments.app', 'test-deployment',
                                               '-o', 'jsonpath={.metadata.labels.app\.kubernetes\.io/version}').
        and_return(['1.2.3', 'stderr', return_status])
      allow(return_status).to receive(:success?).and_return(true)

      r = Stacks::KubernetesResourceBundle.new('site',
                                               'test_env',
                                               { 'app.kubernetes.io/name' => 'testapp',
                                                 'stack' => 'stack',
                                                 'machineset' => 'ms' },
                                               [
                                                 {
                                                   'kind' => 'Deployment',
                                                   'metadata' => {
                                                     'name' => 'test-deployment',
                                                     'labels' => {
                                                       'app.kubernetes.io/version' => '1.2.3',
                                                       'app.kubernetes.io/component' => 'app_service'
                                                     }
                                                   }
                                                 },
                                                 {
                                                   'kind' => 'Deployment',
                                                   'metadata' => {
                                                     'name' => 'test-deployment-ing',
                                                     'labels' => {
                                                       'app.kubernetes.io/version' => '1.2.3',
                                                       'app.kubernetes.io/component' => 'ingress'
                                                     }
                                                   }
                                                 }],
                                               { 'secret/data' => 'secret_data' },
                                               { 'environment' => 'test_env' },
                                               'foo')

      expect { r.check_deployment_version }.not_to raise_error
    end
  end
end
