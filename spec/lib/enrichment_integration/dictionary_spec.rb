require 'lib/enrichment_integration/dictionary_inputs'

describe Enrichment::Dictionary do
  include_examples 'dictionary_inputs'

  let(:expected_categories) {
    [
      { id: 'For the Home', name: 'For the Home', parent: '', mapping: 'For the Home///1111' },
      { id: 'For the Home > Bath', name: 'Bath', parent: 'For the Home', mapping: 'For the Home///1111///Bath' },
      { id: 'For the Home > Bath > Shiza', name: 'Shiza', parent: 'For the Home > Bath', mapping: 'For the Home///1111///Bath////Shiza' },
      { id: 'For the Home > Bath > Towels', name: 'Towels', parent: 'For the Home > Bath', mapping: 'For the Home///1111///Bath////Towels' },
      { id: 'Mens > Pants', name: 'Pants', parent: 'Mens', mapping: 'Mens///2222/Pants' }
    ]
  }

  let(:expected_category_tree) {
    {
      'For the Home' => ['For the Home > Bath', 'For the Home > Bath > Shiza', 'For the Home > Bath > Towels'],
      'For the Home > Bath' => ['For the Home > Bath > Shiza', 'For the Home > Bath > Towels'],
      'For the Home > Bath > Shiza' => [],
      'For the Home > Bath > Towels' => [],
      'Mens > Pants' => []
    }
  }

  context self do
    it 'responds to #dept_iph' do
      expect(dictionary.dept_iph('111','1110')).to eq nil
      expect(dictionary.dept_iph('113','1112')).to eq 'Women > Coats > Parka'
    end

    it 'responds to #omni_size' do
      expect(dictionary.omni_size('186','33904')).to eq '272981'
      expect(dictionary.omni_size('185','33904')).to eq nil
    end

    it 'responds to #refinement_size' do
      expect(dictionary.refinement_size('185','0')).to eq ['S','M','XXL']
      expect(dictionary.refinement_size('185','10')).to eq nil
    end

    it 'responds to #refinement_sub_size' do
      expect(dictionary.refinement_sub_size('185','0')).to eq ['S','M','XXL']
      expect(dictionary.refinement_sub_size('185','10')).to eq nil
    end

    it 'responds to #omni_color' do
      expect(dictionary.omni_color('015')).to eq '1'
    end

    it 'responds to #refinement_color' do
      expect(dictionary.refinement_color('015')).to eq 'blue'
    end

    it 'responds to #omni_brand' do
      expect(dictionary.omni_brand('10003999')).to eq '1'
    end

    it 'responds to #categories' do
      expect(dictionary.categories).to eq expected_categories
    end

    it 'responds to #category_tree' do
      expect(dictionary.category_tree).to eq expected_category_tree
    end

    it 'responds to category_mapping' do
      expect(dictionary.category_mapping['For the Home///1111///Bath']).to eq 'For the Home > Bath'
    end

  end

end
