# frozen_string_literal: true

RSpec.describe 'EmTools::Core::Rules filters' do
  describe EmTools::Core::Rules::BatteryFilter do
    it 'flags products that include batteries' do
      result = described_class.new.check(
        'attributes' => { 'batteries_included' => [{ 'value' => true }] }
      )
      expect(result).to include(passed: false, reason: '[IncludeBattery]')
    end

    it 'flags hazmat with lithium-ion description' do
      result = described_class.new.check(
        'attributes' => {
          'hazmat' => [{ 'aspect' => 'note', 'value' => 'Lithium ion batteries packed with equipment' }]
        }
      )
      expect(result).to include(passed: false, reason: '[IncludeBatteryHazmat]')
    end

    it 'passes plain products' do
      expect(described_class.new.check('attributes' => {})).to include(passed: true, reason: '')
    end
  end

  describe EmTools::Core::Rules::CategoryIdFilter do
    it 'blocks DE Lighters category' do
      product = {
        'identifiers' => [{ 'marketplaceId' => 'A1PA6795UKMFR9' }],
        'categories' => [{ 'cat_id' => '2970847031' }]
      }
      expect(described_class.new.check(product)).to include(
        passed: false,
        reason: '[CategoryIdBlocked:2970847031]'
      )
    end

    it 'lets unrelated categories pass' do
      product = {
        'identifiers' => [{ 'marketplaceId' => 'A1PA6795UKMFR9' }],
        'categories' => [{ 'cat_id' => '11111' }]
      }
      expect(described_class.new.check(product)).to include(passed: true)
    end
  end

  describe EmTools::Core::Rules::DimensionFilter do
    it 'blocks oversize package dimensions in cm' do
      product = {
        'item_package_dimensions' => {
          'width' => { 'value' => 50, 'unit' => 'centimeters' },
          'height' => { 'value' => 5, 'unit' => 'centimeters' },
          'length' => { 'value' => 5, 'unit' => 'centimeters' }
        }
      }
      result = described_class.new.check(product)
      expect(result[:passed]).to be(false)
      expect(result[:reason]).to eq('[OverSize]')
    end

    it 'passes products with no dimension data' do
      expect(described_class.new.check({})).to include(passed: true)
    end

    it 'respects custom dimension_max' do
      product = {
        'item_package_dimensions' => {
          'width' => { 'value' => 6, 'unit' => 'inches' },
          'height' => { 'value' => 1, 'unit' => 'inches' },
          'length' => { 'value' => 1, 'unit' => 'inches' }
        }
      }
      expect(described_class.new(dimension_max: 5).check(product)[:passed]).to be(false)
      expect(described_class.new(dimension_max: 12).check(product)[:passed]).to be(true)
    end
  end

  describe EmTools::Core::Rules::TitleKgKeywordFilter do
    it 'blocks 5 kg in titles' do
      expect(described_class.new.check('title' => 'Premium rice 5 kg bag'))
        .to include(passed: false, reason: '[TitleWeightKeyword:5kg]')
    end

    it 'passes titles without a 1-10 kg keyword' do
      expect(described_class.new.check('title' => 'Premium rice 500 g bag'))
        .to include(passed: true)
    end
  end

  describe EmTools::Core::Rules::TempSensitiveFilter do
    it 'blocks titles containing a temperature-sensitive keyword' do
      result = described_class.new.check('title' => 'Keep Frozen Salmon Fillet')
      expect(result[:passed]).to be(false)
      expect(result[:reason]).to start_with('[TempSensitiveTitle:')
    end
  end

  describe EmTools::Core::Rules::LighterFilter do
    it 'blocks lighter product types' do
      product = { 'productTypes' => [{ 'productType' => 'CIGARETTE_LIGHTER' }] }
      expect(described_class.new.check(product))
        .to include(passed: false, reason: '[LighterProductType:CIGARETTE_LIGHTER]')
    end
  end

  describe EmTools::Core::Rules::FlammableFilter do
    it 'blocks UN1987 alcohol shipments' do
      product = {
        'attributes' => {
          'hazmat' => [
            { 'aspect' => 'united_nations_regulatory_id', 'value' => 'UN1987' }
          ]
        }
      }
      expect(described_class.new.check(product))
        .to include(passed: false, reason: '[FlammableHazmat:UN1987]')
    end
  end

  describe EmTools::Core::Rules::PaintHazmatFilter do
    it 'flags paints with Class 3 hazmat' do
      product = {
        'attributes' => {
          'hazmat' => [
            { 'aspect' => 'proper_shipping_name', 'value' => 'PAINT, FLAMMABLE' },
            { 'aspect' => 'transportation_regulatory_class', 'value' => '3' }
          ]
        }
      }
      expect(described_class.new.check(product))
        .to include(passed: false, reason: '[HazmatPaint]')
    end
  end

  describe EmTools::Core::Rules::PaintFilter do
    it 'lets hair dyes through' do
      product = { 'title' => 'Permanent hair dye balayage paint kit' }
      expect(described_class.new.check(product)).to include(passed: true)
    end

    it 'blocks spray paint' do
      product = { 'title' => 'Spray paint primer for metal' }
      expect(described_class.new.check(product))
        .to include(passed: false, reason: '[RestrictedPaint]')
    end
  end

  describe EmTools::Core::Rules::FoamFilter do
    it 'blocks aerosol-context foam products' do
      product = {
        'title' => 'Foaming spray cleaner',
        'attributes' => { 'bullet_point' => [{ 'value' => 'pressurized aerosol can' }] }
      }
      expect(described_class.new.check(product))
        .to include(passed: false, reason: '[HazmatKeyword:foam]')
    end
  end

  describe EmTools::Core::Rules::FreshFoodFilter do
    it 'flags grocery website groups' do
      product = { 'summaries' => [{ 'websiteDisplayGroupName' => 'Grocery & Gourmet Food' }] }
      expect(described_class.new.check(product))
        .to include(passed: false, reason: '[FresFood]')
    end
  end

  describe EmTools::Core::Rules::FoodFilter do
    it 'blocks fresh-food product types when context matches' do
      product = {
        'productTypes' => [{ 'productType' => 'FISH' }],
        'categories' => [{ 'cat_name' => 'Fresh & Chilled' }]
      }
      expect(described_class.new.check(product))
        .to include(passed: false, reason: 'freshfood')
    end

    it 'does not block packaged groceries' do
      product = {
        'productTypes' => [{ 'productType' => 'GROCERY' }],
        'categories' => [{ 'cat_name' => 'Pantry Staples' }]
      }
      expect(described_class.new.check(product)).to include(passed: true)
    end
  end

  describe EmTools::Core::Rules::HazmatFilter do
    it 'blocks aerosol products by title keyword' do
      product = { 'title' => 'Body spray aerosol can' }
      expect(described_class.new.check(product))
        .to include(passed: false, reason: '[HazmatKeyword:aerosol]')
    end

    it 'lets benign products pass' do
      expect(described_class.new.check('title' => 'Plain wooden chair'))
        .to include(passed: true)
    end
  end
end
