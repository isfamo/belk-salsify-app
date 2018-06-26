module RRDonnelley
  class Mailer
    attr_reader :message, :postmark, :recipients, :subject, :attachment_local_paths

    COPIED_RECIPIENTS = [].freeze

    def initialize(recipients, subject, message, attachment_local_paths)
      @postmark = Postmark::ApiClient.new(ENV.fetch("POSTMARK_API_KEY"))
      @recipients = [recipients].flatten
      @subject = subject
      @message = message
      @attachment_local_paths = attachment_local_paths
    end

    def self.send_mail(recipients: nil, subject: nil, message: nil, attachment_local_paths: [])
      new(recipients, subject, message, attachment_local_paths).send_mail
    end

    def send_mail
      @postmark.deliver(params)
    end

    private

    def params
      {
        from: 'support@salsify.com',
        to: recipients,
        cc: (COPIED_RECIPIENTS - recipients),
        subject: subject,
        html_body: message,
        attachments: attachment_local_paths.compact.uniq.map { |path| File.open(path) }
      }
    end

  end
end
