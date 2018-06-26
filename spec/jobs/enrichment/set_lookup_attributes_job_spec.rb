describe Enrichment::SetLookupAttributesJob do
  include_examples 'dictionary_inputs'

  before :each do
    allow_any_instance_of(Enrichment::SetLookupAttributesJob).to receive(:salsify_client) { nil }
    allow(job).to receive(:dictionary).and_return(dictionary)
  end

  describe 'product with all values' do
    let(:products) { JSON.parse(File.read('spec/jobs/enrichment/fixtures/product.json')) }
    let(:job) { Enrichment::SetLookupAttributesJob.new(products) }
    let(:expected_lookup_values) {
      {
        'Refinement SubSize' => ['S','M','XXL'],
        'omniSizeDesc' => '272982',
        'refinementSize' => ['L','XL','XXL'],
        'refinementColor' => 'brown'
      }
    }

    context self do
      it 'calcuates the correct values' do
        expect(job.enrichment_attributes(job.products.first)).to eq expected_lookup_values
      end
    end
  end

  describe 'parent with all values' do
    let(:products) { JSON.parse(File.read('spec/jobs/enrichment/fixtures/parent.json')) }
    let(:job) { Enrichment::SetLookupAttributesJob.new(products) }
    let(:expected_lookup_values) {
      {
        'iphCategory' => 'Women > Coats > Parka',
        'OmniChannel Brand' => nil
      }
    }

    context self do
      it 'calcuates the correct values' do
        expect(job.enrichment_attributes(job.products.first)).to eq expected_lookup_values
      end
    end
  end

  describe 'product with missing values' do
    let(:products) { JSON.parse(File.read('spec/jobs/enrichment/fixtures/product_with_missing_values.json')) }
    let(:job) { Enrichment::SetLookupAttributesJob.new(products) }
    let(:expected_lookup_values) {
      {
        'Refinement SubSize' => ['S','M','XXL'],
        'omniSizeDesc' => '272982',
        'refinementSize' => ['L','XL','XXL'],
        'refinementColor' => nil
      }
    }

    context self do
      it 'calcuates the correct values' do
        expect(job.enrichment_attributes(job.products.first)).to eq expected_lookup_values
      end
    end
  end

  describe 'product with duplicate values' do
    let(:products) { JSON.parse(File.read('spec/jobs/enrichment/fixtures/product_with_duplicate_values.json')) }
    let(:job) { Enrichment::SetLookupAttributesJob.new(products) }
    let(:expected_lookup_values) {
      {
        'Refinement SubSize' => ['S','M','XXL'],
        'omniSizeDesc' => '272982',
        'refinementSize' => ['L','XL','XXL'],
        'refinementColor' => nil
      }
    }

    context self do
      it 'calcuates the correct values' do
        expect(job.enrichment_attributes(job.products.first)).to eq expected_lookup_values
      end
    end
  end

end
