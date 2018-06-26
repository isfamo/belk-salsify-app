module Maintenance
  class CheckForPimFileFtpBackups
    include FTPClients

    def self.run
      new.run
    end

    def run
      files = salsify_ftp.list_files('CARS/PROD/PIM_Delta')
      return unless files.count >= 12
      send_email_notification
    end

    def send_email_notification
      EmailNotifier.notify
    end

    class EmailNotifier < Muffin::EmailNotifier

      FROM = 'solutions@salsify.com'.freeze
      EMAILS = [
        'customer-solutions@salsify.com',
        'ecommitopssupport@belk.com'
      ].freeze

      def notify
        puts 'sending notification email...'
        postmark_client.deliver(
          from: FROM,
          to: EMAILS,
          subject: 'PIM FTP Backup Detected',
          text_body: ' ',
        )
      end

    end

  end
end
