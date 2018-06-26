module Metrics
  class LocateOrphanedProducts
    include Muffin::SalsifyClient

    LIST_ID = 47280

    def self.run
      new.run
    end

    def run
      jobs = Queue.new
      lists.each { |list| jobs.push(list)}
      4.times.map do
        Thread.new do
          begin
            while list = jobs.pop(true)
              export_list(list)
            end
          rescue Exception => e
            puts "EXCEPTION: #{e.inspect}, MESSAGE: #{e.message}" unless e.message == 'queue empty'
          end
        end
      end.map(&:join)
      update_list
    end

    def update_list
      puts "updating #{product_ids.to_a.count} products"
      product_ids.each_slice(100_000) do |ids|
        salsify_client.update_list(LIST_ID, list_filter(ids))
        with_retry { Salsify::Utils::List.wait_until_complete(salsify_client, LIST_ID) }
      end
    end

    def export_list(list)
      csv = publish_list(list)
      return unless csv.present?
      cache_product_ids(csv)
    end

    def list_filter(product_ids)
      { additions: { member_external_ids: product_ids.to_a } }
    end

    def publish_list(list)
      puts "publishing list #{list.name}"
      SalsifyToDemandware::PublishList.run(list.id, salsify_client(org_id: 3562))
    end

    def cache_product_ids(csv)
      CSV.parse(csv).each do |row|
        product_id = row.first
        next if product_id == 'product_id'
        product_ids << product_id
      end.compact.uniq
    end

    def product_ids
      @product_ids ||= Set.new
    end

    def lists
      @lists ||= lazily_paginate('product', client: salsify_client, resource: :lists).map do |list|
        Hashie::Mash.new(id: list.id, name: list.name)
      end.delete_if { |list| SalsifyToDemandware::LISTS_TO_IGNORE.include?(list.name.strip) }
    end

  end
end
