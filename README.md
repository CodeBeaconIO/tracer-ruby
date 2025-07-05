# Code Beacon Tracer

> ⚠️ **Pre-release Warning**: This is a pre-release version of Code Beacon. While core functionality exists and may provide utility, you may encounter significant bugs or issues and should expect frequent breaking changes. Testing is currently limited, and the interface and future direction may change. We appreciate your feedback and bug reports as we work towards a stable release.

A Ruby gem for tracing method calls, creating call graphs and otherwise generating dynamic runtime flows to assist with debugging and onboarding for large complex codebases. This gem persists data, but does not come with a visualization tool. It is meant to be paired with the Code Beacon VSCode extension or other similar IDE integrations.

There is a rails integration that will automatically trace every request. There is not yet a way to turn this off or filter requests.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'codebeacon-tracer'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install codebeacon-tracer
```

## Usage

### Basic Usage

```ruby
require 'codebeacon-tracer'

# Trace a block of code
Codebeacon::Tracer.trace("My Trace", "Description of what I'm tracing") do |tracer|
  # Your code to analyze goes here
  some_method_to_analyze
end

# Or start and stop tracing manually
Codebeacon::Tracer.start
# Your code to analyze
some_method_to_analyze
Codebeacon::Tracer.stop
```

### Using the Analyze Script

The project includes an `analyze` script that executes your script within a trace block.

```bash
bin/analyze path/to/your/script.rb
```

### Recording Metadata Exclusion

1. **Pre-trace filtering**: When name and description are provided to `Codebeacon::Tracer.trace()`, matching patterns skip tracing entirely.
2. **Post-trace filtering**: When metadata is set after tracing begins (e.g., Rails middleware), tracing occurs but matching patterns skip data persistence.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports are welcome on GitHub at https://github.com/jconley88/code_beacon_tracer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/jconley88/code_beacon_tracer/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Code Beacon Tracer project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jconley88/code_beacon_tracer/blob/main/CODE_OF_CONDUCT.md).
