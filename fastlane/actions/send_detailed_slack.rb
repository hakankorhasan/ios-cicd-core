# encoding: utf-8

require 'net/http'
require 'uri'
require 'json'

module Fastlane
  module Actions
    class SendDetailedSlackAction < Action
      def self.run(params)
        app_name       = params[:app_name]
        status         = params[:status] || "Success"
        is_success     = status.to_s.downcase == "success"
        version_number = params[:version_number] || "N/A"
        build_number   = params[:build_number] || (ENV["BUILD_NUMBER"] || "Local")
        git_branch     = params[:git_branch] || Actions.git_branch || "main"
        git_commit     = params[:git_commit] || Actions.last_git_commit_dict[:commit_hash] rescue "unknown"
        error_message  = params[:error_message]
        webhook_url    = params[:webhook_url] || ENV["SLACK_WEBHOOK_URL"]
        dry_run        = params[:dry_run]

        status_emoji = is_success ? "[OK]" : "[FAIL]"
        status_color = is_success ? "#36a64f" : "#dc3545"
        headline     = is_success ? "#{app_name} Pipeline Succeeded!" : "#{app_name} Pipeline Failed!"

        fields = [
          {
            "type" => "mrkdwn",
            "text" => "*Application:*\n#{app_name}"
          },
          {
            "type" => "mrkdwn",
            "text" => "*Status:*\n#{status_emoji} #{status.capitalize}"
          },
          {
            "type" => "mrkdwn",
            "text" => "*Version:*\n#{version_number} (#{build_number})"
          },
          {
            "type" => "mrkdwn",
            "text" => "*Branch:*\n`#{git_branch}`"
          }
        ]

        if git_commit && git_commit != "unknown"
          fields << {
            "type" => "mrkdwn",
            "text" => "*Commit:*\n`#{git_commit[0..6]}`"
          }
        end

        blocks = [
          {
            "type" => "header",
            "text" => {
              "type" => "plain_text",
              "text" => "#{status_emoji} #{headline}",
              "emoji" => true
            }
          },
          {
            "type" => "section",
            "fields" => fields
          }
        ]

        if error_message && !is_success
          blocks << {
            "type" => "section",
            "text" => {
              "type" => "mrkdwn",
              "text" => "*Error Details:*\n```#{error_message}```"
            }
          }
        end

        payload = {
          "attachments" => [
            {
              "color" => status_color,
              "blocks" => blocks
            }
          ]
        }

        # Dry run or missing webhook handling
        if dry_run || webhook_url.to_s.strip.empty?
          UI.important("=" * 60)
          UI.important("[send_detailed_slack] SIMULATED SLACK NOTIFICATION (Dry-Run)")
          UI.important("Headline: #{headline}")
          UI.important("App: #{app_name} | Status: #{status} | Version: #{version_number} (#{build_number})")
          UI.important("Branch: #{git_branch} | Commit: #{git_commit}")
          UI.important("Error: #{error_message}") if error_message
          UI.important("Payload JSON Preview:")
          UI.message(JSON.pretty_generate(payload))
          UI.important("=" * 60)
          return payload
        end

        # Send actual HTTP Post
        begin
          uri = URI.parse(webhook_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")

          request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' })
          request.body = payload.to_json

          response = http.request(request)
          if response.code.to_i == 200
            UI.success("Successfully posted detailed status to Slack!")
          else
            UI.error("Failed to post to Slack: #{response.code} #{response.body}")
          end
        rescue StandardError => e
          UI.error("Exception while sending Slack notification: #{e.message}")
        end

        payload
      end

      def self.description
        "Sends a rich formatted Slack notification with build details and error logging"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :app_name,
                                       env_name: "SLACK_APP_NAME",
                                       description: "The name of the application",
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :status,
                                       env_name: "SLACK_STATUS",
                                       description: "Status string, e.g. Success or Failed",
                                       default_value: "Success",
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :version_number,
                                       description: "The version of the app",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :build_number,
                                       description: "The build number of the app",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :git_branch,
                                       description: "Git branch name",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :git_commit,
                                       description: "Git commit hash",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :error_message,
                                       description: "Error message details if failed",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :webhook_url,
                                       env_name: "SLACK_WEBHOOK_URL",
                                       description: "Slack Incoming Webhook URL",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :dry_run,
                                       description: "When true, outputs notification to console without sending",
                                       default_value: false,
                                       is_string: false)
        ]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end

      def self.authors
        ["Hakan Korhasan"]
      end

      def self.category
        :notifications
      end
    end
  end
end
