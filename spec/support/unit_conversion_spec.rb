require 'stackbuilder/support/unit_conversion'
require 'spec_helper'

describe Support::UnitConversion do
  Happy_cases = [
    ['1G', 'M', 1024],
    ['1M', 'K', 1024],
    ['1K', 'B', 1024],

    ['1G', 'G', 1],
    ['1M', 'M', 1],
    ['1K', 'K', 1],
    ['1B', 'B', 1],

    ['1024B', 'K', 1],
    ['1024K', 'M', 1],
    ['1024M', 'G', 1],

    ['512K', 'M', 0.5],
    ['0.5M', 'K', 512],

    ['3m', 'k', 1024 * 3] # be case insensitive
  ]

  Sad_cases = [
    ['1U', 'B', 'Unknown source unit U in "1U"'],
    ['B', 'B', 'No value specified in "B"'],
    ['1M', 'U', 'Unknown target unit U']
  ]

  describe 'data_to_unit' do
    Happy_cases.each do |spec|
      it "converts #{spec[0]} into #{spec[2]} #{spec[1]}" do
        expect(Support::UnitConversion.data_to_unit(spec[0], spec[1])).to eq(spec[2])
      end
    end

    Sad_cases.each do |spec|
      it "errors when given #{spec[0]} and #{spec[1]}" do
        expect do
          Support::UnitConversion.data_to_unit(spec[0], spec[1])
        end.to raise_error(ArgumentError, spec[2])
      end
    end
  end

  describe 'data_to_unit_s' do
    Happy_cases.each do |spec|
      it "converts #{spec[0]} into the string '#{spec[2]}#{spec[1]}'" do
        expect(Support::UnitConversion.data_to_unit_s(spec[0], spec[1])).to eq("#{spec[2]}#{spec[1]}")
      end
    end

    Sad_cases.each do |spec|
      it "errors when given #{spec[0]} and #{spec[1]}" do
        expect do
          Support::UnitConversion.data_to_unit_s(spec[0], spec[1])
        end.to raise_error(ArgumentError, spec[2])
      end
    end
  end
end
