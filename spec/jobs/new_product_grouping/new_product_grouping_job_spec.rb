describe NewProductWorkflow do

  # Commenting out to pass circle

  before :each do
    GroupingId.create!(sequence: 1171100)
    allow(worker).to receive(:update_product_id).and_return(nil)
    allow(worker).to receive(:update_included_in_grouping_links).and_return(nil)
    allow(worker).to receive(:client).and_return(nil)
    stub_const("NewProductWorkflow::Worker::ORG_ID", "5041")
  end

  describe 'Builds import with correct autp-generated ids' do
    let(:new_products) { JSON.parse(File.read('spec/jobs/new_product_grouping/fixtures/products.json')) }
    let(:worker) { NewProductWorkflow::Worker.new(new_products) }
    let(:expected_groupings) { ["99999991171100", "99999991171101"] }

    context 'Logic Works' do
      it 'Generates the correct Ids' do
        generated_groupings = []
        new_products.each do |product|
          generated_groupings << worker.generate_grouping(product)
        end
        expect(generated_groupings).to eq(expected_groupings)
      end
    end

    context 'Runs without errors' do
      it 'Runs the entire class with nor errors' do
        worker.run
      end
    end
  end

end
