class SlackClient

  SLACK_CHANNEL = '#account-belk'.freeze
  SLACK_USERNAME = 'Belk Delayed Job Queue Alarm'.freeze
  #SLACK_ICON_URL = 'https://media.glassdoor.com/sqll/2732/belk-squarelogo.png'.freeze # belk icon
  SLACK_ICON_URL = 'https://salsify-ce.s3.amazonaws.com/customers/belk/icon.png'.freeze

  attr_reader :client, :queue_size

  Slack.configure do |config|
    config.token = ENV['SLACK_API_TOKEN']
  end

  def initialize(queue_size)
    @client = Slack::Web::Client.new
    @queue_size = queue_size
  end

  # def self.post_message(message)
  #   new(message).post_message
  # end

  def self.send_queue_alarm(queue_size)
    new(queue_size).post_message
  end

  def post_message
    client.chat_postMessage(
      channel: SLACK_CHANNEL,
      text: queue_alarm_message,
      username: SLACK_USERNAME,
      icon_url: SLACK_ICON_URL
    )
  end

  def queue_alarm_message
    "ALERT: Belk #{ENV.fetch('CARS_ENVIRONMENT')} environment delayed jobs queue is at #{queue_size}."
  end

end
