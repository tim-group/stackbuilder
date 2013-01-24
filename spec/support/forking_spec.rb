describe Support::Forking do
  include Support::Forking

  it 'returns multiple futures for async execs' do
    future1 = async_fork_and_return do |runner|
      4.times do
        puts "A"
      end
      1
    end

    future2 = async_fork_and_return do |runner|
      4.times do
        puts "B"
      end
      2
    end

    future1.value.should eql(1)
    future2.value.should eql(2)
  end

  it 'throws an exception it a mistake was made' do
    expect do
      async_fork_and_return(:broker=>"dev-puppet", :timeout=>4).value do
        provisio
      end.value
    end.to raise_error
  end

end
