class Stacks::Validator
  def self.validate(inventory, validators)
    output = []
    validators.each do |validator|
      validation = validator.new
      validation.validate(inventory)
      output << validation.failure_output if validation.failed?
    end
    output.join("\n")
  end
end
