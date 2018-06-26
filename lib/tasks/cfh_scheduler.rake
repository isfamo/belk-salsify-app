require 'csv'

TIMEZONE = 'Eastern Time (US & Canada)'.freeze

# e.g: rake cma:run[2016-11-11]
namespace :cma do
  task :run, [:date] => :environment do |t, args|
    today = Time.now.in_time_zone(TIMEZONE).to_date
    date = args[:date] ? Date.strptime(args[:date], '%Y-%m-%d') : today
    puts "$CMA$ running CMA Feed for today, #{date}"
    start = Time.now
    ProcessCMAFeed.run(date)
    puts "$CMA$ CMA process was completed in #{(Time.now - start) / 60} minutes"
  end

  task :import_pricing_feed, [:date] => :environment do |t, args|
    today = Time.now.in_time_zone(TIMEZONE).to_date
    date = args[:date] ? Date.strptime(args[:date], '%Y-%m-%d') : today
    puts "importing Pricing feed for today, #{date}"
    ProcessCMAFeed.import_pricing_feed(date)
  end

  task :generate_cma_feed, [:date] => :environment do |t, args|
    today = Time.now.in_time_zone(TIMEZONE).to_date
    date = args[:date] ? Date.strptime(args[:date], '%Y-%m-%d') : today
    puts "exporting cma feed for today, #{date}"
    ProcessCMAFeed.export_xml(date)
  end

  task :on_demand_run, [:filename] => :environment do |t, args|
    date = Date.today
    filename = args[:filename]
    return unless filename
    ProcessCMAFeed.run(date, filename)
  end
end

namespace :cfh do
  task sync: [:environment] do
    puts '$CFH SYNC$ running CFH synchronization (import and export)...'
    start = Time.now
    CFHSynchronization.run
    puts "$CFH SYNC$ CFH synchronization was completed in #{(Time.now - start) / 60} minutes"
  end

  # e.g: rake cfh:import[2017-02-06]
  task :import, [ :date ] => :environment do |t, args|
    today = Time.now.in_time_zone(TIMEZONE).to_date
    date = args[:date] ? Date.strptime(args[:date], '%Y-%m-%d') : today
    puts "running PIM import for today, #{date}"
    start = Time.now
    # this can take a second parameter of the filename to use, so could make a special version that we can tell specific files for one offs via rake
    PIMToSalsify.import_pim_feed(date, ENV['filename'])
    puts "XML Demandware file was generated in #{(Time.now - start) / 60} minutes"
  end

  task export: :environment do
    puts 'running export...'
    CFHSynchronization.generate_cfh_export
  end

  # e.g: rake cfh:manual_export[ 2,1 ]
  task :manual_export, [ :today_cfh_execution_id, :yesterday_cfh_execution_id ] => :environment do |t, args|
    puts "running export for cfh_execution_ids #{args[:today_cfh_execution_id]} and #{args[:yesterday_cfh_execution_id]}"
    cfh_exec_today = SalsifyCfhExecution.find(args[:today_cfh_execution_id])
    cfh_exec_yesterday = SalsifyCfhExecution.find(args[:yesterday_cfh_execution_id])
    OnDemandExport.run(cfh_exec_today, cfh_exec_yesterday)
  end

  task :generate_cfh_execution, [ :cfh_execution_id ] => :environment do |t, args|
    puts 'running...'
    cfh_exec_today = args[:cfh_execution_id] ? SalsifyCfhExecution.find(args[:cfh_execution_id]) :
      SalsifyCfhExecution.auto_today.first_or_create
    SalsifyToDemandware.export_category_hierarchy(cfh_exec_today)
    SalsifyToDemandware.export_category_products(cfh_exec_today)
    SalsifyToDemandware.roll_up_products(cfh_exec_today)
  end

end

namespace :clean do
  task database: [ :environment ] do
    days_to_retain = ENV['DAYS_TO_RETAIN'] || 4
    SalsifyCfhExecution.older_than(days_to_retain).each { |run| run.destroy_w_children }
    SalsifySqlNode.older_than(days_to_retain).delete_all
    CMAEvent.older_than(days_to_retain).delete_all
  end
end

task import_inventory: [ :environment ] do
  puts "running inventory import for today, #{Date.today}"
  ProcessInventoryFeed.run
  puts 'finished'
end

task run_offline_cfh_feed: :environment do
  OfflineCFHFeed.run
end

task purge_events: :environment do
  puts 'parsing csv...'
  skus = CSV.read('lib/cfh_integration/cache/skus_to_purge.csv').flatten
  puts 'fetching all events...'
  events = CMAEvent.where(sku_code: skus)
  puts 'removing events...'
  events.delete_all
end

task fetch_parents_from_salsify: [ :environment ] do
  puts 'running...'
  FetchParentsFromSalsify.run
end
