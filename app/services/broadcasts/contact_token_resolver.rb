# Resolves `{contact.*}` tokens inside a broadcast's template config so each
# recipient gets their own copy. Deep-dupes first: without it one recipient's
# resolved name would leak into the next.
#
# Supported: {contact.name}, {contact.phone_number}, {contact.email} and
# {contact.attr.KEY} for custom attributes.
class Broadcasts::ContactTokenResolver
  TOKEN = /\{contact\.([a-z_]+)(?:\.([^}]+))?\}/

  def initialize(contact)
    @contact = contact
  end

  def resolve(raw)
    return raw if raw.blank?

    walk(Marshal.load(Marshal.dump(raw)))
  end

  private

  def walk(node)
    case node
    when Hash then node.transform_values { |v| walk(v) }
    when Array then node.map { |v| walk(v) }
    when String then node.gsub(TOKEN) { value_for(Regexp.last_match(1), Regexp.last_match(2)) }
    else node
    end
  end

  def value_for(field, key)
    case field
    when 'name' then @contact.name.to_s
    when 'phone', 'phone_number' then @contact.phone_number.to_s
    when 'email' then @contact.email.to_s
    when 'attr', 'custom' then (@contact.custom_attributes || {})[key].to_s
    else ''
    end
  end
end
