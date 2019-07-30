require 'stackbuilder/stacks/namespace'
require 'spec_helper'

describe Stacks::KubernetesResources do
  it 'does something' do
    return_status = double('return_status')
    open3 = double('Open3')
    stub_const("Open3", open3)

    r = Stacks::KubernetesResources.new('site', 'test_env', 'stack', 'ms', [], ['secret'], 'environment' => 'test_env')

    expect(open3).to receive(:capture3).with(any_args).and_return(['stdout', 'stderr', return_status])
    expect(return_status).to receive(:success?).and_return(true)

    r.apply_and_prune
  end
end
