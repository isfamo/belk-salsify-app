module Metrics
  class Lists
    include Muffin::SalsifyClient

    PRODUCT_COUNT_THRESHOLD = 100_000

    def self.find_outlier_lists
      new.find_outlier_lists
    end

    def self.count_all_products_on_lists
      new.count_all_products_on_lists
    end

    def self.find_broken_filters
      new.find_broken_filters
    end

    def self.compare_list_metadata_with_lists
      new.compare_list_metadata_with_lists
    end

    def compare_list_metadata_with_lists
      list_names = lists.map(&:name)
      defined_categories = SalsifyToDemandware::CategoryMetadata.trigger_export(salsify_client(org_id: 3562)).map { |category| category['product_id'] }
      missing_categories = list_names.map do |list_name|
        list_name if !defined_categories.include?(list_name)
      end.uniq.compact
      CSV.open('missing_category_metadata.csv', 'w') do |csv|
        missing_categories.each { |name| csv << [ name ] }
      end
    end

    def find_outlier_lists
      lists.each do |list|
        list = Hashie::Mash.new(id: list.id, name: list.name)
        list_total = salsify_client(org_id: 3562).products_on_list(list.id).meta.total_entries
        next if list_total < PRODUCT_COUNT_THRESHOLD
        puts "#{list_total} -- #{list.name}"
      end
    end

    def count_all_products_on_lists
      total = 0
      lists.each do |list|
        list = Hashie::Mash.new(id: list.id, name: list.name)
        list_total = salsify_client(org_id: 3562).products_on_list(list.id).meta.total_entries
        next if list_total > PRODUCT_COUNT_THRESHOLD
        puts "#{list_total} -- #{list.name}"
        total += list_total
      end
      puts total
    end

    def find_broken_filters
      lists.each do |list|
        filter = list.filter
        next unless filter
        next unless filter.count('=') > 1
        next unless filter.include?('display_name')
        list_total = salsify_client(org_id: 3562).products_on_list(list.id).meta.total_entries
        next unless list_total > 20_000
        puts "#{list.name} -- #{list_total} -- #{filter}"
      end
    end

    def lists
      lazily_paginate('product', client: salsify_client(org_id: 3562), resource: :lists).to_a
    end

  end
end
