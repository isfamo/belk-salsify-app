require 'csv'
require 'thread'
require 'new_relic/agent'

class SalsifyToDemandware
  include Muffin::SalsifyClient
  include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

  # We may want this if we are not seeing exceptions surface due to the threads
  # Thread.abort_on_exception=true

  LISTS_TO_IGNORE = [
    'Is Category Attribute?',
    'Unorphaned Products',
    'Orphaned Products',
    'Parent to Variants On-Demand List',
    'Parent to Variants Incremental List',
    'web-exclusion-products'
  ].freeze
  ORG_ID = 3562

  attr_reader :cfh_execution, :list_name, :missing_category_metadata

  def initialize(cfh_execution, list_name = nil)
    @cfh_execution = cfh_execution
    @list_name = list_name
    @missing_category_metadata = []
    NewRelic::Agent.manual_start(sync_startup: true)
  end

  def self.export_category_hierarchy(cfh_execution)
    new(cfh_execution).export_category_hierarchy
  end

  def self.export_on_demand_category_hierarchy(cfh_execution, list_name)
    new(cfh_execution, list_name).export_on_demand_category_hierarchy
  end

  def self.export_category_products(cfh_execution)
    new(cfh_execution).export_all_categories
  end

  def self.export_offline_catagory_products(cfh_execution, offline_lists)
    new(cfh_execution).export_offline_categories(offline_lists)
  end

  def self.roll_up_products(cfh_execution)
    cfh_execution.salsify_sql_nodes.categories.where.not(parent_sid: 'root').each do |categ|
      threeshold = categ.data['product_rollup_threshold'].to_i
      next if threeshold == 0
      products = SalsifySqlNode.where(parent_sid: categ.sid, node_type: 'product')
      count = products.count
      if count < threeshold
        # puts "ROLL UP: Category: #{categ.sid}, Threeshold: #{threeshold}, Products Count: #{count}"
        products.update(parent_sid: categ.parent_sid)
        # puts "ROLL UP: Rolled up to #{categ.parent_sid}"
      end
    end
  end

  def export_category_hierarchy
    run_hierarchy_and_metadata_exports
    update_categories
  end

  def export_on_demand_category_hierarchy
    run_hierarchy_and_metadata_exports
    update_on_demand_categories
    export_on_demand_categories
  end

  def run_hierarchy_and_metadata_exports
    puts '$CFH SYNC$ Exporting CFH Hierarchy...'
    category_hierarchy
    puts '$CFH SYNC$ Exporting CFH Metadata...'
    category_metadata
  end

  def update_categories
    puts '$CFH SYNC$ Updating ALL categories...'
    lists.each { |list| update_category(list) }
  end

  def update_on_demand_categories
    puts '$CFH SYNC$ Updating On-Demand categories'
    on_demand_lists.each { |list| update_category(list) }
  end

  def update_category(list)
    categ = cfh_execution.salsify_sql_nodes.where(sid: list.name).first
    if categ.present? && list.id
      new_data = categ.data
      new_data['list_id'] = list.id
      categ.update(data: new_data)
    end
  end

  def export_all_categories
    puts '$CFH SYNC$ Exporting ALL categories...'
    export_categories(lists)
    CSV.open('missing_category_metadata.csv', 'w') do |csv|
      missing_category_metadata.each { |category| csv << [ category ] }
    end unless missing_category_metadata.empty?
  end

  def export_on_demand_categories
    puts "$CFH SYNC$ Exporting #{on_demand_lists.count} On-Demand category(s) -> #{on_demand_lists.map(&:name).join(', ')}"
    export_categories(on_demand_lists)
  end

  def export_offline_categories(offline_lists)
    puts "$CFH SYNC$ Exporting #{offline_lists.map(&:name).join(', ')} offline categories"
    export_categories(offline_lists)
  end

  # export EXPORT_THREADS lists at a time via ephemeral runs
  # The current want this works is that each export_category process takes in a specific list, and gets its own thread.
  # That means the list export gets triggered in that thread, and then that same thread waits until the export is done, and then acts on that list.
  # It technically may make more sense for a process to trigger all of the list exports so that they are queued in Salsify, and then the multi-threaded
  #   solution scans all of those looking for ones that have finished and pulling those in and processing them, pulling that out of the list of possible exports
  #   until that list is empty.
  # The downside of the above is that it would require significant refactoring of this code - the existing solution doesn't require much adjustment. This existing
  #   setup may benefit from higher thread counts. (the Heroku size=performance-l instance can handle over 32k threads - so we are not at risk of bumping into that
  #   at the relatively low counts we are dealing with).
  def export_categories(lists)
    puts "$CFH SYNC$ Starting export of lists using #{ENV['EXPORT_THREADS']} threads"
    # may want to put an or in there with the number, in case the value is not set in env it gets a default that way
    jobs = Queue.new
    lists.each { |list| jobs.push(list)}
    workers = (ENV['EXPORT_THREADS'].to_i).times.map do
      Thread.new do
        begin
            while list = jobs.pop(true)
              export_category(list)
            end
        rescue Exception => e
          # technically ThreadError here, but I think need the generic to catch here if I understand correctly
          puts "$CFH SYNC$ EXCEPTION: #{e.inspect}, MESSAGE: #{e.message}" unless e.message == 'queue empty'
        end
      end
    end
    workers.map(&:join)
  end

  def export_category(list)
    begin
      puts "publishing list #{list.name}"
      start_time = Time.now
      csv = PublishList.run(list.id, salsify_client(org_id: ORG_ID))
      return unless csv.present?
      rows = CSV.parse(csv)
      name = list.name.try(:remove, /[^[:print:]]/)
      puts "$CFH SYNC$ finished publishing list #{list.name} (took #{Time.now - start_time} seconds)"
      start_time = Time.now
      puts "$CFH SYNC$ processing list #{list.name} (#{rows.length} items)"
      category = SalsifySqlNode.find_by(sid: name, node_type: 'category', salsify_cfh_execution_id: cfh_execution.id)
      return unless category.data['online-flag']
      rows.each do |row|
        product_id = row.first
        next if product_id == 'product_id' # skip headers
        begin
          if product_id.present?
            data = {
              list_id: list.id,
              groupings: row[1].try(:force_encoding, 'UTF-8'),
              grouping_condition: category.data['grouping_condition']
            }
            SalsifySqlNode.create!(
              sid: product_id,
              parent_sid: name,
              node_type: 'product',
              salsify_cfh_execution_id: cfh_execution.id,
              data: data
            )
          end
        rescue => error
          puts "PRODUCT FATAL: #{error.class} #{error.message} #{product_id}"
        end
      end
      total_time = Time.now - start_time
      puts "$CFH SYNC$ finished processing list #{list.name} (#{'PROCESSING ALERT - ' if total_time > 100}took #{total_time} seconds)"
    rescue Exception => e
      missing_category_metadata << list.name
      # note there are instances where product_id will not be known here, so don't put it in the error message
      puts "$CFH SYNC$ Exception occured when exporting products - #{e.message} (List: #{list.name}"
    end
  end

  def category_hierarchy
    @category_hierarchy ||= CategoryHierarchy.run(salsify_client(org_id: ORG_ID), cfh_execution)
  end

  def category_metadata
    @category_metadata ||= CategoryMetadata.run(salsify_client(org_id: ORG_ID), cfh_execution)
  end

  # capture all category children with #select
  def on_demand_lists
    @on_demand_lists ||= lists.select { |list| list.name.include?(list_name) }
  end

  def lists
    @lists ||= lazily_paginate('product', client: salsify_client(org_id: ORG_ID), resource: :lists).map do |list|
      Hashie::Mash.new(id: list.id, name: list.name)
    end.delete_if { |list| LISTS_TO_IGNORE.include?(list.name.strip) }
  end

  add_transaction_tracer :export_category, :category => :task

  class PublishList < Struct.new(:list_id, :salsify_client)
    include SalsifyExportUtils

    PRODUCT_LIMIT = 500_000.freeze
    if ENV['SALSIFY_ENV'] == 'PROD'
      CHANNEL_ID = 50133.freeze # PROD
    else
      CHANNEL_ID = 50453.freeze # TEST
    end

    def self.run(list_id, salsify_client)
      new(list_id, salsify_client).run
    end

    # set the list_id as the product selection and publish channel.
    def run
      return unless list_product_count < PRODUCT_LIMIT
      begin
        ephemeral_run = salsify_client.create_ephemeral_run(CHANNEL_ID, ephemeral_run_body)
        response = Salsify::Utils::EphemeralRun.wait_until_complete(salsify_client, ephemeral_run, channel_id: CHANNEL_ID)
        open(response.product_export_url).read
      rescue => error
        puts "Category publishing error for #{list_name}: #{error.message} #{error.response}"
      end
    end

    def ephemeral_run_body
      { filter: "=list:#{list_id}:product_type:root" }
    end

    def list_product_count
      salsify_client.products_on_list(list_id).meta.total_entries
    end

    def list_name
      salsify_client.list(list_id).list.name
    end

  end

  class CategoryMetadata
    include SalsifyExportUtils

    attr_reader :salsify_client, :cfh_execution

    def initialize(salsify_client, cfh_execution = nil)
      @salsify_client = salsify_client
      @cfh_execution = cfh_execution
    end

    if ENV['SALSIFY_ENV'] == 'PROD'
      LIST_ID = 28755
    else
      LIST_ID = 28755
    end

    def self.run(salsify_client, cfh_execution)
      new(salsify_client, cfh_execution).run
    end

    def self.trigger_export(salsify_client)
      new(salsify_client).trigger_export
    end

    def run
      rows = trigger_export
      upsert_rows(rows)
    end

    def trigger_export
      begin
        response = salsify_client.create_export_run(export_body)
        completed_response = Salsify::Utils::Export.wait_until_complete(salsify_client, response)
        CSV.read(open(completed_response.url), headers: true)
      rescue RestClient::ResourceNotFound, RestClient::UnprocessableEntity => e
        puts "METADATA RUN FATAL: #{e.message} #{e.response}"
        return []
      end
    end

    def export_body
      {
        configuration: {
          entity_type: 'product',
          product_type: 'all',
          include_all_columns: true,
          filter: "=list:#{LIST_ID}",
          format: 'csv'
        }
      }
    end

    private

    def upsert_rows(rows)
      rows.each do |metadata|
        sid = metadata['product_id']
        row = SalsifySqlNode.find_or_initialize_by(sid: sid, salsify_cfh_execution_id: cfh_execution.id)

        online_flag = str_to_bool(metadata['online-flag'])
        row.data.merge!({
          'online-flag' => online_flag,
          'profile_asset_id' => metadata['salsify:profile_asset_id'],
          'product_rollup_threshold' => metadata['headerMenuBanner'],
          'grouping_condition' => metadata['grouping_condition'],
          'is_primary_category' => str_to_bool(metadata['is_primary_category']),
          'online_from' => dw_online_from(metadata['online_from']),
          'online_to' => dw_online_to(metadata['online_to']),
          'show_in_menu' => str_to_bool(metadata['showInMenu'])
        })
        begin
          if row.save
            # puts "METADATA UPDATE: CategoryId - #{sid}"
          elsif !row.persisted?
            @cfh_execution.cfh_execution_errors.create(category_id: sid, message: "Category Attributes is missing category")
            puts "METADATA ERROR: CategoryId - #{sid} not found"
          else
            puts "METADATA ERROR : CategoryId - #{sid} cannot be updated -  #{row.errors.full_messages.to_sentence}"
          end
        rescue Exception => e
          puts "METADATA FATAL: #{e.class} #{e.message} #{metadata}"
        end
      end
    end
  end

  class CategoryHierarchy
    include SalsifyExportUtils

    attr_reader :salsify_client, :cfh_execution

    def initialize(salsify_client, cfh_execution = nil)
      @salsify_client = salsify_client
      @cfh_execution = cfh_execution
    end

    def self.run(salsify_client, cfh_execution)
      new(salsify_client, cfh_execution).run
    end

    def self.trigger_export(salsify_client)
      new(salsify_client).trigger_export
    end

    def run
      rows = trigger_export
      upsert_rows(rows)
    end

    def export_run_body
      {
        configuration: {
          entity_type: 'attribute_value',
          format: 'csv',
          product_type: 'all'
        }
      }
    end

    def trigger_export
      begin
        run_response = salsify_client.create_export_run(export_run_body)
        completed_response = Salsify::Utils::Export.wait_until_complete(salsify_client, run_response)
        CSV.parse(open(completed_response.url).read)
      rescue RestClient::UnprocessableEntity => e
        puts "CATEGORY RUN FATAL: #{e.message} #{e.response}"
      end
    end

    def upsert_rows(rows)
      rows.each do |category|
        # Category Row Format - ["salsify:id", "salsify:name", "salsify:attribute_id", "salsify:parent_id"]
        row = SalsifySqlNode.find_or_initialize_by(sid: category[0].try(:strip), parent_sid: category[3].try(:strip), salsify_cfh_execution_id: cfh_execution.id)
        row.data = {
          'name' => category[1].try(:force_encoding, 'UTF-8').try(:strip),
          'attribute_id' => category[2].try(:force_encoding, 'UTF-8').try(:strip),
          'salsify:parent_id' => category[3].try(:strip)
        }
        begin
          if row.persisted? && row.save
            # puts "CATEGORY UPDATE: CategoryId - #{category[0]}"
          elsif row.save
            # puts "CATEGORY CREATE: CategoryId - #{category[0]}"
          else
            puts "CATEGORY ERROR : CategoryId - #{category[0]} cannot be created -  #{row.errors.full_messages.to_sentence}"
          end
        rescue Exception => e
          puts "CATEGORY FATAL: #{e.class} #{e.message} #{category}"
        end
      end
    end
  end
end
