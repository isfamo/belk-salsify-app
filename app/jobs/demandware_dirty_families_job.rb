class DemandwareDirtyFamiliesJob < Struct.new(:hours_back_string)

  def perform
    @start_datetime = DateTime.now.utc.to_datetime
    puts "$DW RECORD REQ$ Demandware test publish job queued, looking for changes since #{since_datetime}"
    begin
      require_rel '../../lib/demandware_integration/**/*.rb'

      puts "$DW RECORD REQ$ Creating dirty families hash for test DW feed"
      Demandware::DirtyFamiliesHelper.record_dirty_families(
        to_datetime: @start_datetime,
        since_datetime: since_datetime,
        send_email_on_start: true
      )

      # Make sure we include the file being uploaded to S3
      sleep 3
      feed_start_datetime = DateTime.now.utc.to_datetime

      puts "$DW RECORD REQ$ Generating master feed"
      Demandware::DwFeed.send_feed(
        since_datetime: since_datetime,
        to_datetime: feed_start_datetime,
        options: {
          send_email_when_done: true
        }
      )

      puts "$DW RECORD REQ$ Generating LIMITED feed"
      Demandware::DwLimitedFeed.send_feed(
        since_datetime: since_datetime,
        to_datetime: feed_start_datetime,
        options: {
          send_email_when_done: true
        }
      )

    rescue Exception => e
      puts "$DW RECORD REQ$ ERROR while doing test Demandware feed: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end

  def last_record_timestamp
    @last_record_timestamp ||= begin
      mode = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :qa
      s3_bucket = mode == :prod ? Demandware::S3_BUCKET_PROD : Demandware::S3_BUCKET_TEST
      s3_key = mode == :prod ? Demandware::S3_KEY_CHANGES_TIMESTAMP_PROD : Demandware::S3_KEY_CHANGES_TIMESTAMP_TEST
      timestamp_s3_object = Demandware::S3Helper.new.pull_from_s3(s3_bucket, s3_key)
      if timestamp_s3_object
        DateTime.parse(timestamp_s3_object.body.read)
      else
        puts "$DW RECORD REQ$ No last record timestamp found on S3 at #{File.join(s3_bucket, s3_key)}! Needs to be like #{DateTime.now.to_s} (DateTime.now.to_s)"
        nil
      end
    end
  end

  def since_datetime
    @since_datetime ||= begin
      if hours_back_string
        (@start_datetime - (hours_back_string.to_f / 24.0))
      elsif last_record_timestamp
        last_record_timestamp
      else
        nil
      end
    end
  end

end
