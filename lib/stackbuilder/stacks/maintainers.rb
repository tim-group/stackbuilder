module Stacks::Maintainers
  def person(name, contacts = {})
    {
      'type' => 'Individual',
      'name' => name
    }.merge(contacts)
  end

  def slack(channel_name)
    {
      'type' => 'Group',
      'slack_channel' => channel_name
    }
  end
end
