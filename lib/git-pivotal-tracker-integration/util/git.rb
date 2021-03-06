# Git Pivotal Tracker Integration
# Copyright (c) 2013 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'git-pivotal-tracker-integration/util/shell'
require 'git-pivotal-tracker-integration/util/util'

# Utilities for dealing with Git
class GitPivotalTrackerIntegration::Util::Git

  # Adds a Git hook to the current repository
  #
  # @param [String] name the name of the hook to add
  # @param [String] source the file to use as the source for the created hook
  # @param [Boolean] overwrite whether to overwrite the hook if it already exists
  # @return [void]
  def self.add_hook(name, source, overwrite = false)
    hooks_directory =  File.join repository_root, '.git', 'hooks'
    hook = File.join hooks_directory, name

    if overwrite || !File.exist?(hook)
      print "Creating Git hook #{name}...  "

      FileUtils.mkdir_p hooks_directory
      File.open(source, 'r') do |input|
        File.open(hook, 'w') do |output|
          output.write(input.read)
          output.chmod(0755)
        end
      end

      puts 'OK'
    end
  end

  # Returns the name of the currently checked out branch
  #
  # @return [String] the name of the currently checked out branch
  def self.branch_name
    GitPivotalTrackerIntegration::Util::Shell.exec('git branch').scan(/\* (.*)/)[0][0]
  end

  # Creates a branch with a given +name+ based off the main remote / branch.
  #
  # Fetches the remote.
  # checks out the remote
  # creates a new branch off of that.
  #
  # @param [String] name the name of the branch to create
  # @param [Boolean] print_messages whether to print messages
  # @return [void]
  def self.create_branch(base_remote, base_branch, personal_remote, name)
    self.exec "git fetch #{base_remote}"
    self.exec "git checkout #{base_remote}/#{base_branch}"

    self.exec "git checkout -b #{name}"


    set_config KEY_ROOT_BRANCH, base_branch, :branch
    set_config KEY_ROOT_REMOTE, base_remote, :branch
    set_config KEY_PERSONAL_REMOTE, personal_remote, :branch
  end

  # Creates a commit with a given message.  The commit includes all change
  # files.
  #
  # @param [String] message The commit message, which will be appended with
  #   +[#<story-id]+
  # @param [PivotalTracker::Story] story the story associated with the current
  #   commit
  # @return [void]
  def self.create_commit(message, story)
    GitPivotalTrackerIntegration::Util::Shell.exec "git commit --quiet --all --allow-empty --message \"#{message}\n\n[##{story.id}]\""
  end

  # Returns a Git configuration value.  This value is read using the +git
  # config+ command. The scope of the value to read can be controlled with the
  # +scope+ parameter.
  #
  # @param [String] key the key of the configuration to retrieve
  # @param [:branch, :inherited] scope the scope to read the configuration from
  #   * +:branch+: equivalent to calling +git config branch.branch-name.key+
  #   * +:inherited+: equivalent to calling +git config key+
  # @return [String] the value of the configuration
  # @raise if the specified scope is not +:branch+ or +:inherited+
  def self.get_config(key, scope = :inherited)
    if :branch == scope
      GitPivotalTrackerIntegration::Util::Shell.exec("git config branch.#{branch_name}.#{key}", false).strip
    elsif :inherited == scope
      GitPivotalTrackerIntegration::Util::Shell.exec("git config #{key}", false).strip
    else
      raise "Unable to get Git configuration for scope '#{scope}'"
    end
  end

  def self.clear_config_from_branch
      GitPivotalTrackerIntegration::Util::Shell.exec("git config --unset-all branch.#{branch_name}.#{key}", false).strip
  end

  def self.update_from_master
    branch = get_config KEY_ROOT_BRANCH, :branch
    remote = get_config KEY_ROOT_REMOTE, :branch

    print "Merging #{remote}/#{branch} in..."

    GitPivotalTrackerIntegration::Util::Shell.exec "git pull #{remote} #{branch}"
    puts 'OK'
  end

  # Push changes to the remote of the current branch
  #
  # @param [String] refs the explicit references to push
  # @return [void]
  def self.push(*refs)
    remote = get_config(KEY_PERSONAL_REMOTE, :branch) || "origin"

    print "Pushing to #{remote}... "
    GitPivotalTrackerIntegration::Util::Shell.exec "git push --quiet #{remote} " + refs.join(' ')
    puts 'OK'
  end

  # Returns the root path of the current Git repository.  The root is
  # determined by ascending the path hierarchy, starting with the current
  # working directory (+Dir#pwd+), until a directory is found that contains a
  # +.git/+ sub directory.
  #
  # @return [String] the root path of the Git repository
  # @raise if the current working directory is not in a Git repository
  def self.repository_root
    repository_root = Dir.pwd

    until Dir.entries(repository_root).any? { |child| File.directory?(child) && (child =~ /^.git$/) }
      next_repository_root = File.expand_path('..', repository_root)
      abort('Current working directory is not in a Git repository') unless repository_root != next_repository_root
      repository_root =  next_repository_root
    end

    repository_root
  end


  def self.verify_uncommitted_changes!
    result = `git diff --exit-code`
    if $?.exitstatus != 0
      abort "You have uncommitted changes!"
    end
    result = `git diff --staged --exit-code`

    if $?.exitstatus != 0
      abort "You have uncommitted staged changes!"
    end
  end

  # Sets a Git configuration value.  This value is set using the +git config+
  # command.  The scope of the set value can be controlled with the +scope+
  # parameter.
  #
  # @param [String] key the key of configuration to store
  # @param [String] value the value of the configuration to store
  # @param [:branch, :global, :local] scope the scope to store the configuration value in.
  #   * +:branch+: equivalent to calling +git config --local branch.branch-name.key value+
  #   * +:global+: equivalent to calling +git config --global key value+
  #   * +:local+:  equivalent to calling +git config --local key value+
  # @return [void]
  # @raise if the specified scope is not +:branch+, +:global+, or +:local+
  def self.set_config(key, value, scope = :local)
    if :branch == scope
      GitPivotalTrackerIntegration::Util::Shell.exec "git config --local branch.#{branch_name}.#{key} \"#{value}\""
    elsif :global == scope
      GitPivotalTrackerIntegration::Util::Shell.exec "git config --global #{key} \"#{value}\""
    elsif :local == scope
      GitPivotalTrackerIntegration::Util::Shell.exec "git config --local #{key} \"#{value}\""
    else
      raise "Unable to set Git configuration for scope '#{scope}'"
    end
  end

  private

  def self.exec(cmd)
    GitPivotalTrackerIntegration::Util::Shell.exec cmd
  end

  KEY_ROOT_BRANCH = 'root-branch'.freeze

  KEY_ROOT_REMOTE = 'root-remote'.freeze

  KEY_PERSONAL_REMOTE = 'personal-remote'.freeze

end
