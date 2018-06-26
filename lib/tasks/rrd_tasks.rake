namespace :rrd do
  require_rel '../rrd_integration/**/*.rb'
  require_rel '../concerns/**/*.rb'
  require_rel '../image_management/**/*.rb'

  task unsent_assets: :environment do
    ImageManagement::ImageTransfer.send_unsent_assets
  end

  task :image_feed => :environment do
    # Send newly uploaded/linked images to RRD FTP
    # Notify them via xml and excel files
    RRDonnelley::RRDConnector.send_asset_feed_to_rrd

    # Notify RRD of deleted images via xml and excel
    RRDonnelley::RRDConnector.send_deleted_asset_feed_to_rrd

    # Check RRD for image responses (pass/fail various checks)
    # Append responses on the digital assets in Salsify
    RRDonnelley::RRDConnector.check_rrd_for_processed_assets

    # Check RRD for image history files indicating images which have passed and been sent to Belk
    # If all images for a product have passed, generate a task ID and add it to the product
    RRDonnelley::RRDConnector.process_rrd_vendor_image_histories

    # Send sample requests to RRD and catalog requests in db
    RRDonnelley::RRDConnector.send_sample_requests_to_rrd

    # Check RRD for sample history files indicating samples which have been processed
    #
    RRDonnelley::RRDConnector.check_rrd_for_processed_samples
  end

  task :send_asset_feed_to_rrd => :environment do
    RRDonnelley::RRDConnector.send_asset_feed_to_rrd
  end

  task :send_deleted_asset_feed_to_rrd => :environment do
    RRDonnelley::RRDConnector.send_deleted_asset_feed_to_rrd
  end

  task :check_rrd_for_processed_assets => :environment do
    RRDonnelley::RRDConnector.check_rrd_for_processed_assets
  end

  task :process_rrd_vendor_image_histories => :environment do
    RRDonnelley::RRDConnector.process_rrd_vendor_image_histories
  end

  task :send_sample_requests_to_rrd => :environment do
    RRDonnelley::RRDConnector.send_sample_requests_to_rrd
  end

  task :check_rrd_for_processed_samples => :environment do
    RRDonnelley::RRDConnector.check_rrd_for_processed_samples
  end

  task :send_belk_hex_feed => :environment do
    RRDonnelley::RRDConnector.send_belk_hex_feed
  end

  task :pull_belk_ads_feed => :environment do
    RRDonnelley::RRDConnector.pull_belk_ads_feed
  end

  task :automated_ads_import => :environment do
    sleep_time = ENV['ADS_DAEMON_SLEEP_MINS'] ? ENV.fetch('ADS_DAEMON_SLEEP_MINS').to_i : 15
    loop do
      puts '$ADS$ Checking Belk FTP for ADS files...'
      RRDonnelley::RRDConnector.pull_belk_ads_feed
      puts "$ADS$ Sleeping for #{sleep_time} minutes..."
      sleep 60 * sleep_time
    end
  end

  task :identify_skus => :environment do
    RRDonnelley::RRDConnector.identify_skus
  end

  # rake rrd:process_belk_department_emails input='./lib/rrd_integration/cache/belk_email_groups_prod.csv' output='./lib/rrd_integration/cache/belk_email_groups_prod.json'
  task :process_belk_department_emails => :environment do
    RRDonnelley::RRDConnector.process_belk_department_emails(ENV.fetch('input'), ENV.fetch('output'))
  end

  task :process_all_image_metadata => :environment do
    RRDonnelley::RRDConnector.process_image_metadata_for_products_with_assets
  end

  task :process_image_metadata_for_product_ids => :environment do
    RRDonnelley::RRDConnector.process_image_metadata_for_product_ids(JSON.parse(ENV.fetch('product_ids')))
  end

  task :process_image_metadata_for_assets_with_empty_metadata => :environment do
    RRDonnelley::RRDConnector.process_image_metadata_for_assets_with_empty_metadata
  end

  task :identify_assets_with_invalid_rrd_id => :environment do
    RRDonnelley::RRDConnector.identify_assets_with_invalid_rrd_id
  end

  # bundle exec rake rrd:import_foreign_image_ids filepath='./path/to/my/file.xlsx'
  task :import_foreign_image_ids => :environment do
    RRDonnelley::ImportVendorImageIds.import_foreign_image_ids(ENV.fetch('filepath'))
  end

  # bundle exec rake rrd:import_foreign_sample_reqs filepath='./path/to/my/file.xlsx'
  task :import_foreign_sample_reqs => :environment do
    RRDonnelley::ImportSampleReqs.import_foreign_sample_reqs(ENV.fetch('filepath'))
  end

  task :update_products_for_sample_reqs => :environment do
    RRDonnelley::ImportSampleReqs.update_products_for_sample_reqs
  end

  task :connect => :environment do
    RRDonnelley::RRDConnector.connect
  end

  task :identify_products_for_asset_ids => :environment do
    RRDonnelley::RRDConnector.identify_products_for_asset_ids
  end

  task :adjust_image_metadata_from_csv => :environment do
    RRDonnelley::RRDConnector.adjust_image_metadata_from_csv
  end
end
