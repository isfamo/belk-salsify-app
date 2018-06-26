describe PIMFeed::Import do

  describe 'Delta Feed' do

    let(:pim_import) { PIMFeed::Import.new }
    let(:extracted_file) { 'spec/lib/cars_integration/pim_feed/fixtures/pim.xml' }
    let(:generated_output) { 'spec/lib/cars_integration/pim_feed/fixtures/generated_delta_import.json' }
    let(:generated_parent_output) { 'spec/lib/cars_integration/pim_feed/fixtures/generated_parent_import.json' }
    let(:expected_output) { 'spec/lib/cars_integration/pim_feed/fixtures/expected_delta_import.json' }
    let(:expected_parent_output) { 'spec/lib/cars_integration/pim_feed/fixtures/expected_parent_import.json' }
    let(:existing_products) { Amadeus::Export::JsonExport.new(JSON.parse(File.read('spec/lib/cars_integration/pim_feed/fixtures/existing_products.json')), performance_mode: true).products_hash }

    before :each do
      stub_const("PIMFeed::Import::FILE_LOCATION", generated_output)
      allow(pim_import).to receive(:extracted_files).and_return([extracted_file])
      allow(pim_import).to receive(:parent_file_location).and_return(generated_parent_output)
      allow(pim_import).to receive(:input_filepath).and_return(nil)
      allow(pim_import).to receive(:download_file_from_ftp).and_return(nil)
      allow(pim_import).to receive(:remote_filepath).and_return('placeholder')
      allow(pim_import).to receive(:unzip_file).and_return(nil)
      allow(pim_import).to receive(:run_salsify_import).and_return(nil)
      allow(pim_import).to receive(:archive_file_on_ftp).and_return(nil)
      allow_any_instance_of(PIMFeed::XMLParser).to receive(:existing_products).and_return(existing_products)
    end

    context self do
      it 'generates the correct Salsify JSON' do
        pim_import.run
        expect(JSON.parse(File.read(generated_output))).to eq JSON.parse(File.read(expected_output))
      end

      it 'generates the correct Salsify parent JSON' do
        pim_import.run
        expect(JSON.parse(File.read(generated_parent_output))).to eq JSON.parse(File.read(expected_parent_output))
      end
    end

  end

  describe 'Full Feed' do

    let(:pim_import) { PIMFeed::Import.new('placeholder', :full) }
    let(:extracted_file) { 'spec/lib/cars_integration/pim_feed/fixtures/pim.xml' }
    let(:generated_output) { 'spec/lib/cars_integration/pim_feed/fixtures/generated_full_import.json' }
    let(:expected_output) { 'spec/lib/cars_integration/pim_feed/fixtures/expected_full_import.json' }
    let(:generated_parent_output) { 'spec/lib/cars_integration/pim_feed/fixtures/generated_full_parent_import.json' }
    let(:expected_parent_output) { 'spec/lib/cars_integration/pim_feed/fixtures/expected_full_parent_import.json' }

    before :each do
      stub_const("PIMFeed::Import::FILE_LOCATION", generated_output)
      allow(pim_import).to receive(:file_location).and_return(generated_output)
      allow(pim_import).to receive(:parent_file_location).and_return(generated_parent_output)
      allow(pim_import).to receive(:extracted_files).and_return([extracted_file])
      allow(pim_import).to receive(:input_filepath).and_return(nil)
      allow(pim_import).to receive(:download_file_from_ftp).and_return(nil)
      allow(pim_import).to receive(:remote_filepath).and_return('placeholder')
      allow(pim_import).to receive(:unzip_file).and_return(nil)
      allow(pim_import).to receive(:run_salsify_import).and_return(nil)
      allow(pim_import).to receive(:archive_file_on_ftp).and_return(nil)
      allow(pim_import).to receive(:upload_import_file_to_salsify).and_return(nil)
      allow_any_instance_of(PIMFeed::XMLParser).to receive(:existing_products).and_return({})
    end

    context self do
      it 'generates the correct Salsify JSON' do
        pim_import.run
        expect(JSON.parse(File.read(generated_output))).to eq JSON.parse(File.read(expected_output))
      end

      it 'generates the correct Salsify parent JSON' do
        pim_import.run
        expect(JSON.parse(File.read(generated_parent_output))).to eq JSON.parse(File.read(expected_parent_output))
      end
    end

  end

end
