class Array
  def flatten_hashes
    Hash[*self.map(&:to_a).flatten]
  end
end


