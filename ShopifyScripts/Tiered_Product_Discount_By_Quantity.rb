# ================================ Customizable Settings ================================
# ================================================================
# Tiered Product Discount by Quantity
#
# If the total quantity of matching items is greater than (or
# equal to) an entered threshold, the associated discount is
# applied to each matching item.
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
#       - ':all' for all products
#   - 'product_selectors' is a list of identifiers (from above) for
#     qualifying products. Product/Variant ID lists should only
#     contain numbers (ie. no quotes). If ':all' is used, this
#     can also be 'nil'.
#   - 'tiers' is a list of tiers where:
#     - 'quantity' is the minimum quantity you need to buy to
#       qualify
#     - 'discount_type' is the type of discount to provide. Can be
#       either:
#         - ':percent'
#         - ':dollar'
#     - 'discount_amount' is the percentage/dollar discount to
#       apply (per item)
#     - 'discount_message' is the message to show when a discount
#       is applied
# ================================================================
PRODUCT_DISCOUNT_TIERS = [
  {
    product_selector_match_type: :include,
    product_selector_type: :tag,
    product_selectors: ["your_tag"],
    tiers: [
      {
        quantity: 2,
        discount_type: :percent,
        discount_amount: 10,
        discount_message: '10% off for 2+',
      },
      {
        quantity: 5,
        discount_type: :percent,
        discount_amount: 15,
        discount_message: '15% off for 5+',
      },
    ],
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

  def all(line_item)
    true
  end
end

# ================================================================
# DiscountApplicator
#
# Applies the entered discount to the supplied line item.
# ================================================================
class DiscountApplicator
  def initialize(discount_type, discount_amount, discount_message)
    @discount_type = discount_type
    @discount_message = discount_message

    @discount_amount = if discount_type == :percent
      1 - (discount_amount * 0.01)
    else
      Money.new(cents: 100) * discount_amount
    end
  end

  def apply(line_item)
    new_line_price = if @discount_type == :percent
      line_item.line_price * @discount_amount
    else
      [line_item.line_price - (@discount_amount * line_item.quantity), Money.zero].max
    end

    line_item.change_line_price(new_line_price, message: @discount_message)
  end
end

# ================================================================
# TieredProductDiscountByQuantityCampaign
#
# If the total quantity of matching items is greater than (or
# equal to) an entered threshold, the associated discount is
# applied to each matching item.
# ================================================================
class TieredProductDiscountByQuantityCampaign
  def initialize(campaigns)
    @campaigns = campaigns
  end

  def run(cart)
    @campaigns.each do |campaign|
      product_selector = ProductSelector.new(
        campaign[:product_selector_match_type],
        campaign[:product_selector_type],
        campaign[:product_selectors],
      )

      applicable_items = cart.line_items.select { |line_item| product_selector.match?(line_item) }

      next if applicable_items.nil?

      total_applicable_quantity = applicable_items.map(&:quantity).reduce(0, :+)
      tiers = campaign[:tiers].sort_by { |tier| tier[:quantity] }.reverse
      applicable_tier = tiers.find { |tier| tier[:quantity] <= total_applicable_quantity }

      next if applicable_tier.nil?

      discount_applicator = DiscountApplicator.new(
        applicable_tier[:discount_type],
        applicable_tier[:discount_amount],
        applicable_tier[:discount_message]
      )

      applicable_items.each do |line_item|
        discount_applicator.apply(line_item)
      end
    end
  end
end

CAMPAIGNS = [
  TieredProductDiscountByQuantityCampaign.new(PRODUCT_DISCOUNT_TIERS),
]

CAMPAIGNS.each do |campaign|
  campaign.run(Input.cart)
end

Output.cart = Input.cart