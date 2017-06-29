# This file should be used to extend the origen command line tool with tasks
# specific to your application.
# The comments below should help to get started and you can also refer to
# lib/origen/commands.rb in your Origen core workspace for more examples and
# inspiration.

# Map any command aliases here, for example to allow 'origen ex' to refer to a
# command called execute you would add a reference as shown below:
aliases ={
#  "ex" => "execute",
}

# The requested command is passed in here as @command, this checks it against
# the above alias table and should not be removed.
@command = aliases[@command] || @command

# Some helper methods to enable test coverage, these will eventually be
# added to Origen Core, but they need to be here for now and should generally
# not be modified
def path_to_coverage_report
  require 'pathname'
  Pathname.new("#{Origen.root}/coverage/index.html").relative_path_from(Pathname.pwd)
end

def enable_coverage(name, merge=true)
  if ARGV.delete("-c") || ARGV.delete("--coverage")
    require 'simplecov'
    SimpleCov.start do
      command_name name
      add_filter "DO_NOT_HAND_MODIFY"  # Exclude all imports

      at_exit do
        SimpleCov.result.format!
        puts ""
        puts "To view coverage report:"
        puts "  firefox #{path_to_coverage_report} &"
        puts ""
      end
    end
    yield
  else
    yield
  end
end

# Now branch to the specific task code
case @command

when "tags"
  Dir.chdir Origen.root do
    system "ripper-tags --recursive lib"
  end
  exit 0

## Example of how to make a command to run unit tests, this simply invokes RSpec on
## the spec directory
when "specs"
  enable_coverage("specs") do
    ARGV.unshift "spec"
    require "rspec"
    require "rspec/autorun"
  end
  exit 0 # This will never be hit on a fail, RSpec will automatically exit 1

## Example of how to make a command to run diff-based tests
#when "examples"
#  Origen.load_application
#  status = 0
#  enable_coverage("examples") do
#
#    # Compiler tests
#    ARGV = %w(templates/example.txt.erb -t debug -r approved)
#    load "origen/commands/compile.rb"
#    # Pattern generator tests
#    #ARGV = %w(some_pattern -t debug -r approved)
#    #load "#{Origen.top}/lib/origen/commands/generate.rb"
#
#    if Origen.app.stats.changed_files == 0 &&
#       Origen.app.stats.new_files == 0 &&
#       Origen.app.stats.changed_patterns == 0 &&
#       Origen.app.stats.new_patterns == 0
#
#      Origen.app.stats.report_pass
#    else
#      Origen.app.stats.report_fail
#      status = 1
#    end
#    puts ""
#  end
#  exit status  # Exit with a 1 on the event of a failure per std unix result codes

# Always leave an else clause to allow control to fall back through to the
# Origen command handler.
else
  # You probably want to also add the your commands to the help shown via
  # origen -h, you can do this be assigning the required text to @application_commands
  # before handing control back to Origen. Un-comment the example below to get started.
  @application_commands = <<-EOT
 specs        Run the specs (tests), -c will enable coverage
 tags         Generate ctags for this app
  EOT
# examples     Run the examples (tests), -c will enable coverage

end
