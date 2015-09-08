describe 'stacks/rake_tasks' do
  it 'can be loaded' do
    expect(system("ruby -c lib/stackbuilder/stacks/rake/tasks.rb 2>&1 >/dev/null")).to eql(true)
  end
end
