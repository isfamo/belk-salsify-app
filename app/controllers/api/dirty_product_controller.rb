require 'json'

class Api::DirtyProductController < ApplicationController
  protect_from_forgery prepend: true

  NEWLINE = "\n".freeze

  # POST /api/dirty_product
  def dirty_product
    # Once we see the webhook come through, maybe there is relevant data we care about - for now just show triggering.
    puts "dirty_product webhook alert"

    Delayed::Job.enqueue(DirtyProductJob.new('Dirty Product', params))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in DirtyProductController#send_to_pim:\n Message: #{e.message}\n#{e.backtrace.join(NEWLINE)}"
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
