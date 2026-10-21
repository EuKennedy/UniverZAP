# UniverZAP: the team tab — contacts of the business itself (staff, partners)
# picked by an admin. The pick lives on the contact (`equipe = true`, so it
# shows in the contact sidebar and filters) and is mirrored on their
# conversations (`is_team`), which moves those chats to the Equipe tab and out
# of the customer queues and counts.
class Contacts::TeamService
  ATTRIBUTE = 'equipe'.freeze

  def initialize(contact)
    @contact = contact
  end

  def add
    update(true)
  end

  def remove
    update(false)
  end

  private

  def update(member)
    attributes = (@contact.custom_attributes || {}).except(ATTRIBUTE)
    attributes[ATTRIBUTE] = true if member
    @contact.update!(custom_attributes: attributes)
    @contact.conversations.update_all(is_team: member) # rubocop:disable Rails/SkipsModelValidations
    @contact
  end
end
