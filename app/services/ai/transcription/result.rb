# What every transcription provider must return.
#
# `duration_seconds` is not decoration: it is what the operator is billed on,
# so a provider that cannot report it has to say so (nil) rather than let the
# service invent a number.
Ai::Transcription::Result = Struct.new(:text, :model, :duration_seconds, keyword_init: true)
