module Maintenance
  class ListFilters
    include Muffin::SalsifyClient

    GROUPING_FILTER = '\'groupingType\':^*'.freeze
    IL_ELIGIBLE_FILTER = '\'il_eligible\':^\'true\''.freeze
    CATEGORY_ATTRIBUTE_FILTER = '\'Is Category Attribute?\':^\'true\''.freeze
    WEB_EXCLUSION_FILTER = 'list:^63394'.freeze

    def self.update
      new.update
    end

    def update
      update_filters
    end

    def update_filters
      lists.each do |list|
        il_eligible_filter = !has_filter?(list, IL_ELIGIBLE_FILTER)
        grouping_filter = !has_filter?(list, GROUPING_FILTER)
        category_attribute_filter = !has_filter?(list, CATEGORY_ATTRIBUTE_FILTER)
        web_exclusion_filter = !has_filter?(list, WEB_EXCLUSION_FILTER)
        next if il_eligible_filter && grouping_filter && category_attribute_filter && web_exclusion_filter
        puts "updating list id #{list.id}"
        begin
          if list.name != 'il-eligible-items'
            salsify_client.update_list(list.id, list_body(list, IL_ELIGIBLE_FILTER)) unless il_eligible_filter
            salsify_client.update_list(list.id, list_body(list, WEB_EXCLUSION_FILTER)) unless web_exclusion_filter
          end
          salsify_client.update_list(list.id, list_body(list, GROUPING_FILTER)) unless grouping_filter
          salsify_client.update_list(list.id, list_body(list, CATEGORY_ATTRIBUTE_FILTER)) unless category_attribute_filter
        rescue => error
          puts "error with list id #{list.id}"
          puts error
        end
      end
    end

    def has_filter?(list, filter)
      list.filter.split('=').delete_if { |filters| !filters.present? }.any? { |filters| !filters.include?(filter) }
    end

    def lists
      lazily_paginate('product', client: salsify_client, resource: :lists).to_a.delete_if do |list|
        SalsifyToDemandware::LISTS_TO_IGNORE.include?(list.name.strip)
      end
    end

    def list_body(list, new_filter)
      {
        'id' => list.id,
        'filter' => "#{list_filter(get_list(list.id), new_filter)}:product_type:root",
        'list_type' => 'smart',
        'entity_type' => 'product'
      }
    end

    def get_list(id)
      salsify_client.list(id).list.filter
    end

    def list_filter(filter, new_filter)
      updated_filter = filter.split('=').map.with_index do |set, index|
        if index == 0
          set
        else
          if set.include?(new_filter)
            "#{set}".gsub(':product_type:root', '')
          else
            "#{set},#{new_filter}".gsub(':product_type:root', '')
          end
        end
      end.join('=')
      updated_filter.empty? ? "=#{new_filter}" : updated_filter
    end

  end
end
