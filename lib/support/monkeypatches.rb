class Array
  def flatten_hashes
    Hash[*map(&:to_a).flatten]
  end
end
