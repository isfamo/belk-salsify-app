require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module CustomerBelk
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/)
    config.eager_load_paths += %W(#{Rails.root}/lib/cars_integration/)
    config.eager_load_paths += %W(#{Rails.root}/lib/enrichment_integration)
    config.eager_load_paths += %W(#{Rails.root}/lib/demandware_integration/)
    config.eager_load_paths += %W(#{Rails.root}/lib/iph_mapping/)
    config.eager_load_paths += %W(#{Rails.root}/lib/rrd_integration/)
    config.eager_load_paths += %W(#{Rails.root}/lib/helpers/)
    config.eager_load_paths += %W(#{Rails.root}/lib/concerns/)
    config.eager_load_paths += %W(#{Rails.root}/lib/new_product_grouping/)

    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/cfh_feed)
    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/cma_feed)
    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/inventory_feed)
    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/color_code_feed)
    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/metrics)
    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/maintenance)
    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/helpers)
    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/concerns)
    config.eager_load_paths += %W(#{Rails.root}/lib/cfh_integration/jobs)

    config.eager_load_paths += %W(#{Rails.root}/lib/cars_integration/pim_feed)

    config.eager_load_paths += %W(#{Rails.root}/lib/enrichment_integration/enrichment)

    config.active_record.time_zone_aware_types = [:datetime, :time]

    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins '*'
        resource '*', :headers => :any, :methods => [:get, :post, :options]
      end
    end
  end
end
