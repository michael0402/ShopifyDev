# ================================ Customizable Settings ================================
# ================================================================
# Hide Rate(s) for Product/Country
#
# If the cart contains any matching items, and we have a matching
# country, the entered rate(s) are hidden.
#
#   - 'product_selector_match_type' determines whether we look for
#     products that do or don't match the entered selectors. Can
#     be:
#       - ':include' to check if the product does match
#       - ':exclude' to make sure the product doesn't match
#   - 'product_selector_type' determines how eligible products
#     will be identified. Can be either:
#       - ':tag' to find products by tag
#       - ':type' to find products by type
#       - ':vendor' to find products by vendor
#       - ':product_id' to find products by ID
#       - ':variant_id' to find products by variant ID
#       - ':subscription' to find subscription products
#   - 'product_selectors' is a list of tags or IDs to identify
#     associated products
#   - 'country_code_match_type' determines whether we look for
#     countries that do, or don't, match the entered options, or
#     all countries. Can be:
#       - ':include' to look for countries that DO match
#       - ':exclude' to look for countries that DO NOT match
#       - ':all' to look for all countries
#   - 'country_codes' is a list of country code abbreviations
#     - ie. United States would be `US`
#   - 'rate_match_type' determines whether the below strings
#     should be an exact or partial match. Can be:
#       - ':exact' for an exact match
#       - ':partial' for a partial match
#       - ':all' for all rates
#   - 'rate_names' is a list of strings to identify rates
#     - if using ':all' above, this can be set to 'nil'
# ================================================================
HIDE_RATES_FOR_PRODUCT_AND_COUNTRY = [
  {
    product_selector_match_type: :include,
    product_selector_type: :product_id,
    product_selectors: [1234567890987, 1234567890986],
    country_code_match_type: :include,
    country_codes: ["CA"],
    rate_match_type: :exact,
    rate_names: ["Shipping Rate"],
  },
]

# ================================ Script Code (do not edit) ================================
# ================================================================
# ProductSelector
#
# Finds matching products by the entered criteria.
# ================================================================
class ProductSelector
  def initialize(match_type, selector_type, selectors)
    @match_type = match_type
    @comparator = match_type == :include ? 'any?' : 'none?'
    @selector_type = selector_type
    @selectors = selectors
  end

  def match?(line_item)
    if self.respond_to?(@selector_type)
      self.send(@selector_type, line_item)
    else
      raise RuntimeError.new('Invalid product selector type')
    end
  end

  def tag(line_item)
    product_tags = line_item.variant.product.tags.map { |tag| tag.downcase.strip }
    @selectors = @selectors.map { |selector| selector.downcase.strip }
    (@selectors & product_tags).send(@comparator)
  end

  def type(line_item)
    @selectors = @selectors.map { |selector| selector.downcase.strip }
    (@match_type == :include) == @selectors.include?(line_item.variant.product.product_type.downcase.strip)
  end

  def vendor(line_item)
    @selectors = @selectors.map { |selector| selector.downcase.strip }
    (@match_type == :include) == @selectors.include?(line_item.variant.product.vendor.downcase.strip)
  end

  def product_id(line_item)
    (@match_type == :include) == @selectors.include?(line_item.variant.product.id)
  end

  def variant_id(line_item)
    (@match_type == :include) == @selectors.include?(line_item.variant.id)
  end

  def subscription(line_item)
    !line_item.selling_plan_id.nil?
  end
end

# ================================================================
# CountrySelector
#
# Finds whether the supplied country code matches the entered
# strings.
# ================================================================
class CountrySelector
  def initialize(match_type, countries)
    @match_type = match_type
    @countries = countries.map { |country| country.upcase.strip }
  end

  def match?(country_code)
    if @match_type == :all
      true
    else
      (@match_type == :include) == @countries.any? { |country| country_code.upcase.strip == country }
    end
  end
end

# ================================================================
# RateNameSelector
#
# Finds whether the supplied rate name matches any of the entered
# names.
# ================================================================
class RateNameSelector
  def initialize(match_type, rate_names)
    @match_type = match_type
    @comparator = match_type == :exact ? '==' : 'include?'
    @rate_names = rate_names&.map { |rate_name| rate_name.downcase.strip }
  end

  def match?(shipping_rate)
    if @match_type == :all
      true
    else
      @rate_names.any? { |name| shipping_rate.name.downcase.send(@comparator, name) }
    end
  end
end

# ================================================================
# HideRatesForProductCountryCampaign
#
# If the cart contains any matching items, and we have a matching
# country, the entered rate(s) are hidden.
# ================================================================
class HideRatesForProductCountryCampaign
  def initialize(campaigns)
    @campaigns = campaigns
  end

  def run(cart, shipping_rates)
    address = cart.shipping_address

    return if address.nil?

    @campaigns.each do |campaign|
      product_selector = ProductSelector.new(
        campaign[:product_selector_match_type],
        campaign[:product_selector_type],
        campaign[:product_selectors],
      )

      country_selector = CountrySelector.new(campaign[:country_code_match_type], campaign[:country_codes])
      product_match = cart.line_items.any? { |line_item| product_selector.match?(line_item) }
      country_match = country_selector.match?(address.country_code)

      next unless product_match && country_match

      rate_name_selector = RateNameSelector.new(
        campaign[:rate_match_type],
        campaign[:rate_names],
      )

      shipping_rates.delete_if do |shipping_rate|
        rate_name_selector.match?(shipping_rate)
      end
    end
  end
end

CAMPAIGNS = [
  HideRatesForProductCountryCampaign.new(HIDE_RATES_FOR_PRODUCT_AND_COUNTRY),
]

CAMPAIGNS.each do |campaign|
  campaign.run(Input.cart, Input.shipping_rates)
end

Output.shipping_rates = Input.shipping_rates