# Contributing to Code Beacon Tracer

Thank you for considering contributing to Code Beacon Tracer! This document outlines the process for contributing to this project.

## Code of Conduct

This project and everyone participating in it is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

This section guides you through submitting a bug report. Following these guidelines helps maintainers and the community understand your report, reproduce the behavior, and find related reports.

* **Use a clear and descriptive title** for the issue to identify the problem.
* **Describe the exact steps which reproduce the problem** in as many details as possible.
* **Provide specific examples to demonstrate the steps**. Include links to files or GitHub projects, or copy/pasteable snippets, which you use in those examples.
* **Describe the behavior you observed after following the steps** and point out what exactly is the problem with that behavior.
* **Explain which behavior you expected to see instead and why.**
* **Include screenshots and animated GIFs** which show you following the described steps and clearly demonstrate the problem.
* **If the problem wasn't triggered by a specific action**, describe what you were doing before the problem happened.

### Suggesting Enhancements

This section guides you through submitting an enhancement suggestion, including completely new features and minor improvements to existing functionality.

* **Use a clear and descriptive title** for the issue to identify the suggestion.
* **Provide a step-by-step description of the suggested enhancement** in as many details as possible.
* **Provide specific examples to demonstrate the steps**. Include copy/pasteable snippets which you use in those examples.
* **Describe the current behavior** and **explain which behavior you expected to see instead** and why.
* **Explain why this enhancement would be useful** to most Code Beacon Tracer users.

### Pull Requests

* Fill in the required template
* Do not include issue numbers in the PR title
* Include screenshots and animated GIFs in your pull request whenever possible
* Follow the Ruby styleguide
* Include tests for new features
* Document new code based on the YARD documentation style
* End all files with a newline

## Development Process

### Setup

1. Fork and clone the repository
2. Run `bin/setup` to install dependencies
3. Run `bundle exec rake spec` to run the tests

### Making Changes

1. Create a new branch: `git checkout -b my-branch-name`
2. Make your changes
3. Run the tests: `bundle exec rake spec`
4. Run the linter: `bundle exec rubocop`
5. Update the CHANGELOG.md with your changes
6. Push to your fork and submit a pull request

## Styleguides

### Git Commit Messages

* Use the present tense ("Add feature" not "Added feature")
* Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
* Limit the first line to 72 characters or less
* Reference issues and pull requests liberally after the first line

### Ruby Styleguide

* Follow the [Ruby Style Guide](https://github.com/rubocop/ruby-style-guide)
* Run `bundle exec rubocop` to ensure your changes follow the style guide

### Documentation Styleguide

* Use [YARD](https://yardoc.org/) for documentation
* Include code examples when appropriate

## Additional Notes

### Issue and Pull Request Labels

This section lists the labels we use to help us track and manage issues and pull requests.

* **bug** - Issues that are bugs
* **documentation** - Issues or PRs related to documentation
* **enhancement** - Issues that are feature requests or PRs that add new features
* **good first issue** - Good for newcomers
* **help wanted** - Extra attention is needed 