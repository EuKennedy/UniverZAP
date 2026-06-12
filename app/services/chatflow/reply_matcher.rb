# Maps a customer's reply to a menu option. WhatsApp delivers a button/list
# selection as the option *title* (handled by `by_label`); a customer typing
# "1" or "1-" hits `by_index`; an exact value match wins first. Returns the
# matched option hash ({ 'label' =>, 'value' => }) or nil.
class Chatflow::ReplyMatcher
  def initialize(node, reply_text)
    @options = node.menu_options
    @text = reply_text.to_s.strip.downcase
  end

  def match
    return nil if @text.blank? || @options.empty?

    by_value || by_index || by_label
  end

  private

  def by_value
    @options.find { |o| o['value'].to_s.downcase == @text }
  end

  # Strip everything but digits so "1️⃣", "1-", "1." and "opção 1" collapse to
  # the ordinal. Empty (pure text reply) falls through to label matching.
  def by_index
    digits = @text.gsub(/\D/, '')
    return nil if digits.blank?

    idx = digits.to_i - 1
    return nil if idx.negative? || idx >= @options.size

    @options[idx]
  end

  def by_label
    @options.find { |o| o['label'].to_s.downcase == @text } ||
      @options.find { |o| o['label'].present? && @text.include?(o['label'].to_s.downcase) }
  end
end
