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

require 'git-pivotal-tracker-integration/command/base'
require 'git-pivotal-tracker-integration/command/command'
require 'git-pivotal-tracker-integration/util/git'
require 'git-pivotal-tracker-integration/util/story'
require 'pivotal-tracker'

# The class that encapsulates starting a Pivotal Tracker Story
class GitPivotalTrackerIntegration::Command::Start < GitPivotalTrackerIntegration::Command::Base

  # Starts a Pivotal Tracker story by doing the following steps:
  # * Create a branch
  # * Add default commit hook
  # * Start the story on Pivotal Tracker
  #
  # @param [String, nil] filter a filter for selecting the story to start.  This
  #   filter can be either:
  #   * a story id
  #   * a story type (feature, bug, chore)
  #   * +nil+
  # @return [void]
  def run(filter)
    story = GitPivotalTrackerIntegration::Util::Story.select_story @project, filter

    GitPivotalTrackerIntegration::Util::Story.pretty_print story

    if (!story_is_startable?(story))
      abort "Story is not in a startable state"
    end

    development_branch_name = development_branch_name story

    # Checkout {remote} / {master}

    config = GitPivotalTrackerIntegration::Command::Configuration.new
    GitPivotalTrackerIntegration::Util::Git.create_branch config.base_remote, config.base_branch, config.personal_remote, development_branch_name
    @configuration.story = story

    GitPivotalTrackerIntegration::Util::Git.add_hook 'prepare-commit-msg', File.join(File.dirname(__FILE__), 'prepare-commit-msg.sh')

    start_on_tracker story
  end

  private

  def development_branch_name(story)
    suggested = "#{story.id}-#{story.name.strip.gsub(/[^a-zA-Z0-9]/, '-').squeeze}"
    puts "suggested name: #{suggested}"
    user_choice = ask("Enter branch name (or enter to accept suggestion)").strip
    if (user_choice == '')
      branch_name = suggested
    else
      branch_name = "#{story.id}-" + user_choice.gsub(/[^a-zA-Z0-9]/, '-').squeeze
    end
    puts
    branch_name
  end

  def story_is_startable?(story)
    # -1 means unestimated
    story.estimate != -1
  end

  def start_on_tracker(story)
    config = GitPivotalTrackerIntegration::Command::Configuration.new
    print 'Starting story on Pivotal Tracker... '
    story.update(
      :current_state => 'started',
      :owned_by => config.pivotal_full_name
    )
    puts 'OK'
  end

end
