require 'stackbuilder/support/namespace'

module Support::UnitConversion

  SCALE = {
    'G' => {
      'G' => 1,
      'M' => 1024,
      'K' => 1024 ** 2,
      'B' => 1024 ** 3
    },
    'M' => {
      'G' => 1/1024.0,
      'M' => 1,
      'K' => 1024,
      'B' => 1024 ** 2
    },
    'K' => {
      'G' => 1/(1024.0 ** 2),
      'M' => 1/1024.0,
      'K' => 1,
      'B' => 1024
    },
    'B' => {
      'G' => 1/(1024.0 ** 3),
      'M' => 1/(1024.0 ** 2),
      'K' => 1/1024.0,
      'B' => 1
    },
  }

  # Convert data size specifications to a desired unit.
  # Units are
  #   * G = Gibibytes
  #   * M = Mebibytes
  #   * K = Kibibytes
  #   * B = Bytes
  #
  # The arguments are
  #   * spec: a string of the number suffixed by the Unit (e.g. '10G').
  #   * target_unit: a string of the unit desired (e.g. 'B')
  #
  # The function returns an integer of the spec converted to the requested unit.
  #
  # If you want the output in the same format as the input (string => string) use
  # the data_to_unit_s() function.
  def self.data_to_unit(spec, target_unit)
    normalized_target = target_unit.upcase
    source_value, source_unit = spec.upcase.match(/(\d*(?:\.\d+)?)(.)/).captures

    raise ArgumentError.new("Unknown target unit #{target_unit}") unless SCALE.has_key?(normalized_target)
    raise ArgumentError.new("Unknown source unit #{source_unit} in \"#{spec}\"") unless SCALE.has_key?(source_unit)
    raise ArgumentError.new("No value specified in \"#{spec}\"") if source_value.nil? || source_value.empty?

    source_value.to_f * SCALE[source_unit][normalized_target]
  end

  def self.data_to_unit_s(spec, target_unit)
    target_value = data_to_unit(spec, target_unit)
    "#{target_value.denominator == 1 ? target_value.to_i : target_value}#{target_unit}"
  end
end
