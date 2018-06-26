# e.g: rake cars:run_pim_import['filename']
namespace :cars do
  task :run_pim_import, [:ftp_filename, :mode] => :environment do |t, args|
    ftp_filename = args[:ftp_filename]
    mode = args[:mode].try(:to_sym)
    puts "running import for #{ftp_filename} in mode #{mode}..."
    PIMFeed::Import.run(ftp_filename: ftp_filename, mode: mode)
  end

  task automated_pim_import: :environment do
    puts '$PIM IMPORT$ listening to CARS FTP for PIM import file...'
    loop do
      PIMFeed::Import.run
      sleep 60
    end
  end

  task run_pim_attribute_import: :environment do
    PIMFeed::AttributeImport.run
  end

  task check_for_pim_file_ftp_backups: :environment do
    Maintenance::CheckForPimFileFtpBackups.run
  end

  task delayed_job_alert_daemon: :environment do
    calm_interval = ENV.fetch('calm_interval').to_i
    alert_interval = ENV.fetch('alert_interval').to_i
    warning_threshold = ENV.fetch('warning_threshold').to_i

    loop do
      queue_size = Delayed::Job.count
      if queue_size >= warning_threshold
        SlackClient.send_queue_alarm(queue_size)
        puts "$DELAYED JOB ALARM$ Alerting slack channel of queue size of #{queue_size}, sleeping #{(alert_interval / 60).round(1)} minutes"
        sleep alert_interval
      else
        sleep calm_interval
      end
    end
  end

  task process_new_skus: :environment do
    SkusCreated.process_new_skus
  end

  task process_converted_il_skus: :environment do
    IlSkusConverted.process_converted_il_skus
  end

end

# full feed example: heroku run:detached rake cars:run_pim_import['Product_CARCreate_Full_20170711_1532_3.tar.gz','full'] --size=performance-l
