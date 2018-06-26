require_rel '../helpers/salsify_filter.rb'
module Groupings
  class GroupingHandler
    include Muffin::SalsifyClient

    STAMP = '$GROUPINGS$'.freeze
    PROPERTY_CHILD_STYLES = 'styles'.freeze
    PROPERTY_CHILD_SKUS = 'skus'.freeze
    PROPERTY_INCLUDED_IN_GROUPINGS = 'Included in Groupings'.freeze
    IMPORT_FILEPATH = 'tmp/groupings/groupings_updated_import.json'.freeze
    URL_TEMPLATE = 'https://app.salsify.com/app/orgs/{{org_system_id}}/products/{{product_id}}'.freeze
    MAX_IDS_PER_CRUD = 100.freeze
    MAX_URLS_PER_FILTER = 10.freeze

    attr_reader :products

    def initialize(products)
      @products = products
    end

    def self.new_groupings(products)
      new(products).new_groupings
    end

    def self.removed_groupings(products)
      new(products).removed_groupings
    end

    def self.modified_groupings(products)
      new(products).modified_groupings
    end

    def new_groupings
      updates_by_id = {}

      # Find all children pointed to by the new groupings
      all_children = get_products_crud(child_ids_by_grouping_id.values.flatten.uniq)
      puts "#{STAMP} Identified #{all_children.length} styles/skus referenced by the #{products.length} new groupings"

      all_children.each do |child_product|
        # Add any relevant new grouping URLs to the child's referenced parent groupings
        referenced_grouping_urls = [
          child_product[PROPERTY_INCLUDED_IN_GROUPINGS],
          child_ids_by_grouping_id.select { |grouping_id, child_ids|
            child_ids.include?(child_product['salsify:id'])
          }.keys.map { |grouping_id| url_from_id(grouping_id) }
        ].flatten.compact.uniq

        # Update the child with referenced groupings
        updates_by_id[child_product['salsify:id']] = { PROPERTY_INCLUDED_IN_GROUPINGS => referenced_grouping_urls }
      end
      perform_updates(updates_by_id)
      puts "#{STAMP} Done handling new groupings!"
    end

    def removed_groupings
      updates_by_id = {}

      # Find all children pointed to by the removed groupings
      all_children = get_products_crud(child_ids_by_grouping_id.values.flatten.uniq)
      puts "#{STAMP} Identified #{all_children.length} styles/skus referenced by the #{products.length} removed groupings"

      all_children.each do |child_product|
        next unless child_product[PROPERTY_INCLUDED_IN_GROUPINGS]

        # Remove any of the deleted grouping IDs from the child's referenced parent groupings
        remaining_grouping_urls = [child_product[PROPERTY_INCLUDED_IN_GROUPINGS]].flatten.reject do |grouping_url|
          child_ids_by_grouping_id[id_from_url(grouping_url)]
        end

        # Update the child with remaining groupings
        updates_by_id[child_product['salsify:id']] = { PROPERTY_INCLUDED_IN_GROUPINGS => remaining_grouping_urls }
      end
      perform_updates(updates_by_id)
      puts "#{STAMP} Done handling removed groupings!"
    end

    def modified_groupings
      updates_by_id = {}

      # Find all children pointing to these groupings
      puts "#{STAMP} Searching for alleged children of #{products.length} modified grouping products"
      alleged_child_by_id = find_alleged_children(child_ids_by_grouping_id.keys).map { |ac| [ac['salsify:id'], ac] }.to_h

      # Find all children acknowledged by these groupings
      puts "#{STAMP} Searching for acknowledged children of #{products.length} modified grouping products"
      acknowledged_children_by_id = get_products_crud(child_ids_by_grouping_id.values.flatten.uniq).map { |ac| [ac['salsify:id'], ac] }.to_h

      puts "#{STAMP} Identifying disowned and adopted children for each grouping"
      disowned_child_ids_by_grouping_id = child_ids_by_grouping_id.map do |grouping_id, acked_child_ids|
        grouping_url = url_from_id(grouping_id)
        [grouping_id, alleged_child_by_id.select { |alleged_child_id, alleged_child|
          [alleged_child[PROPERTY_INCLUDED_IN_GROUPINGS]].flatten.compact.include?(grouping_url) &&
          !acked_child_ids.include?(alleged_child_id)
        }.keys]
      end.to_h

      adopted_child_ids_by_grouping_id = child_ids_by_grouping_id.map do |grouping_id, acked_child_ids|
        grouping_url = url_from_id(grouping_id)
        [grouping_id, acknowledged_children_by_id.select { |acked_child_id, acked_child|
          ![acked_child[PROPERTY_INCLUDED_IN_GROUPINGS]].flatten.compact.include?(grouping_url) &&
          acked_child_ids.include?(acked_child_id)
        }.keys]
      end.to_h

      disowned_child_ids_by_grouping_id.each do |grouping_id, disowned_child_ids|
        grouping_url = url_from_id(grouping_id)
        disowned_child_ids.each do |disowned_child_id|
          if updates_by_id[disowned_child_id]
            alleged_parent_ids = [updates_by_id[disowned_child_id][PROPERTY_INCLUDED_IN_GROUPINGS]].flatten.compact
          else
            alleged_parent_ids = [alleged_child_by_id[disowned_child_id][PROPERTY_INCLUDED_IN_GROUPINGS]].flatten.compact
          end
          updates_by_id[disowned_child_id] = { PROPERTY_INCLUDED_IN_GROUPINGS => alleged_parent_ids - [grouping_url] }
        end
      end

      adopted_child_ids_by_grouping_id.each do |grouping_id, adopted_child_ids|
        grouping_url = url_from_id(grouping_id)
        adopted_child_ids.each do |adopted_child_id|
          adopted_child = acknowledged_children_by_id[adopted_child_id]
          if updates_by_id[adopted_child_id]
            alleged_parent_ids = [updates_by_id[adopted_child_id][PROPERTY_INCLUDED_IN_GROUPINGS]].flatten.compact
          else
            alleged_parent_ids = [adopted_child[PROPERTY_INCLUDED_IN_GROUPINGS]].flatten.compact
          end
          updates_by_id[adopted_child_id] = { PROPERTY_INCLUDED_IN_GROUPINGS => alleged_parent_ids.concat([grouping_url]).uniq }
        end
      end

      updates_by_id.each do |product_id, update_hash|
        update_hash[PROPERTY_INCLUDED_IN_GROUPINGS] = nil if update_hash[PROPERTY_INCLUDED_IN_GROUPINGS].empty?
      end

      perform_updates(updates_by_id)
      puts "#{STAMP} Done handling new groupings!"
    end

    def perform_updates(updates_by_id)
      return if updates_by_id.empty?
      puts "#{STAMP} Starting import #{import_id} for #{updates_by_id.length} products"
      SalsifyImport.import_products(
        updates_by_id.map { |product_id, update_hash|
          update_hash.merge({ product_id_property => product_id })
        },
        client,
        import_id,
        product_id_property,
        IMPORT_FILEPATH
      )
      puts "#{STAMP} Finished import"
    end

    def grouping_by_id
      @grouping_by_id ||= products.map { |id, product| [id, product] }.to_h
    end

    def child_ids_by_grouping_id
      @child_ids_by_grouping_id ||= products.map do |product|
        [
          product['salsify:id'],
          [product[PROPERTY_CHILD_STYLES], product[PROPERTY_CHILD_SKUS]].flatten.compact.uniq
        ]
      end.to_h
    end

    def get_products_crud(product_ids)
      product_ids.each_slice(MAX_IDS_PER_CRUD).map do |product_id_batch|
        client.products(product_id_batch)
      end.flatten
    end

    def find_alleged_children(grouping_ids)
      filter_strings = grouping_ids.map do |grouping_id|
        url_from_id(grouping_id)
      end.each_slice(MAX_URLS_PER_FILTER).map do |grouping_url_batch|
        "='#{PROPERTY_INCLUDED_IN_GROUPINGS}':{#{grouping_url_batch.map { |url| "'#{url}'" }.join(',')}}:product_type:all"
      end
      filter_strings.map do |filter_string|
        filter.filter(filter_string: filter_string, selections: [PROPERTY_INCLUDED_IN_GROUPINGS])
      end.flatten
    end

    def url_from_id(product_id)
      URL_TEMPLATE.gsub('{{org_system_id}}', org_system_id).gsub('{{product_id}}', product_id)
    end

    def id_from_url(url)
      i = url.index('?')
      url = url[0..(i-1)] if i
      match = url.match(/^.+\/products\/(.+)$/)
      match ? match[1] : nil
    end

    def org_system_id
      @org_system_id ||= ENV.fetch('CARS_ORG_SYSTEM_ID')
    end

    def filter
      @filter ||= SalsifyFilter.new(client)
    end

    def client
      @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID').to_i)
    end

    def import_id
      @import_id ||= ENV.fetch('GROUPINGS_UPDATE_IMPORT_ID').to_i
    end

    def product_id_property
      @product_id_property ||= lazily_paginate(client: client, resource: :properties).find do |property|
        property['role'] == 'product_id'
      end['id']
    end

  end
end
