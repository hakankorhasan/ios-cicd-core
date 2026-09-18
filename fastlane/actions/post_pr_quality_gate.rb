# encoding: utf-8

require 'yaml'
require 'net/http'
require 'uri'
require 'json'

module Fastlane
  module Actions
    class PostPrQualityGateAction < Action
      def self.run(params)
        rules_path    = params[:rules_path] || ".github/pr-rules.yml"
        pr_title      = params[:pr_title] || ENV["GITHUB_PR_TITLE"] || Actions.last_git_commit_dict[:message] rescue ""
        pr_body       = params[:pr_body] || ENV["GITHUB_PR_BODY"] || ""
        pr_number     = params[:pr_number] || ENV["PR_NUMBER"] || (ENV["GITHUB_REF"] =~ /refs\/pull\/(\d+)\/merge/ ? $1 : nil)
        github_token  = params[:github_token] || ENV["GITHUB_TOKEN"]
        repo_name     = params[:repo_name] || ENV["GITHUB_REPOSITORY"]
        dry_run       = params[:dry_run]

        # 1. Load Rules Configuration (or use defaults)
        rules = load_rules(rules_path)
        q_rules = rules["quality_gate"] || {}

        max_lines         = q_rules["max_lines_changed"] || 500
        fail_on_large     = q_rules.fetch("fail_on_large_pr", false)
        require_tests     = q_rules.fetch("require_tests_for_features", true)
        require_desc      = q_rules.fetch("require_description", true)
        min_desc_len      = q_rules["min_description_length"] || 25
        block_wip         = q_rules.fetch("block_wip_titles", true)
        critical_patterns = q_rules["critical_files"] || ['Package.swift', 'Podfile', '*.pbxproj']

        UI.message("[PR Quality Gate] Evaluating pull request rules from #{rules_path}...")

        # 2. Inspect Git Diffs
        changed_files = get_changed_files
        line_stats    = get_line_stats
        additions     = line_stats[:additions]
        deletions     = line_stats[:deletions]
        total_changed = additions + deletions

        gate_passed = true
        table_rows  = []

        # Check 1: PR Size
        if total_changed > max_lines
          if fail_on_large
            gate_passed = false
            table_rows << "| **PR Size** | 🛑 **Failed** | `+#{additions} / -#{deletions}` lines (Exceeds limit of #{max_lines}) |"
          else
            table_rows << "| **PR Size** | ⚠️ **Warning** | `+#{additions} / -#{deletions}` lines (Large PR, consider splitting) |"
          end
        else
          table_rows << "| **PR Size** | 🟢 **Passed** | `+#{additions} / -#{deletions}` lines (Under #{max_lines} limit) |"
        end

        # Check 2: Automated Tests for Source Changes
        if require_tests
          has_source_changes = changed_files.any? { |f| (f.include?("Sources/") || f.end_with?(".swift")) && !f.include?("Tests") }
          has_test_changes   = changed_files.any? { |f| f.include?("Tests") || f.end_with?("Tests.swift") }

          if has_source_changes && !has_test_changes
            table_rows << "| **Tests Added** | ⚠️ **Warning** | Source code modified without corresponding unit tests |"
          else
            table_rows << "| **Tests Added** | 🟢 **Passed** | Test suite updated or no source changes |"
          end
        end

        # Check 3: PR Description
        if require_desc
          clean_body = pr_body.to_s.strip
          if clean_body.length < min_desc_len
            table_rows << "| **PR Description** | ⚠️ **Notice** | Description is brief or missing (Min #{min_desc_len} chars) |"
          else
            table_rows << "| **PR Description** | 🟢 **Passed** | Well-documented PR description (#{clean_body.length} chars) |"
          end
        end

        # Check 4: WIP / Draft Protection
        if block_wip && pr_title =~ /^(wip|\[wip\]|draft):?/i
          gate_passed = false
          table_rows << "| **WIP Blocker** | 🛑 **Blocked** | PR title marked as Work In Progress (`#{pr_title}`) |"
        else
          table_rows << "| **WIP Blocker** | 🟢 **Passed** | Pull request marked ready for review |"
        end

        # Check 5: Critical Files Watch
        matched_critical = []
        critical_patterns.each do |pattern|
          regex_pattern = Regexp.new(pattern.gsub('.', '\.').gsub('*', '.*'))
          matched = changed_files.select { |f| f =~ regex_pattern }
          matched_critical.concat(matched)
        end
        matched_critical.uniq!

        if matched_critical.any?
          table_rows << "| **Critical Files** | ⚠️ **Review** | Touched sensitive configs: `#{matched_critical.join(', ')}` |"
        else
          table_rows << "| **Critical Files** | 🟢 **Passed** | No core configuration files touched |"
        end

        # 3. Construct Markdown Comment
        status_banner = gate_passed ? "🟢 **QUALITY GATE PASSED**" : "🛑 **QUALITY GATE REQUIRES ATTENTION**"

        markdown_report = <<~MARKDOWN
          ## 🤖 iOS Platform PR Quality Gate

          #{status_banner}

          | Check | Status | Details |
          | :--- | :---: | :--- |
          #{table_rows.join("\n")}

          > ⏱️ Evaluated via **[ios-cicd-core@v1.3.0](https://github.com/hakankorhasan/ios-cicd-core)** • Config: `#{rules_path}`
        MARKDOWN

        # 4. Dry Run or Output to Console
        if dry_run || github_token.to_s.strip.empty? || pr_number.nil? || repo_name.nil?
          UI.important("=" * 65)
          UI.important("🤖 [PR Quality Gate] SIMULATED PR REVIEW COMMENT (Dry-Run / Local)")
          UI.message("\n" + markdown_report)
          UI.important("Quality Gate Decision: #{gate_passed ? 'PASSED ✅' : 'FAILED ❌'}")
          UI.important("=" * 65)
          return { passed: gate_passed, report: markdown_report }
        end

        # 5. Post or Update Comment via GitHub API (Update-in-Place)
        post_or_update_github_comment(repo_name, pr_number, github_token, markdown_report)

        { passed: gate_passed, report: markdown_report }
      end

      # Load rules from YAML or provide enterprise defaults
      def self.load_rules(path)
        if File.exist?(path)
          YAML.load_file(path) rescue {}
        else
          {
            "quality_gate" => {
              "max_lines_changed" => 500,
              "fail_on_large_pr" => false,
              "require_tests_for_features" => true,
              "require_description" => true,
              "min_description_length" => 25,
              "block_wip_titles" => true,
              "critical_files" => ['Package.swift', 'Podfile', '*.pbxproj']
            }
          }
        end
      end

      def self.get_changed_files
        raw = Actions.sh("git diff --name-only HEAD~1 2>/dev/null || git diff --name-only origin/main...HEAD 2>/dev/null || git ls-files -m").strip
        raw.split("\n").map(&:strip).reject(&:empty?)
      rescue StandardError
        []
      end

      def self.get_line_stats
        raw = Actions.sh("git diff --numstat HEAD~1 2>/dev/null || git diff --numstat origin/main...HEAD 2>/dev/null || git diff --numstat").strip
        additions = 0
        deletions = 0
        raw.each_line do |line|
          parts = line.split("\t")
          additions += parts[0].to_i if parts[0] =~ /^\d+$/
          deletions += parts[1].to_i if parts[1] =~ /^\d+$/
        end
        { additions: additions, deletions: deletions }
      rescue StandardError
        { additions: 0, deletions: 0 }
      end

      def self.post_or_update_github_comment(repo, pr_number, token, body)
        uri = URI("https://api.github.com/repos/#{repo}/issues/#{pr_number}/comments")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        headers = {
          "Authorization" => "Bearer #{token}",
          "Accept" => "application/vnd.github.v3+json",
          "Content-Type" => "application/json",
          "User-Agent" => "ios-cicd-core-quality-gate"
        }

        # Check existing comments to update-in-place
        req_get = Net::HTTP::Get.new(uri.request_uri, headers)
        res_get = http.request(req_get)

        existing_comment_id = nil
        if res_get.code.to_i == 200
          comments = JSON.parse(res_get.body) rescue []
          bot_comment = comments.find { |c| c["body"].to_s.include?("## 🤖 iOS Platform PR Quality Gate") }
          existing_comment_id = bot_comment["id"] if bot_comment
        end

        if existing_comment_id
          # PATCH existing comment
          update_uri = URI("https://api.github.com/repos/#{repo}/issues/comments/#{existing_comment_id}")
          req_patch = Net::HTTP::Patch.new(update_uri.request_uri, headers)
          req_patch.body = { "body" => body }.to_json
          res_patch = http.request(req_patch)
          if res_patch.code.to_i == 200
            UI.success("[PR Quality Gate] Successfully updated existing review comment on PR ##{pr_number}!")
          end
        else
          # POST new comment
          req_post = Net::HTTP::Post.new(uri.request_uri, headers)
          req_post.body = { "body" => body }.to_json
          res_post = http.request(req_post)
          if [200, 201].include?(res_post.code.to_i)
            UI.success("[PR Quality Gate] Successfully posted PR review comment to PR ##{pr_number}!")
          end
        end
      rescue StandardError => e
        UI.important("[PR Quality Gate] Could not post comment to GitHub API: #{e.message}")
      end

      def self.description
        "Enforces configurable PR quality gate rules and posts/updates rich bot review comments on GitHub PRs"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :rules_path,
                                       description: "Path to project's custom pr-rules.yml",
                                       optional: true,
                                       default_value: ".github/pr-rules.yml",
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :pr_title,
                                       description: "Pull Request title",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :pr_body,
                                       description: "Pull Request description body",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :pr_number,
                                       description: "Pull Request number",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :github_token,
                                       env_name: "GITHUB_TOKEN",
                                       description: "GitHub API Token",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :repo_name,
                                       env_name: "GITHUB_REPOSITORY",
                                       description: "GitHub repository (owner/repo)",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :dry_run,
                                       description: "Dry run mode (prints to console)",
                                       default_value: false,
                                       is_string: false)
        ]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end

      def self.authors
        ["Hakan Körhasan"]
      end

      def self.category
        :source_control
      end
    end
  end
end
