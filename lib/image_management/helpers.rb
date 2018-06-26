module ImageManagement
  module Helpers

    MAX_LIST_UPDATE_TRIES = 8.freeze
    MIN_SLEEP_SEC = 5.freeze
    MAX_SLEEP_SEC = 30.freeze

    def query_lists(query, entity_type = 'product', page = 1, per_page = 50)
      result = client.lists(entity_type, query: query, page: page, per_page: per_page)
      if (page * per_page) < result['meta']['total_entries']
        result['lists'].concat(query_lists(query, entity_type, page, per_page))
      else
        result['lists']
      end
    end

    def update_list(list_id:, additions: [], removals: [])
      tries = 0
      return if additions.empty? && removals.empty?
      begin
        tries += 1
        client.update_list(
          list_id,
          {
            additions: { member_external_ids: additions },
            removals: { member_external_ids: removals }
          }
        )
      rescue RestClient::Locked => e
        if tries < MAX_LIST_UPDATE_TRIES
          sleep rand(MIN_SLEEP_SEC..MAX_SLEEP_SEC)
          retry
        else
          puts "#{STAMP} ERROR while updating list #{list_id} with #{additions.length} additions and #{removals.length} removals: #{e.message}\n#{e.backtrace.join("\n")}"
        end
      end
    end

  end
end
