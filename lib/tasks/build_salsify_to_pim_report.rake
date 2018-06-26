require_rel '../reporting/**/*.rb'
# Piggyback on the mailer that this uses
require_rel '../rrd_integration/**/*.rb'

task build_report: :environment do
  Reporting::SalsifyToPimReport.build_report
end

task build_report_back_to_last_week_from_today: :environment do
  Reporting::SalsifyToPimReport.build_week_back_from_today
end
