# frozen_string_literal: true

RSpec.describe EmTools::Core::Rules::Registry do
  it 'lists all rule class names matching the available files' do
    expected = %w[
      BatteryFilter CategoryIdFilter DimensionFilter
      FlammableFilter FoamFilter FoodFilter FreshFoodFilter
      HazmatFilter LighterFilter PaintFilter PaintHazmatFilter
      TempSensitiveFilter TitleKgKeywordFilter
    ]

    expect(described_class.class_names).to match_array(expected)
  end

  it 'looks up a rule case-insensitively and instantiates it' do
    expect(described_class.lookup('batteryfilter')).to eq(EmTools::Core::Rules::BatteryFilter)
    expect(described_class.get('TitleKgKeywordFilter')).to be_a(EmTools::Core::Rules::TitleKgKeywordFilter)
  end

  it 'raises an UnknownRuleError for unregistered names' do
    expect { described_class.lookup('does_not_exist') }
      .to raise_error(EmTools::Core::Rules::Registry::UnknownRuleError)
  end

  it 'forwards constructor opts to rule classes that accept them' do
    instance = described_class.get('DimensionFilter', dimension_max: 4)
    expect(instance.instance_variable_get(:@dimension_max)).to eq(4)
  end

  it 'returns concrete rule instances from #all' do
    rules = described_class.all

    expect(rules.length).to eq(described_class.class_names.length)
    expect(rules).to all(be_a(EmTools::Core::Rules::Strategy))
  end
end
