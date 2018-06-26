class DirtyProductJob < Struct.new(:payload_alert_name, :payload)
  include Muffin::SalsifyClient

  DIRTY_ATTRIBUTE = 'salsify_cs:product_updated'.freeze # I like to think they're all dirty in their own way

  def perform
    # Lookup products that have this property map on them.
    payload[:events].each do |event|
      lookup_map = { event[:enumerated_value][:property][:external_id] => event[:previous][:external_id] }
      lazily_paginate(lookup_map, resource: :products_filtered_by, client: salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))).each do |product|
        # This is a timestamp but really could be anything unique (not sure how critical it is there to do the to_s)
        product[DIRTY_ATTRIBUTE] = Time.now.getutc.to_s
        begin
          salsify_client.update_product(product['salsify:id'], product)
        rescue
          puts "There was a problem trying to update product id '#{product['salsify:id']}'"
        end
      end
    end
  end

  # The Payload in looks like:
  # {
  #   organization: {
  #       id: organization_id, # system ID
  #       name: organization.name
  #   },
  #   events: [
  #     {
  #       trigger_type: 'change',
  #       enumerated_value: {
  #         id: enumerated_value.id, # system ID
  #         external_id: enumerated_value.external_id,
  #         created_at: enumerated_value.created_at,
  #         updated_at: enumerated_value.updated_at,
  #         destroyed_at: enumerated_value.destroyed_at, # nullable
  #         name: enumerated_value.name,
  #         parent: { # nullable
  #           id: enumerated_value.id, # system ID
  #           external_id: reference.external_id,
  #           type: 'enumerated_values'
  #         },
  #         property: {
  #           id: property.id, # system ID
  #           external_id: reference.external_id,
  #           type: 'properties'
  #         }
  #       },
  #       previous: {
  #         id: enumerated_value.id, # system ID
  #         external_id: enumerated_value.external_id,
  #         created_at: enumerated_value.created_at,
  #         updated_at: enumerated_value.updated_at,
  #         destroyed_at: enumerated_value.destroyed_at, # nullable
  #         name: enumerated_value.name,
  #         parent: { # nullable
  #           id: enumerated_value.id, # system ID
  #           external_id: reference.external_id,
  #           type: 'enumerated_values'
  #         },
  #         property: {
  #           id: property.id, # system ID
  #           external_id: reference.external_id,
  #           type: 'properties'
  #         }
  #       }
  #     }
  #   ]
  # }

end
