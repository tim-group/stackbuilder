describe 'stacks/rake_tasks' do
  it 'can be loaded' do
    system("ruby -c lib/stacks/rake/tasks.rb 2>&1 >/dev/null").should eql(true)
  end
end

