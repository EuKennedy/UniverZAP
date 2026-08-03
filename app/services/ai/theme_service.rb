# What customers keep asking this agent.
#
# The most useful marketing report the module can produce, and it costs nothing:
# the questions are already in the response log. A term that shows up forty times
# is either a page the operator should write or a product they should stock.
#
# Deliberately lexical, with no model call. A clustering model would give
# prettier labels and a bill per report, and the operator does not need a label
# invented for them: they need to see the word their customers actually use.
class Ai::ThemeService
  DEFAULT_DAYS = 30
  MAX_DAYS = 365
  TOP_TERMS = 15
  MIN_TERM_LENGTH = 4
  # A term nobody repeats is not a theme.
  MIN_OCCURRENCES = 2
  SAMPLE_MAX_CHARS = 140

  STOPWORDS = %w[
    para como quando onde voce voces uma dos das com por mais meu minha isso tem
    esta este muito sobre pode quero preciso fazer qual quais quanto quantos aqui
    ainda entao porque tambem depois antes agora obrigado obrigada bom dia boa
    tarde noite tudo bem vcs pra pro nao sim ola oi que ser tem ter fica ficou
    vai vou sei sabe pois mas dele dela deles seu sua meus suas
  ].freeze

  def initialize(assistant:, days: DEFAULT_DAYS)
    @assistant = assistant
    @days = days.to_i.clamp(1, MAX_DAYS)
  end

  def perform
    { period_days: @days, total_questions: questions.length, themes: themes }
  end

  private

  # Only real customer questions: the playground is the operator talking to
  # themselves, and counting it would report the operator's own curiosity as a
  # market signal.
  def questions
    @questions ||= @assistant.invocations.live
                             .where(created_at: @days.days.ago..)
                             .where.not(user_message: nil)
                             .pluck(:user_message)
  end

  def themes
    counted = Hash.new(0)
    samples = {}
    questions.each do |question|
      terms(question).each do |term|
        counted[term] += 1
        samples[term] ||= question.to_s.strip.truncate(SAMPLE_MAX_CHARS)
      end
    end
    top(counted, samples)
  end

  def top(counted, samples)
    counted.select { |_term, count| count >= MIN_OCCURRENCES }
           .sort_by { |term, count| [-count, term] }
           .first(TOP_TERMS)
           .map { |term, count| { term: term, count: count, sample: samples[term] } }
  end

  # One occurrence per question, not per mention: someone writing "preço, preço,
  # preço" is one person asking about price, not three.
  def terms(question)
    question.to_s.downcase.gsub(/[^\p{Alnum}\s]/u, ' ').split
            .reject { |word| word.length < MIN_TERM_LENGTH || STOPWORDS.include?(word) }
            .uniq
  end
end
