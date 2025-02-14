require "rainbow/refinement"

using Rainbow

module SysHelper
  # Run a multiple system commands and return true if all commands succeed
  # If any command fails, the method will return false and stop executing
  # any further commands.
  #
  # Provide a block to evaluate the output of the command and return true
  # if the command was successful. If the block returns false, the method
  # will return false and stop executing any further commands.
  #
  # @param *steps [Array<Array<String>>] an array of commands to run
  # @param block [Proc] a block to evaluate the output of the command
  # @return [Boolean] true if all commands succeed, false otherwise
  #
  # @example
  #   syscall(
  #     ["echo Hello, World!"],
  #     ["ls -l"]
  #   )
  def syscall(*steps, output: $stdout, error: $stderr)
    success = false
    stdout, stderr, status = nil
    steps.each do |cmd|
      puts cmd.join(" ").bg(:green).black
      stdout, stderr, status = Open3.capture3(*cmd)
      if status.success?
        output.puts stdout
        success = true
      else
        error.puts stderr
        success = false
        exit(status.exitstatus)
      end
    end
    if block_given?
      success = !!yield(stdout, stderr, status)
      # If the error reports that a rule was bypassed, consider the command successful
      # because we are bypassing the rule intentionally when merging the release branch
      # to the production branch.
      success = true if stderr.match?(/bypassed rule violations/i)
      abort(stderr) unless success
    end
    success
  end

  # Echo a message to the console
  #
  # @param message [String] the message to echo
  # return [TrueClass]
  def sysecho(message, output: $stdout)
    output.puts message
    true
  end
end
