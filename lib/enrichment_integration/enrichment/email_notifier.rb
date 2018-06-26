module Enrichment
  class EmailNotifier < Muffin::EmailNotifier

    FROM = 'solutions@salsify.com'.freeze

    def notify
      puts "sending notification email to #{user_email}..."
      postmark_client.deliver(
        from: FROM,
        to: user_email,
        subject: subject,
        text_body: text_body,
      )
    end

    def subject
      if import_failed?
        'Errors encountered while refreshing attributes!'
      else
        'Attributes successfully refreshed!'
      end
    end

    def text_body
      if import_failed?
        'Errors encountered while refreshing attributes! Please contact Salsify\n\n' +
          import.script_run.output
      else
        'Attributes successfully refreshed!'
      end
    end

    def import_failed?
      import.script_run.status == 'failed'
    end

  end
end
