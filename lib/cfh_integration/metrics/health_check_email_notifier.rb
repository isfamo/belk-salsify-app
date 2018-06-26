module Metrics
  class HealthCheckEmailNotifier < Muffin::EmailNotifier

    FROM = 'solutions@salsify.com'.freeze
    EMAILS = [ 'kgaughan@salsify.com', 'carey_corrigan@belk.com', 'pbreault@salsify.com', 'Adam_Miller@belk.com' ].freeze
    CATEGORY_HEALTH_CHECK_REPORT = 'lib/cfh_integration/output/category_health_check.csv'
    LIST_HEALTH_CHECK_REPORT = 'lib/cfh_integration/output/list_health_check.csv'
    CATEGORY_HEALTH_CHECK_REPORT_NAME = 'category_health_check.csv'
    LIST_HEALTH_CHECK_REPORT_NAME = 'list_health_check.csv'

    def notify
      puts "sending health check notification email..."
      postmark_client.deliver(
        from: FROM,
        to: EMAILS,
        subject: subject,
        text_body: text_body,
        attachments: attachments
      )
    end

    def subject
      "Salsify Health check reports for #{Time.now.strftime('%Y%m%d-%H%M')}"
    end

    def text_body
      'Please find reports attached.'
    end

    def attachments
      [
        {
          name: CATEGORY_HEALTH_CHECK_REPORT_NAME,
          content: [ File.read(CATEGORY_HEALTH_CHECK_REPORT) ].pack('m'),
          content_type: 'csv'
        },
        {
          name: LIST_HEALTH_CHECK_REPORT_NAME,
          content: [ File.read(LIST_HEALTH_CHECK_REPORT) ].pack('m'),
          content_type: 'csv'
        }
      ]
    end

  end
end
