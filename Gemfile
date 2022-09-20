source "https://rubygems.org"

# Specify your gem's dependencies in prop_check.gemspec
gemspec

#gem "bundler", "~> 2.0"

group :test do
  gem "rake", "~> 12.3", require: false
  gem "rspec", "~> 3.0", require: false
  gem "doctest-rspec", require: false
  gem "simplecov", require: false

  gem 'json', '<= 2.4.1', require: false if RUBY_VERSION <= '2.0.0'
  gem 'byebug', RUBY_VERSION < '2.5.0' ? '9.0.6' : '>= 10.0.0'
  gem 'pry-rescue'
  gem 'pry-stack_explorer'
end
