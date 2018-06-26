module RRDonnelley
  class SampleHistories

    attr_reader :sample_histories

    def initialize(sample_histories)
      @sample_histories = sample_histories
    end

    def self.from_xml(child)
      histories_tag = child.children.find do |child|
        child.name.downcase == 'samplephotohistories'
      end

      # Protect empty file case, histories_tag will be nil
      if histories_tag
        new(histories_tag.children.select do |child|
          child.name.downcase == 'history'
        end.map do |sample_history|
          SampleHistory.from_xml(sample_history)
        end.compact)
      end
    end

    def to_xml
      xml = Builder::XmlMarkup.new
      xml.tag!('histories') do |histories|
        histories.tag!('sampleHistories') do |sample_histories_tag|
          sample_histories.each do |sample_history|
            sample_histories_tag.tag!('history') do |history|
              history.tag!('sample', { 'id' => sample_history.sample['id'] })
              sample_history.events.each do |event|
                history.tag!('event',
                  {
                    'type' => sample_history.event['type'],
                    'qualifier' => sample_history.event['qualifier'],
                    'time' => sample_history.event['time']
                  }
                ) do |event_tag|
                  if sample_history.event['shipment']
                    event_tag.tag!('shipment',
                      {
                        'carrier' => sample_history.event['shipment']['carrier'],
                        'trackingNumber' => sample_history.event['shipment']['trackingNumber']
                      }
                    )
                  end
                end
              end
            end
          end
        end
      end
      xml.target!
    end

    class SampleHistory

      attr_reader :sample, :events

      def initialize(sample: nil, events: nil)
        @sample = sample
        @events = events
      end

      def self.from_xml(child)
        sample = child.children.find { |item| item.name == 'sample' }
        return nil unless sample

        # TODO: Change this to use child as event source when RRD makes change on their end
        event_source = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? child : sample

        new(
          sample: {
            'id' => sample['id']
          },
          events: event_source.children.select do |item|
            item.name == 'event'
          end.map do |event|
            {
              'type' => event['type'],
              'qualifier' => event['qualifier'],
              'time' => event['time'],
              'shipment' => event.children.select do |item|
                item.name == 'shipment'
              end.map do |shipment|
                {
                  'carrier' => shipment['carrier'],
                  'trackingNumber' => shipment['trackingNumber']
                }
              end.first
            }
          end
        )
      end

    end

  end
end
