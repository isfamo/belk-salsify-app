class CMAOnDemandExportJob < Struct.new(:date, :filename)

  def perform
    ProcessCMAFeed.run(date, filename)
  end

end
