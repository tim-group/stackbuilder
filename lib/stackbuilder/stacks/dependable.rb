class Stacks::Dependable
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def to_hash
    {
      @name => {}
    }
  end
end
