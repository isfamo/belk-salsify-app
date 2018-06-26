class EmailNotifier < Muffin::EmailNotifier
  include ErrorUtils

  FROM = 'solutions@salsify.com'.freeze
  CMA_FEED_TIMEZONE = 'Eastern Time (US & Canada)'.freeze
  EMAILS = [
    'pbreault@salsify.com',
    'kgaughan@salsify.com',
    'rahul_gopinath@belk.com',
    'IT_Ops_Apps@belk.com',
    'ESB_Support@belk.com',
    'ETL_Support@belk.com',
    'esmith@salsify.com',
    'lee@salsify.com',
    'lberlin@salsify.com'
  ].freeze

  def notify
    puts "sending notification email..."
    if mode == :pim_import
      postmark_client.deliver(
        from: FROM,
        to: EMAILS,
        subject: pim_import_subject,
        text_body: pim_import_body,
      )
    elsif mode == :cfh
      postmark_client.deliver(
        from: FROM,
        to: EMAILS,
        subject: cfh_subject,
        text_body: cfh_body,
      )
    elsif mode == :cma_feed
      postmark_client.deliver(
        from: FROM,
        to: EMAILS,
        subject: cma_feed_subject,
        text_body: cma_feed_body,
      )
    elsif mode == :color_feed
      postmark_client.deliver(
        from: FROM,
        to: EMAILS,
        subject: color_feed_subject,
        text_body: color_feed_body,
      )
    elsif mode == :inventory_feed
      postmark_client.deliver(
        from: FROM,
        to: EMAILS,
        subject: inventory_feed_subject,
        text_body: inventory_feed_body,
      )
    elsif mode == :offline
      postmark_client.deliver(
        from: FROM,
        to: EMAILS,
        subject: offline_feed_subject,
        text_body: offline_feed_body,
      )
    elsif mode == :cfh_on_demand
      postmark_client.deliver(
        from: FROM,
        to: email,
        subject: cfh_on_demand_export_subject,
        text_body: cfh_on_demand_export_subject,
        attachments: attachments
      )
    end
  end

  def pim_import_subject
    error ? "Errors encountered importing PIM Feed! Please contact Salsify" :
      "Salsify import of PIM feed finished successfully at #{completion_time}"
  end

  def pim_import_body
    error ? "Errors encountered importing PIM Feed: #{format_error(error)}" :
      "Salsify import of PIM feed finished successfully at #{completion_time}"
  end

  def cfh_subject
    error ? 'Errors encountered generating CFH XML! Please contact Salsify!' :
      "CFH XML feed successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def cfh_body
    error ? "Errors encountered generating CFH XML: #{format_error(error)}" :
      "CFH XML feed successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def cma_feed_subject
    error ? 'Errors encountered on CMA export! Please contact Salsify' :
      "CMA XML successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def cma_feed_body
    error ? "Errors encountered in CMA export: #{format_error(error)}" :
      "CMA XML successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def color_feed_subject
    error ? 'Errors encountered in Color Over Key export! Please contact Salsify' :
      "Color Over Key export successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def color_feed_body
    error ? "Errors encountered in Color Over Key export: #{format_error(error)}" :
      "Color Over Key export successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def inventory_feed_subject
    error ? 'Errors encountered in Inventory export! Please contact Salsify' :
      "Inventory export successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def inventory_feed_body
    error ? "Errors encountered in Inventory export: #{format_error(error)}" :
      "Inventory export successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def offline_feed_subject
    error ? 'Errors encountered in Offline CFH export! Please contact Salsify' :
      "Offline CFH export successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def offline_feed_body
    error ? "Errors encountered in Offline CFH export: #{format_error(error)}" :
      "Offline CFH export successfully generated and uploaded to Belk FTP at #{completion_time}"
  end

  def cfh_on_demand_export_subject
    "Belk Export for category: #{sid}"
  end

  def completion_time
    Time.now.in_time_zone(CMA_FEED_TIMEZONE).strftime('%I:%M:%S')
  end

  def attachments
    [
      {
        name: File.basename(cfh_on_demand_filename),
        content: [ File.read(cfh_on_demand_filename) ].pack('m'), content_type: 'xml'
      }
    ]
  end

end
