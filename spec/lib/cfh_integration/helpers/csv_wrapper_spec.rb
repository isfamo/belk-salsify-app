require "csv"

describe CustomCSV::Wrapper do
  before(:all) do
    @file_name = "/tmp/cma_feed_v1.csv"

    CSV.open(@file_name, "wb") do |csv|
      CSV_DOC_V1.each {|row| csv << row}
    end
  end

  context '#initialize' do
    it 'should initialize an object correctly' do
      obj = CustomCSV::Wrapper.new(@file_name)
      expect(obj).to be_an_instance_of(CustomCSV::Wrapper)
    end

    it 'should raise exception if file is missing' do
      expect {
        CustomCSV::Wrapper.new(@file_name + "1")
      }.to raise_error(CustomCSV::MissingFileError)
    end
  end

  context '#foreach' do
    before(:each) do
      @obj = CustomCSV::Wrapper.new(@file_name)
    end

    it 'should yield the rows without the headers' do
      @obj.foreach { |x| expect(x[:skucode]).to be_present}
    end
  end

  # after(:all) do
  #   File.delete(@file_name)
  # end
end
