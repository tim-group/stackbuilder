require 'stackbuilder/support/namespace'

class Support::DigestGenerator
  def self.from_hash(h)
    Digest::SHA1.hexdigest(canonize_hash(h).to_s)[0..6]
  end

  def self.canonize_hash(h)
    r = h.map do |k, v|
      if v.is_a?(Hash)
        canonized_value = canonize_hash(v)
      else
        canonized_value = v
      end
      [k, canonized_value]
    end
    Hash[r.sort]
  end
end
