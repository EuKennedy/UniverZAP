require 'simplecov'
require 'simplecov_json_formatter'

# Emit BOTH HTML (for the artifact uploaded by CI) and JSON (Qlty + any
# future automated coverage reporter). Filters concentrate the report
# on app code — vendor / bin / specs themselves are noise.
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::SimpleFormatter,
    SimpleCov::Formatter::JSONFormatter
  ]
)
SimpleCov.start 'rails' do
  coverage_dir 'coverage'
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/db/'
  add_filter '/vendor/'
  add_filter '/bin/'

  # No hard minimum_coverage yet — we don't have a measured baseline.
  # Once the first green CI run uploads the artifact, set this to
  # `minimum_coverage(<current_pct - 1>)` so regressions block.
end
