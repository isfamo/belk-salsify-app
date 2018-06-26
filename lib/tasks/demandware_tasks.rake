namespace :demandware do
  require_rel '../demandware_integration/**/*.rb'
  require_rel '../concerns/**/*.rb'

  # Manually record changes since 'hours_back' hours back from now
  # Optional arg is 'to_time' with format '2018-03-05 09:00:00 EST'
  task record_changes: :environment do
    start_datetime = ENV['to_time'] ? DateTime.parse(ENV['to_time']).utc.to_datetime : DateTime.now.utc.to_datetime
    if ENV['hours_back']
      since_datetime = (start_datetime - (ENV.fetch('hours_back').to_f / 24.0))
      record_changes(from: since_datetime, to: start_datetime)
    else
      since_datetime = pull_record_timestamp_from_s3
      if since_datetime
        record_changes(from: since_datetime, to: start_datetime)
      else
        puts "$DW RECORD$ ERROR unable to pull last record timestamp from S3!"
      end
    end
  end

  # Generate and send demandware feed which includes recorded
  # changes since 'hours_back' hours back from now, or uses
  # timestamp of last time dw feed was run.
  task send_feed: :environment do
    to_datetime = ENV['to_time'] ? DateTime.parse(ENV['to_time']).utc.to_datetime : DateTime.now.utc.to_datetime
    since_datetime = ENV['hours_back'] ? (to_datetime - (ENV['hours_back'].to_f / 24.0)) : pull_feed_timestamp_from_s3

    if since_datetime
      send_master_feed(from: since_datetime, to: to_datetime) if ENV['feed'].nil? || ENV['feed'] == 'master'
      send_limited_feed(from: since_datetime, to: to_datetime) if ENV['feed'].nil? || ENV['feed'] == 'limited'
    else
      puts "$DW FEED$ Unable to determine since_datetime, aborting!"
    end
  end

  task daemon: :environment do
    puts "$DW DAEMON$ Starting demandware feed daemon"

    first_run = true
    loop do
      from_dt = pull_daemon_timestamp_from_s3
      to_dt = DateTime.now.utc.to_datetime
      next_run_datetime = (from_dt + hours_between_daemon_feeds)
      wait_until(next_run_datetime) if first_run

      if from_dt
        t_start = Time.now

        puts "$DW DAEMON$ STARTING WINDOW: #{est(from_dt)} to #{est(to_dt)}"
        JobStatus.create(title: 'dwre_master', status: 'In Progress', activity: "Identifying modified products for range:\n#{from_dt.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')} to\n#{to_dt.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')}", start_time: DateTime.now.in_time_zone('UTC').strftime('%Y-%m-%d %H:%M:%S'))
        JobStatus.create(title: 'dwre_limited', status: 'In Progress', activity: "Identifying modified products for range:\n#{from_dt.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')} to\n#{to_dt.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')}", start_time: DateTime.now.in_time_zone('UTC').strftime('%Y-%m-%d %H:%M:%S'))

        smart_feed(from_dt: from_dt, to_dt: to_dt)

        puts "$DW DAEMON$ FINISHED WINDOW: #{est(from_dt)} to #{est(to_dt)} (took #{(((Time.now - t_start) / 60) / 60).round(1)} hours)"
        next_run_datetime = (to_dt + hours_between_daemon_feeds)
        first_run = false

        JobStatus.where(title: 'dwre_master').last.update_attributes(status: 'Finished Processing', activity: "Next run at #{next_run_datetime.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')}", end_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'))
        JobStatus.where(title: 'dwre_limited').last.update_attributes(status: 'Finished Processing', activity: "Next run at #{next_run_datetime.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')}", end_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'))
        wait_until(next_run_datetime)
      else
        puts "$DW DAEMON$ ERROR unable to pull last feed timestamp from S3!"
        return
      end
    end
  end

  task num_modified: :environment do
    to_dt = ENV['to_time'] ? DateTime.parse(ENV['to_time']).utc.to_datetime : DateTime.now.utc.to_datetime
    from_dt = (to_dt - (ENV['hours_back'].to_f / 24.0))
    num_updated_products = Demandware::DirtyFamiliesHelper.num_products_updated_in_range(since_datetime: from_dt, to_datetime: to_dt)
    puts "$DW DAEMON$ Quick check shows #{num_updated_products} updated products between #{est(from_dt)} and #{est(to_dt)}"
  end

  def smart_feed(from_dt:, to_dt:)
    timeframes = identify_timeframes(from: from_dt, to: to_dt)
    if timeframes.empty?
      puts "$DW DAEMON$ No products modified between #{est(from_dt)} and #{est(to_dt)}"
      puts "$DW DAEMON$ Updating daemon timestamp"
      update_daemon_timestamp(to_dt)
      return
    end

    puts "$DW DAEMON$ Identified #{timeframes.length} modified product windows for export. Timeframes are:\n#{timeframes.map { |tf| "[#{tf[:from].in_time_zone('America/New_York').to_s} => #{tf[:to].in_time_zone('America/New_York').to_s}]"}.join("\n")}"
    count = 0

    # Run first export
    puts "$DW DAEMON$ Recording changes from #{est(timeframes.first[:from])} to #{est(timeframes.first[:to])}"
    recorded_files = record_changes(from: timeframes.first[:from], to: timeframes.first[:to])
    puts "$DW DAEMON$ Finished recording changes from #{est(timeframes.first[:from])} to #{est(timeframes.first[:to])}, generated #{recorded_files.length} modified products json files"

    # Run export and feed for each timeframe, doing the export
    # for the next while we build the feed for the first
    while count < timeframes.length
      tf1, tf2 = timeframes[count..(count + 1)]
      filenames = recorded_files
      puts "$DW DAEMON$ SUB-WINDOW (#{count + 1}/#{timeframes.length}) | FEED: #{est(tf1[:from])} => #{est(tf1[:to])} | RECORD: #{tf2 ? "#{est(tf2[:from])} => #{est(tf2[:to])}" : "DONE!"}"

      [
        Thread.new {
          recorded_files = record_changes(from: tf2[:from], to: tf2[:to]) if tf2
        },
        Thread.new {
          send_all_feeds(from: tf1[:from], to: tf1[:to], filenames: filenames)
          update_daemon_timestamp(tf1[:to])
        }
      ].each { |th| th.join }

      count += 1
    end
  end

  # Take two DateTimes and create an array of sub-windows,
  # where each sub-window has number of modified products
  # below the configured threshold
  def identify_timeframes(from:, to:)
    num_updated_products = Demandware::DirtyFamiliesHelper.num_products_updated_in_range(since_datetime: from, to_datetime: to)
    puts "$DW DAEMON$ Quick check shows #{num_updated_products} updated products between #{from.in_time_zone('America/New_York').to_s} and #{to.in_time_zone('America/New_York').to_s}"
    if num_updated_products == 0
      []
    elsif num_updated_products > max_updated_products_per_window
      mid_dt = datetime_midpoint(from, to)
      [
        identify_timeframes(from: from, to: mid_dt),
        identify_timeframes(from: mid_dt, to: to)
      ].flatten
    else
      [{ from: from, to: to, num: num_updated_products }]
    end
  end

  def send_all_feeds(from:, to:, filenames:)
    from_s = from.in_time_zone('America/New_York').to_s
    to_s = to.in_time_zone('America/New_York').to_s
    puts "$DW DAEMON$ Sending demandware feed for products modified between #{from_s} and #{to_s}. Processing #{filenames.length} recorded json files."
    puts "$DW DAEMON$ Sending master belk.com feed"
    JobStatus.where(title: 'dwre_master').last.update_attributes(activity: "Generating xml for range:\n#{from.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')} to\n#{to.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')}")
    t = Time.now
    send_master_feed(from: from, to: to, options: { specific_files: filenames.to_s })
    puts "$DW DAEMON$ Sent master belk.com feed, took #{((Time.now - t) / 60).round(1)} minutes."
    JobStatus.where(title: 'dwre_master').last.update_attributes(activity: "Done generating xml for range:\n#{from.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')} to\n#{to.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')}")
    puts "$DW DAEMON$ Sending limited feed"
    JobStatus.where(title: 'dwre_limited').last.update_attributes(activity: "Generating xml for range:\n#{from.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')} to\n#{to.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')}")
    t = Time.now
    send_limited_feed(from: from, to: to, options: { specific_files: filenames.to_s })
    puts "$DW DAEMON$ Sent limited feed, took #{((Time.now - t) / 60).round(1)} minutes."
    JobStatus.where(title: 'dwre_limited').last.update_attributes(activity: "Done generating xml for range:\n#{from.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')} to\n#{to.in_time_zone('America/New_York').strftime('%Y-%m-%d %H:%M:%S %Z')}")
  end

  def record_changes(from:, to:)
    Demandware::DirtyFamiliesHelper.record_dirty_families(since_datetime: from, to_datetime: to)
  end

  def send_master_feed(from:, to:, options: {})
    Demandware::DwFeed.send_feed(since_datetime: from, to_datetime: to, options: send_feed_default_options.merge(options))
  end

  def send_limited_feed(from:, to:, options: {})
    Demandware::DwLimitedFeed.send_feed(since_datetime: from, to_datetime: to, options: send_feed_default_options.merge(options))
  end

  def send_feed_default_options
    {
      only_use_latest_export: ENV['only_use_latest_export'] == 'true',
      specific_files: ENV['specific_files'],
      specific_file_contains: ENV['specific_file_contains'],
      deliver_feed: ENV['deliver_feed'] == 'false' ? false : true,
      log_each_product: ENV['log_each_product'] == 'true' ? true : false,
      testing: ENV['testing'] == 'true' ? true : false,
      start_seq: ENV['start_seq']
    }
  end

  def hours_between_daemon_feeds
    (ENV.fetch('DW_HOURS_BETWEEN_SENDING_FEEDS').to_f / 24.0)
  end

  def max_updated_products_per_window
    ENV.fetch('DW_MAX_UPDATED_PRODUCTS_PER_WINDOW').to_i
  end

  def pull_record_timestamp_from_s3
    mode = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :qa
    s3_bucket = mode == :prod ? Demandware::S3_BUCKET_PROD : Demandware::S3_BUCKET_TEST
    s3_key = mode == :prod ? Demandware::S3_KEY_CHANGES_TIMESTAMP_PROD : Demandware::S3_KEY_CHANGES_TIMESTAMP_TEST
    timestamp_s3_object = Demandware::S3Helper.new.pull_from_s3(s3_bucket, s3_key)
    if timestamp_s3_object
      DateTime.parse(timestamp_s3_object.body.read)
    else
      puts "$DW RECORD$ No last record timestamp found on S3 at #{File.join(s3_bucket, s3_key)}! Needs to be like #{DateTime.now.to_s} (DateTime.now.to_s)"
      nil
    end
  end

  def pull_daemon_timestamp_from_s3
    mode = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :qa
    s3_bucket = mode == :prod ? Demandware::S3_BUCKET_PROD : Demandware::S3_BUCKET_TEST
    s3_key = mode == :prod ? Demandware::S3_KEY_DW_DAEMON_TIMESTAMP_PROD : Demandware::S3_KEY_DW_DAEMON_TIMESTAMP_TEST
    timestamp_s3_object = Demandware::S3Helper.new.pull_from_s3(s3_bucket, s3_key)
    if timestamp_s3_object
      DateTime.parse(timestamp_s3_object.body.read)
    else
      puts "$DW FEED$ No last dw feed timestamp found on S3 at #{File.join(s3_bucket, s3_key)}! Needs to be like #{DateTime.now.to_s} (DateTime.now.to_s)"
      nil
    end
  end

  def update_daemon_timestamp(datetime)
    mode = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :qa
    s3_bucket = mode == :prod ? Demandware::S3_BUCKET_PROD : Demandware::S3_BUCKET_TEST
    s3_key = mode == :prod ? Demandware::S3_KEY_DW_DAEMON_TIMESTAMP_PROD : Demandware::S3_KEY_DW_DAEMON_TIMESTAMP_TEST
    Demandware::S3Helper.new.upload_to_s3(s3_bucket, s3_key, datetime.to_s)
  end

  def pull_feed_timestamp_from_s3
    mode = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :qa
    s3_bucket = mode == :prod ? Demandware::S3_BUCKET_PROD : Demandware::S3_BUCKET_TEST
    s3_key = mode == :prod ? Demandware::S3_KEY_DW_FEED_TIMESTAMP_PROD : Demandware::S3_KEY_DW_FEED_TIMESTAMP_TEST
    timestamp_s3_object = Demandware::S3Helper.new.pull_from_s3(s3_bucket, s3_key)
    if timestamp_s3_object
      DateTime.parse(timestamp_s3_object.body.read)
    else
      puts "$DW FEED$ No last dw feed timestamp found on S3 at #{File.join(s3_bucket, s3_key)}! Needs to be like #{DateTime.now.to_s} (DateTime.now.to_s)"
      nil
    end
  end

  def update_feed_timestamp(datetime)
    mode = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :qa
    s3_bucket = mode == :prod ? Demandware::S3_BUCKET_PROD : Demandware::S3_BUCKET_TEST
    s3_key = mode == :prod ? Demandware::S3_KEY_DW_FEED_TIMESTAMP_PROD : Demandware::S3_KEY_DW_FEED_TIMESTAMP_TEST
    Demandware::S3Helper.new.upload_to_s3(s3_bucket, s3_key, datetime.to_s)
  end

  def wait_until(datetime)
    if DateTime.now < datetime
      secs_to_wait = (datetime.to_time - Time.now)
      puts "$DW DAEMON$ Waiting until #{datetime.to_s} for next run (#{(secs_to_wait / 60).round(1)} mins from now)"
      sleep secs_to_wait
    end
  end

  def datetime_midpoint(dt1, dt2)
    days_apart = (dt2 - dt1).to_f
    dt2 - (days_apart / 2)
  end

  def est(datetime)
    datetime.in_time_zone('America/New_York').to_s
  end

end
