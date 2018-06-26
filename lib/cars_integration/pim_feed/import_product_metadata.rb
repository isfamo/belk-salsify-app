module PIMFeed
  class ImportProductMetadata
    include Muffin::SalsifyClient
    include Constants

    PROPERTIES = ([
      'product_id',
      'nrfColorCode',
      'omniChannelColorDescription',
      'refinementColor',
      'ImageAssetSource',
      'Color Master?',
      'All Images',
      'pim_nrfColorCode',
      GXS_DATA_RETRIEVED
    ] + ATTRIBUTES_TO_IGNORE).uniq.freeze

    def initialize(skus)
      @skus = skus
      @list_id = ENV['CARS_ENVIRONMENT'] == 'production' ? 78651 : 65222
      salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
    end

    def self.run(skus)
      new(skus).run
    end

    def run
      products
    end

    def products
      Stopwatch.time("$PIM IMPORT$ replacing list with #{@skus.count} products") { replace_list(@list_id, @skus) }
      run_response = salsify_client.create_export_run(export_run_filter)
      completed_response = Salsify::Utils::Export.wait_until_complete(salsify_client, run_response)
      Amadeus::Export::JsonExport.new(completed_response.url, performance_mode: true).products_hash
    end

    def export_run_filter
      {
        'configuration': {
          'entity_type': 'product',
          'format': 'json',
          'filter': "=list:#{@list_id}:product_type:all",
          'properties': "'#{PROPERTIES.join('\',\'')}'",
          'include_all_columns': false
        }
      }
    end

  end
end
