require "bundler/setup"
require 'simplecov'
SimpleCov.start

require "prop_check"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

RSpec.configure do |config|
  original_stderr = $stderr
  original_stdout = $stdout
  config.before(:all) do
    if false # Redirect stderr and stdout
      $stderr = File.open(File::NULL, "w")
      $stdout = File.open(File::NULL, "w")
    end
  end

  config.after(:all) do
    if false
      $stderr = original_stderr
      $stdout = original_stdout
    end
  end
end
