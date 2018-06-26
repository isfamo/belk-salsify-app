module Reporting
  class SalsifyToPimReport

    # Hit the database, get relevant records, iterate them and put into Excel - then Do Things with the Excel.

    HEADERS = ['Product ID', 'CarId', 'Status', 'API Push Type', 'Time (ET)']
    # the key of the DB row returned to use in this position - change the order of these if you want them in a diff col
    DATA_ORDER = %w(product_id car_id status push_type dtstamp)
    HEADER_FILL_COLOR = 'cccccc'.freeze
    WORKSHEET_NAME = 'Salsify-to-PIM Log'.freeze
    RECIPIENTS = ['ravi_kantamneni@belk.com','esmith@salsify.com', 'kgaughan@salsify.com']
    ORG_NAME = { '5041' => 'Belk QA', '5787' => 'Belk Prod'}

    # TODO: can make "build_yesterday", "build this week", "build last week", "build current month", etc

    # Right now this is the only one implemented at the rake level
    def self.build_report
      # Nothing will be older than 2017-01-01, so can use that as the date_from - doesn't have to be exact as it is so out of range
      # Use Right now as the date_to
      new.build_report_for_range(DateTime.parse('2017-01-01'), DateTime.now.in_time_zone('Eastern Time (US & Canada)'))
    end

    def self.build_report_up_to(date_to)
      # Nothing will be older than 2017-01-01, so can use that as the date_from
      # passed in the date_to
      new.build_report_for_range(DateTime.parse('2017-01-01'), date_to)
    end

    def self.build_report_for_range(date_from, date_to)
      new.build_report_for_range(date_from, date_to)
    end

    def self.build_week_back_from_today
      today = DateTime.now.in_time_zone('Eastern Time (US & Canada)')
      new.build_report_for_range(today - 7, today)
    end

    # ROW EXAMPLE:
    #   id: 2,
    #   product_id: "test_1",
    #   car_id: "car1",
    #   status: "status1",
    #   push_type: "type1",
    #   dtstamp: Fri, 22 Sep 2017 19:13:08 UTC +00:00,
    #   created_at: Fri, 22 Sep 2017 19:13:08 UTC +00:00,
    #   updated_at: Fri, 22 Sep 2017 19:13:08 UTC +00:00,
    #   org_id: -1

    def build_report_for_range(date_from, date_to)
      report_workbook = RubyXL::Workbook.new
      # auto gets a first sheet - but rename it
      worksheet = report_workbook[0]
      worksheet.sheet_name = WORKSHEET_NAME
      row_pos = 0
      # put in a header row
      HEADERS.each_with_index do |header_text, index|
        worksheet.add_cell(row_pos, index, header_text)
        # Make header row gray fill and bold text
        worksheet[row_pos][index].change_fill(HEADER_FILL_COLOR)
        worksheet[row_pos][index].change_font_bold(true)
      end
      row_pos += 1
      SalsifyToPimLog.where("dtstamp >= ? and dtstamp < ? and org_id = ?", date_from, date_to, ENV['CARS_ORG_ID'] ).each do |row|
        DATA_ORDER.each_with_index do |lookup_key, index|
          # puts "Row Pos: #{row_pos}, Index: #{index}, Lookup Key: #{lookup_key}, Row Val: #{row[lookup_key]}"
          worksheet.add_cell(row_pos, index, row[lookup_key])
        end
        row_pos += 1
      end
      file_name = "Salsify-to-PIM_Report_#{date_from.strftime("%Y-%m-%d")}_to_#{date_to.strftime("%Y-%m-%d")}"
      report_workbook.write("tmp/#{file_name}.xlsx")
      # TODO - add/replace delivery to internal Salsify reporting endpoint
      send_email(file_name)
    end

    def send_email(file_name)
      RRDonnelley::Mailer.send_mail(
        recipients: RECIPIENTS,
        subject: "#{ORG_NAME[ENV['CARS_ORG_ID']]} - Salsify-to-PIM Report - #{DateTime.now.in_time_zone('Eastern Time (US & Canada)').strftime('%Y-%m-%d')}",
        message: "Please see attachment for report.",
        attachment_local_paths: ["tmp/#{file_name}.xlsx"]
      )
    end


  end
end
